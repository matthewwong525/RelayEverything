#!/usr/bin/env node
// `node install.mjs --into <project>`: copies this release of Relay Everything into a git project, as `.agents/relay/`,
// the person's own files. It writes `RELEASE`, links each skill as `relay-<name>` for Claude Code and Codex, and adds
// Relay Everything's hook groups to `.claude/settings.json` and `.codex/hooks.json`, keeping every other entry. A
// project that has the copy changes nothing: `/relay-update` brings a new release. `update.mjs` reuses the links and
// the hooks. No key, chat or state goes in the copy: they stay in this computer's Relay Everything folder.
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, readlinkSync, realpathSync, rmSync, symlinkSync,
  writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { keyFile } from './lib/config.mjs';

const self = fileURLToPath(import.meta.url);
/** The folder this script runs from: a release, the plugin, or a project's copy. */
export const SOURCE = dirname(self);
/** Where the copy sits in a project. */
export const COPY = join('.agents', 'relay');
export const USAGE = 'usage: install.mjs --into <project>';
/** Not copied: the plugin's own manifest and move skill, the tests, and the release's version, which RELEASE carries. */
const LEFT_OUT = ['.claude-plugin/', 'test/', 'node_modules/', 'skills/move/', 'VERSION', 'RELEASE'];
/** Each app's hooks file in the copy, and the project's settings file it goes into. */
export const HOOK_FILES = [['claude.json', join('.claude', 'settings.json')], ['codex.json', join('.codex', 'hooks.json')]];

const left = path => path.split('/').at(-1) === '.DS_Store' || LEFT_OUT.some(out => (out.endsWith('/') ? path.startsWith(out) : path === out));

/** Each file of a release or copy, as a path with `/`, sorted, less what the copy leaves out. */
export function releaseFiles(dir) {
  return readdirSync(dir, { withFileTypes: true, recursive: true }).filter(entry => entry.isFile())
    .map(entry => relative(dir, join(entry.parentPath ?? entry.path, entry.name)).split(sep).join('/'))
    .filter(path => !left(path)).sort();
}

/** The release's version, from its `VERSION` file. */
export const releaseVersion = (dir = SOURCE) => readFileSync(join(dir, 'VERSION'), 'utf8').trim();

/** `RELEASE` of a project's copy as `{ version, ref }`, or null when the project has no copy. */
export function readRelease(project) {
  try {
    const [version, ref = ''] = readFileSync(join(project, COPY, 'RELEASE'), 'utf8').trim().split(/\s+/);
    return version ? { version, ref } : null;
  } catch {
    return null;
  }
}

export const writeRelease = (project, version, ref) => writeFileSync(join(project, COPY, 'RELEASE'), `${version} ${ref}\n`);

/** The commit a release folder came from, when it is in a git checkout, else its tag. */
export function releaseRef(dir, version) {
  try {
    execFileSync('git', ['-C', dir, 'ls-files', '--error-unmatch', 'VERSION'], { stdio: 'ignore' });
    return execFileSync('git', ['-C', dir, 'rev-parse', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return `relay-v${version}`;
  }
}

/** The skills of a copy: each folder in `skills/` with a `SKILL.md`. */
export function skillNames(copy) {
  try {
    return readdirSync(join(copy, 'skills'), { withFileTypes: true })
      .filter(entry => entry.isDirectory() && existsSync(join(copy, 'skills', entry.name, 'SKILL.md'))).map(entry => entry.name).sort();
  } catch {
    return [];
  }
}

const real = path => {
  try {
    return realpathSync(path);
  } catch {
    return resolve(path);
  }
};

/** The skill folders each app reads, with the link target of skill `name` in each; one when they are the same folder. */
function skillDirs(project) {
  const claude = join(project, '.claude', 'skills');
  const codex = join(project, '.agents', 'skills');
  const dirs = [[claude, name => `../../.agents/relay/skills/${name}`]];
  if (!existsSync(join(project, '.claude')) || !existsSync(join(project, '.agents'))
    || real(join(project, '.claude')) !== real(join(project, '.agents'))) dirs.push([codex, name => `../relay/skills/${name}`]);
  return dirs;
}

const linkAt = path => {
  try {
    return lstatSync(path).isSymbolicLink() ? readlinkSync(path) : '';
  } catch {
    return null;
  }
};

/**
 * Links each skill of the copy as `relay-<name>` in `.claude/skills/` and, for Codex, `.agents/skills/`. A name another
 * skill already has is skipped. A `relay-<name>` link to a skill the copy no longer has goes. Answers `{ linked, skipped,
 * removed }`, each a list of paths in the project.
 */
export function linkSkills(project) {
  const names = skillNames(join(project, COPY));
  const result = { linked: [], skipped: [], removed: [] };
  for (const [dir, target] of skillDirs(project)) {
    for (const name of names) {
      const path = join(dir, `relay-${name}`);
      const now = linkAt(path);
      if (now === target(name)) continue;
      if (now !== null) {
        result.skipped.push(relative(project, path));
        continue;
      }
      mkdirSync(dir, { recursive: true });
      symlinkSync(target(name), path, 'dir');
      result.linked.push(relative(project, path));
    }
    let entries = [];
    try {
      entries = readdirSync(dir);
    } catch {
      // No skills folder: nothing to remove.
    }
    for (const entry of entries.filter(found => found.startsWith('relay-'))) {
      const name = entry.slice('relay-'.length);
      if (!names.includes(name) && linkAt(join(dir, entry)) === target(name)) {
        rmSync(join(dir, entry));
        result.removed.push(relative(project, join(dir, entry)));
      }
    }
  }
  return result;
}

const readJson = path => (existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : {});
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/**
 * Merges the copy's hook groups into each app's settings file, made if missing: each group not there yet is added, each
 * group in `remove` (an older release's, per file name) goes, and every other key and group stays. Answers the files it
 * changed. A settings file that is not JSON stops it before anything is written.
 */
export function mergeHooks(project, remove = {}) {
  const plans = HOOK_FILES.map(([from, to]) => {
    const add = readJson(join(project, COPY, 'hooks', from)).hooks ?? {};
    const path = join(project, to);
    let file;
    try {
      file = readJson(path);
    } catch {
      throw new Error(`${to} is not JSON, so Relay Everything's hooks were not added to it. Fix it, then run this again.`);
    }
    return { to, path, add, file, before: JSON.stringify(file), gone: remove[from] ?? {} };
  });
  const changed = [];
  for (const { to, path, add, file, before, gone } of plans) {
    file.hooks ??= {};
    for (const [event, groups] of Object.entries(gone)) {
      if (!Array.isArray(file.hooks[event])) continue;
      file.hooks[event] = file.hooks[event].filter(group => !groups.some(old => same(old, group)) || (add[event] ?? []).some(kept => same(kept, group)));
      if (!file.hooks[event].length) delete file.hooks[event];
    }
    for (const [event, groups] of Object.entries(add)) {
      const have = (file.hooks[event] ??= []);
      for (const group of groups) if (!have.some(found => same(found, group))) have.push(group);
    }
    if (JSON.stringify(file) === before) continue;
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, `${JSON.stringify(file, null, 2)}\n`);
    changed.push(to);
  }
  return changed;
}

/** The project's git top folder, or null when `dir` is not in a git project. */
export function gitProject(dir) {
  try {
    return execFileSync('git', ['-C', dir, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
}

/** Installs the release in `source` into `into`. Answers `{ code, lines }`. */
export function install({ into, source = SOURCE, env = process.env }) {
  if (!into) return { code: 2, lines: [USAGE] };
  const project = existsSync(into) ? gitProject(resolve(into)) : null;
  if (!project) return { code: 1, lines: [`${into} is not a git project. Relay Everything installs into the top folder of a git project.`] };
  const had = readRelease(project);
  if (had) return { code: 0, lines: [`already installed: ${had.version}; type /relay-update`] };
  const version = releaseVersion(source);
  const copy = join(project, COPY);
  if (real(source) === real(copy)) return { code: 1, lines: ['This is the project\'s own copy. Run the install from a release.'] };
  for (const path of releaseFiles(source)) {
    mkdirSync(dirname(join(copy, path)), { recursive: true });
    cpSync(join(source, path), join(copy, path));
  }
  let hooks;
  try {
    hooks = mergeHooks(project);
  } catch (error) {
    rmSync(copy, { recursive: true, force: true });
    return { code: 1, lines: [error.message] };
  }
  writeRelease(project, version, releaseRef(source, version));
  const links = linkSkills(project);
  return { code: 0, lines: [
    `installed=${version}`,
    `copy=${COPY.split(sep).join('/')}`,
    ...links.linked.map(path => `linked=${path}`),
    ...links.skipped.map(path => `skipped=${path} (another skill has this name)`),
    ...hooks.map(path => `hooks=${path}`),
    `connected=${existsSync(keyFile(env)) ? 'yes' : 'no; type /relay-connect'}`,
    'In Codex, trust this project when it asks, so its hooks run.',
  ] };
}

/** `--name value` options, and the rest. */
export function options(args) {
  const named = {};
  const rest = [];
  for (let at = 0; at < args.length; at += 1) {
    if (args[at].startsWith('--')) named[args[at].slice(2)] = args[at + 1]?.startsWith('--') ? true : args[(at += 1)] ?? true;
    else rest.push(args[at]);
  }
  return { named, rest };
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const { named } = options(process.argv.slice(2));
  const { code, lines } = install({ into: typeof named.into === 'string' ? named.into : undefined });
  for (const line of lines) console.log(line);
  process.exitCode = code;
}
