#!/usr/bin/env node
// `/relay-update`'s script, in a project's copy as `.agents/relay/update.mjs`. It merges the newest release into the
// copy with the person's own edits, three ways: the release named in `RELEASE` is the base. A file only the release
// changed takes the release's text, a file only the person changed keeps theirs, and a file both changed is merged by
// `git merge-file`. Lines both changed are a clash, which the person settles before anything is written.
//   check              the newest release, and the files it changes, or up_to_date
//   plan               what an update does to each file; writes nothing
//   show <path>        a clash's file, with both sides marked
//   apply [--choose <path>=mine|release|both ...]   writes the update, then RELEASE, the skill links and the hooks
// `--into <project>` names the project, else this folder's git project. `--releases <folder>` reads releases from
// `<folder>/<version>/` in place of GitHub, for tests and a trial.
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { COPY, gitProject, HOOK_FILES, linkSkills, mergeHooks, readRelease, releaseFiles, releaseRef, releaseVersion,
  writeRelease } from './install.mjs';

const self = fileURLToPath(import.meta.url);
export const REPOSITORY = 'https://github.com/matthewwong525/RelayEverything';
export const TAG = /^relay-v(\d+\.\d+\.\d+)$/;
export const CHOICES = ['mine', 'release', 'both'];
export const USAGE = 'usage: update.mjs check | plan | show <path> | apply [--choose <path>=mine|release|both ...] '
  + '[--into <project>] [--releases <folder>]';
const NOT_INSTALLED = 'Relay Everything is not installed in this project. Follow https://relayeverything.com/install/ to install it.';

/** Below zero when `a` is older than `b`, zero when the same, above zero when newer. */
export function compareVersions(a, b) {
  const [x, y] = [a, b].map(version => String(version).split('.').map(Number));
  for (let at = 0; at < 3; at += 1) if ((x[at] ?? 0) !== (y[at] ?? 0)) return (x[at] ?? 0) - (y[at] ?? 0);
  return 0;
}

const newestOf = versions => versions.filter(version => /^\d+\.\d+\.\d+$/.test(version)).sort(compareVersions).at(-1) ?? null;

/** Releases from a folder that holds one release per version, as `<version>/`. */
export function folderReleases(dir) {
  return {
    newest: async () => newestOf(readdirSync(dir)),
    fetch: async version => {
      const found = join(dir, version);
      if (!existsSync(join(found, 'VERSION'))) throw new Error(`Release ${version} is not in ${dir}.`);
      return { dir: found, ref: releaseRef(found, version) };
    },
  };
}

/** Releases from the public repository: its `relay-v<version>` tags, each tarball's `plugin/` folder. */
export function githubReleases({ fetcher = fetch, work = mkdtempSync(join(tmpdir(), 'relay-update-')) } = {}) {
  let tags;
  const listTags = () => {
    tags ??= new Map(execFileSync('git', ['ls-remote', '--tags', '--refs', REPOSITORY, 'relay-v*'], { encoding: 'utf8' })
      .split('\n').map(line => line.split('\t')).filter(([, ref]) => ref)
      .map(([sha, ref]) => [ref.replace('refs/tags/', ''), sha]).filter(([tag]) => TAG.test(tag))
      .map(([tag, sha]) => [TAG.exec(tag)[1], sha]));
    return tags;
  };
  const fetched = new Map();
  return {
    work,
    newest: async () => newestOf([...listTags().keys()]),
    fetch: async version => {
      if (fetched.has(version)) return fetched.get(version);
      const sha = listTags().get(version);
      if (!sha) throw new Error(`Relay Everything has no release ${version}.`);
      const response = await fetcher(`https://codeload.github.com/matthewwong525/RelayEverything/tar.gz/refs/tags/relay-v${version}`);
      if (!response.ok) throw new Error(`GitHub did not send release ${version}: ${response.status}.`);
      const into = join(work, version);
      mkdirSync(into, { recursive: true });
      const tarball = join(work, `${version}.tar.gz`);
      writeFileSync(tarball, Buffer.from(await response.arrayBuffer()));
      execFileSync('tar', ['-xzf', tarball, '-C', into], { stdio: 'ignore' });
      const [top] = readdirSync(into);
      const dir = join(into, top, 'plugin');
      if (!existsSync(join(dir, 'VERSION'))) throw new Error(`Release ${version} has no plugin folder.`);
      fetched.set(version, { dir, ref: sha });
      return fetched.get(version);
    },
    close: () => rmSync(work, { recursive: true, force: true }),
  };
}

const read = (dir, path) => {
  try {
    return readFileSync(join(dir, path));
  } catch {
    return null;
  }
};
const equal = (a, b) => (a === null || b === null ? a === b : a.equals(b));

/**
 * Merges the person's file and the release's from their base with `git merge-file`: `{ text, clashes }`. `choice` keeps
 * mine, the release's or both sides' lines where they clash; with none, the clash stays marked.
 */
export function mergeText(mine, base, release, choice) {
  const dir = mkdtempSync(join(tmpdir(), 'relay-merge-'));
  try {
    const files = [['mine', mine], ['base', base], ['release', release]].map(([name, text]) => {
      writeFileSync(join(dir, name), text ?? '');
      return join(dir, name);
    });
    const flag = { mine: ['--ours'], release: ['--theirs'], both: ['--union'] }[choice] ?? [];
    const result = spawnSync('git', ['merge-file', '-p', ...flag, '-L', 'yours', '-L', 'base', '-L', 'release', ...files]);
    if (result.status === null || result.status < 0 || result.error) throw new Error('git merge-file did not run.');
    return { text: result.stdout, clashes: result.status };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/**
 * What an update does to each file of the copy in `copy`, from the release in `base` to the one in `next`. Each step is
 * `{ path, action, text }`: `take` the release's change, `add` a new file, `delete` one the release removed, `keep` the
 * person's change, `merge` both changes cleanly, or `clash` where both changed the same lines. A file nobody changed
 * has no step. `text` is what the file becomes, or null when it goes; a clash with no choice holds both, marked.
 */
export function planFiles({ copy, base, next, choices = {} }) {
  const paths = [...new Set([...releaseFiles(base), ...releaseFiles(next), ...releaseFiles(copy)])].sort();
  const steps = [];
  for (const path of paths) {
    const [was, now, mine] = [read(base, path), read(next, path), read(copy, path)];
    // The person already has the release's text.
    if (equal(mine, now)) continue;
    if (equal(was, now)) {
      // Only the person changed it; a file only the person added needs no word.
      if (was !== null) steps.push({ path, action: 'keep', text: mine });
      continue;
    }
    if (equal(mine, was)) {
      steps.push({ path, action: now === null ? 'delete' : was === null ? 'add' : 'take', text: now });
      continue;
    }
    const choice = choices[path];
    if (mine === null || now === null) {
      // One side deleted the file and the other changed it: the person chooses which.
      const text = choice === 'release' ? now : choice === 'mine' ? mine : mine ?? now;
      steps.push({ path, action: 'clash', clashes: 1, kind: mine === null ? 'you deleted it' : 'the release deleted it', text, choice });
      continue;
    }
    const merged = mergeText(mine, was, now);
    if (!merged.clashes) {
      steps.push({ path, action: 'merge', text: merged.text });
      continue;
    }
    steps.push({ path, action: 'clash', clashes: merged.clashes, text: choice ? mergeText(mine, was, now, choice).text : merged.text, choice });
  }
  return steps;
}

/** The project, its release, the newest release, and the folders of both, for one run. */
async function prepare({ into, releases }) {
  const project = gitProject(into ?? process.cwd());
  const had = project && readRelease(project);
  if (!had) return { lines: [NOT_INSTALLED], code: 1 };
  const newest = await releases.newest();
  if (!newest) return { lines: ['No Relay Everything release was found.'], code: 1 };
  if (compareVersions(newest, had.version) <= 0) return { lines: [`up_to_date=${had.version}`], code: 0 };
  const [base, next] = [await releases.fetch(had.version), await releases.fetch(newest)];
  return { project, had, newest, base, next, copy: join(project, COPY) };
}

const LABEL = { take: 'take', add: 'add', delete: 'delete', keep: 'keep', merge: 'merge', clash: 'clash' };

/** Runs one command: `{ code, lines }`. */
export async function update(command, { into, releases, choices = {}, path } = {}) {
  if (!['check', 'plan', 'show', 'apply'].includes(command)) return { code: 2, lines: [USAGE] };
  const ready = await prepare({ into, releases });
  if (ready.lines) return ready;
  const { project, had, newest, base, next, copy } = ready;
  const head = `current=${had.version} newest=${newest}`;
  if (command === 'check') {
    const changed = [...new Set([...releaseFiles(base.dir), ...releaseFiles(next.dir)])].sort()
      .filter(file => !equal(read(base.dir, file), read(next.dir, file)));
    return { code: 0, lines: [head, ...changed.map(file => `changed=${file}`)] };
  }
  const steps = planFiles({ copy, base: base.dir, next: next.dir, choices });
  if (command === 'show') {
    const step = steps.find(found => found.path === path && found.action === 'clash');
    if (!step) return { code: 1, lines: [`${path ?? 'That file'} has no clash.`] };
    return { code: 0, lines: step.kind ? [`${path}: ${step.kind}, and the other side changed it.`] : [String(step.text).replace(/\n$/, '')] };
  }
  const describe = step => `${LABEL[step.action]}=${step.path}${step.action === 'clash'
    ? ` ${step.kind ?? `places=${step.clashes}`}${step.choice ? ` chosen=${step.choice}` : ''}` : ''}`;
  if (command === 'plan') return { code: 0, lines: [head, ...steps.map(describe)] };
  const open = steps.filter(step => step.action === 'clash' && !CHOICES.includes(step.choice));
  if (open.length) {
    return { code: 1, lines: ['Nothing was written. Each clash needs a choice:',
      ...open.map(step => `clash=${step.path}: --choose ${step.path}=mine|release|both`)] };
  }
  for (const step of steps.filter(found => found.action !== 'keep')) {
    const file = join(copy, step.path);
    if (step.text === null) rmSync(file, { force: true });
    else {
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, step.text);
    }
  }
  writeRelease(project, releaseVersion(next.dir), next.ref);
  // An older release's hook groups go when the new one no longer has them; the person's own stay.
  const remove = Object.fromEntries(HOOK_FILES.map(([from]) => {
    try {
      return [from, JSON.parse(readFileSync(join(base.dir, 'hooks', from), 'utf8')).hooks ?? {}];
    } catch {
      return [from, {}];
    }
  }));
  const hooks = mergeHooks(project, remove);
  const links = linkSkills(project);
  return { code: 0, lines: [`updated=${newest}`, ...steps.filter(step => step.action !== 'keep').map(describe),
    ...links.linked.map(link => `linked=${link}`), ...links.removed.map(link => `unlinked=${link}`),
    ...links.skipped.map(link => `skipped=${link} (another skill has this name)`), ...hooks.map(file => `hooks=${file}`)] };
}

/** The command line: the command, its path, `--into`, `--releases`, and each `--choose <path>=<choice>`. */
export function parse(args) {
  const parsed = { command: args[0], choices: {} };
  for (let at = 1; at < args.length; at += 1) {
    const arg = args[at];
    if (arg === '--into' || arg === '--releases') parsed[arg.slice(2)] = args[(at += 1)];
    else if (arg === '--choose') {
      const [, file, choice] = /^(.+)=([a-z]+)$/.exec(args[(at += 1)] ?? '') ?? [];
      if (file && CHOICES.includes(choice)) parsed.choices[file] = choice;
      else parsed.bad = true;
    } else if (parsed.path === undefined && !arg.startsWith('--')) parsed.path = arg;
    else parsed.bad = true;
  }
  return parsed;
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const parsed = parse(process.argv.slice(2));
  const releases = parsed.releases ? folderReleases(parsed.releases) : githubReleases();
  try {
    const { code, lines } = parsed.bad ? { code: 2, lines: [USAGE] } : await update(parsed.command, { ...parsed, releases });
    for (const line of lines) console.log(line);
    process.exitCode = code;
  } catch (error) {
    console.log(`The update stopped: ${error.message} Nothing was written.`);
    process.exitCode = 1;
  } finally {
    releases.close?.();
  }
}
