import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, readlinkSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { install, linkSkills, readRelease, releaseFiles, SOURCE } from '../install.mjs';
import { gitProject, OWN_HOOK, relayHome, SECRET } from './fake.mjs';

const INSTALL = fileURLToPath(new URL('../install.mjs', import.meta.url));
const SKILLS = ['ask', 'build', 'connect', 'memory', 'save', 'saving', 'update'];
/** Every file and link under `dir`, with its text or link target, to compare two runs. */
function snapshot(dir) {
  const out = {};
  const walk = at => {
    for (const entry of readdirSync(at, { withFileTypes: true })) {
      const path = join(at, entry.name);
      if (entry.name === '.git') continue;
      if (entry.isSymbolicLink()) out[relative(dir, path)] = `-> ${readlinkSync(path)}`;
      else if (entry.isDirectory()) walk(path);
      else out[relative(dir, path)] = readFileSync(path, 'utf8');
    }
  };
  walk(dir);
  return out;
}

test('an install copies the release into .agents/relay, links each skill for both apps, and adds the hooks beside the person\'s own', () => {
  const project = gitProject();
  const env = relayHome({ connected: false });
  const { code, lines } = install({ into: project, env });
  assert.equal(code, 0);
  assert.equal(lines[0], 'installed=0.8.0');
  assert.ok(lines.includes('connected=no; type /relay-connect'));
  assert.equal(lines.at(-1), 'In Codex, trust this project when it asks, so its hooks run.');
  const copy = join(project, '.agents', 'relay');
  assert.deepEqual(releaseFiles(copy), releaseFiles(SOURCE));
  for (const gone of ['.claude-plugin', 'test', 'skills/move', 'VERSION']) assert.ok(!existsSync(join(copy, gone)), gone);
  for (const kept of ['bin/hook.mjs', 'update.mjs', 'install.mjs', 'hooks/claude.json', 'memory/VERSION', 'build/PROMPT.md']) {
    assert.ok(existsSync(join(copy, kept)), kept);
  }
  assert.deepEqual(readRelease(project).version, '0.8.0');
  for (const name of SKILLS) {
    assert.equal(readlinkSync(join(project, '.claude', 'skills', `relay-${name}`)), `../../.agents/relay/skills/${name}`);
    assert.equal(readlinkSync(join(project, '.agents', 'skills', `relay-${name}`)), `../relay/skills/${name}`);
    assert.match(readFileSync(join(project, '.claude', 'skills', `relay-${name}`, 'SKILL.md'), 'utf8'), new RegExp(`^---\\nname: relay-${name}\\n`));
    assert.ok(existsSync(join(project, '.agents', 'skills', `relay-${name}`, 'SKILL.md')), name);
  }
  assert.ok(existsSync(join(project, '.claude', 'skills', 'notes', 'SKILL.md')));
  const settings = JSON.parse(readFileSync(join(project, '.claude', 'settings.json'), 'utf8'));
  assert.equal(settings.model, 'opus');
  assert.deepEqual(settings.hooks.PreToolUse[0], OWN_HOOK);
  assert.deepEqual(Object.keys(settings.hooks), ['PreToolUse', 'SessionStart', 'UserPromptSubmit', 'Stop', 'SessionEnd']);
  assert.match(settings.hooks.Stop[0].hooks[0].command, /^node "\$CLAUDE_PROJECT_DIR\/\.agents\/relay\/bin\/hook\.mjs" stop$/);
  const codex = JSON.parse(readFileSync(join(project, '.codex', 'hooks.json'), 'utf8'));
  assert.match(codex.hooks.SessionStart[0].hooks[0].command, /^node "\$\(git rev-parse --show-toplevel\)\/\.agents\/relay\/bin\/hook\.mjs"/);
});

test('a second install changes nothing and points to the update', () => {
  const project = gitProject();
  const env = relayHome();
  assert.equal(install({ into: project, env }).code, 0);
  const before = snapshot(project);
  // Run as a person runs it, from a folder inside the project.
  mkdirSync(join(project, 'src'));
  const printed = execFileSync(process.execPath, [INSTALL, '--into', join(project, 'src')], { env: { ...process.env, ...env }, encoding: 'utf8' });
  assert.equal(printed, 'already installed: 0.8.0; type /relay-update\n');
  assert.deepEqual(snapshot(project), before);
});

test('a skill name another skill has is skipped and said, and the rest are linked', () => {
  const project = gitProject();
  mkdirSync(join(project, '.claude', 'skills', 'relay-ask'));
  writeFileSync(join(project, '.claude', 'skills', 'relay-ask', 'SKILL.md'), 'mine');
  const { lines } = install({ into: project, env: relayHome() });
  assert.ok(lines.includes('skipped=.claude/skills/relay-ask (another skill has this name)'));
  assert.equal(readFileSync(join(project, '.claude', 'skills', 'relay-ask', 'SKILL.md'), 'utf8'), 'mine');
  assert.ok(lstatSync(join(project, '.claude', 'skills', 'relay-save')).isSymbolicLink());
  assert.ok(lstatSync(join(project, '.agents', 'skills', 'relay-ask')).isSymbolicLink());
});

test('where .claude is .agents, each skill gets one link', () => {
  const project = gitProject({ bare: true });
  mkdirSync(join(project, '.agents'));
  symlinkSync('.agents', join(project, '.claude'));
  assert.equal(install({ into: project, env: relayHome() }).code, 0);
  assert.equal(readlinkSync(join(project, '.agents', 'skills', 'relay-ask')), '../../.agents/relay/skills/ask');
  assert.ok(existsSync(join(project, '.claude', 'skills', 'relay-ask', 'SKILL.md')));
  // A second link run sees each link as its own.
  assert.deepEqual(linkSkills(project), { linked: [], skipped: [], removed: [] });
});

test('no file of the copy holds the key, after a connected computer installs', () => {
  const project = gitProject();
  const env = relayHome();
  const { lines } = install({ into: project, env });
  assert.ok(lines.includes('connected=yes'));
  const copy = join(project, '.agents', 'relay');
  for (const path of releaseFiles(copy)) {
    const text = readFileSync(join(copy, path), 'utf8');
    assert.ok(!text.includes(SECRET) && !/rek_[A-Za-z0-9_-]{43}/.test(text), path);
  }
  assert.ok(!existsSync(join(copy, 'computer.json')) && !existsSync(join(copy, 'state')));
});

test('an install refuses a folder outside git, and a settings file that is not JSON', () => {
  const outside = mkdtempSync(join(tmpdir(), 'relay-nogit-'));
  assert.deepEqual(install({ into: outside, env: relayHome() }).code, 1);
  assert.equal(existsSync(join(outside, '.agents')), false);
  assert.equal(install({ env: relayHome() }).code, 2);
  const project = gitProject();
  writeFileSync(join(project, '.claude', 'settings.json'), '{ "model": ');
  const { code, lines } = install({ into: project, env: relayHome() });
  assert.equal(code, 1);
  assert.match(lines[0], /^\.claude\/settings\.json is not JSON/);
  assert.equal(existsSync(join(project, '.agents', 'relay')), false);
  assert.equal(readFileSync(join(project, '.claude', 'settings.json'), 'utf8'), '{ "model": ');
});
