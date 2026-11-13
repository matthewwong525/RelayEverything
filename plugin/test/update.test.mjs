import assert from 'node:assert/strict';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { install, readRelease, SOURCE } from '../install.mjs';
import { compareVersions, folderReleases, mergeText, parse, planFiles, update } from '../update.mjs';
import { gitProject, OWN_HOOK, relayHome } from './fake.mjs';

const LINES = Array.from({ length: 12 }, (_, at) => `line ${at + 1}`);
const text = (...changes) => `${LINES.map((line, at) => changes.find(([n]) => n === at + 1)?.[1] ?? line).join('\n')}\n`;

/** A folder holding these files. */
function folder(files) {
  const dir = mkdtempSync(join(tmpdir(), 'relay-files-'));
  for (const [path, body] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), body);
  }
  return dir;
}

const edit = (dir, path, change) => writeFileSync(join(dir, path), change(readFileSync(join(dir, path), 'utf8')));

test('a plan takes the release\'s changes, keeps the person\'s, merges both, and marks a clash it does not settle', () => {
  const base = folder({ 'up.md': text(), 'mine.md': text(), 'both.md': text(), 'clash.md': text(), 'gone.md': text(), 'kept.md': text(), 'same.md': text() });
  const next = folder({ 'up.md': text([2, 'new 2']), 'mine.md': text(), 'both.md': text([11, 'release 11']), 'clash.md': text([5, 'release 5']),
    'kept.md': text([3, 'release 3']), 'same.md': text(), 'added.md': 'new\n' });
  const copy = folder({ 'up.md': text(), 'mine.md': text([7, 'mine 7']), 'both.md': text([1, 'mine 1']), 'clash.md': text([5, 'mine 5']),
    'gone.md': text(), 'same.md': text(), 'own.md': 'only mine\n' });
  const steps = planFiles({ copy, base, next });
  const by = Object.fromEntries(steps.map(step => [step.path, step]));
  assert.deepEqual(steps.map(step => `${step.action}=${step.path}`), ['add=added.md', 'merge=both.md', 'clash=clash.md', 'delete=gone.md',
    'clash=kept.md', 'keep=mine.md', 'take=up.md']);
  assert.equal(String(by['up.md'].text), text([2, 'new 2']));
  assert.equal(String(by['both.md'].text), text([1, 'mine 1'], [11, 'release 11']));
  assert.match(String(by['clash.md'].text), /^<<<<<<< yours\nmine 5\n=======\nrelease 5\n>>>>>>> release$/m);
  assert.equal(by['gone.md'].text, null);
  // The person deleted kept.md and the release changed it: a clash too, which keeps the release's file unless chosen.
  assert.equal(by['kept.md'].kind, 'you deleted it');
  // A plan writes nothing to the copy.
  assert.equal(readFileSync(join(copy, 'clash.md'), 'utf8'), text([5, 'mine 5']));
  assert.ok(existsSync(join(copy, 'gone.md')) && !existsSync(join(copy, 'added.md')));
  // Each choice settles the clash its way.
  const chosen = choice => String(planFiles({ copy, base, next, choices: { 'clash.md': choice } }).find(step => step.path === 'clash.md').text);
  assert.equal(chosen('mine'), text([5, 'mine 5']));
  assert.equal(chosen('release'), text([5, 'release 5']));
  assert.equal(chosen('both'), text([5, 'mine 5\nrelease 5']));
  assert.equal(planFiles({ copy, base, next, choices: { 'kept.md': 'mine' } }).find(step => step.path === 'kept.md').text, null);
  assert.equal(mergeText(Buffer.from('a\n'), Buffer.from('a\n'), Buffer.from('b\n')).clashes, 0);
});

/** Releases 0.8.0, this folder's, and 0.9.0, which changes a skill, a script, the hooks, and adds a skill. */
function releases() {
  const dir = mkdtempSync(join(tmpdir(), 'relay-releases-'));
  const now = join(dir, '0.8.0');
  cpSync(SOURCE, now, { recursive: true, filter: path => !path.startsWith(join(SOURCE, 'test')) });
  const next = join(dir, '0.9.0');
  cpSync(now, next, { recursive: true });
  writeFileSync(join(next, 'VERSION'), '0.9.0\n');
  edit(next, 'skills/ask/SKILL.md', body => `${body}\nA line from the release.\n`);
  edit(next, 'bin/saving.mjs', body => body.replace(/\n$/, '\n// The release ends here.\n'));
  edit(next, 'bin/hook.mjs', body => body.replace('export const END_WAIT = 60_000;', 'export const END_WAIT = 90_000;'));
  edit(next, 'hooks/claude.json', body => body.replace('" stop", "timeout": 10', '" stop", "timeout": 12'));
  rmSync(join(next, 'lib', 'daily-off.mjs'));
  mkdirSync(join(next, 'skills', 'tidy'));
  writeFileSync(join(next, 'skills', 'tidy', 'SKILL.md'), '---\nname: relay-tidy\ndescription: Tidy Relay Everything.\n---\n');
  return dir;
}

test('an update checks, plans with the person\'s edits, applies only with each clash chosen, and then is up to date', async () => {
  const dir = releases();
  const project = gitProject();
  assert.equal(install({ into: project, source: join(dir, '0.8.0'), env: relayHome() }).code, 0);
  assert.deepEqual(readRelease(project), { version: '0.8.0', ref: 'relay-v0.8.0' });
  const copy = join(project, '.agents', 'relay');
  // The person changes a skill, the top of a script, and the line the release changes too.
  edit(copy, 'skills/save/SKILL.md', body => `${body}\nMy own line.\n`);
  edit(copy, 'bin/saving.mjs', body => `// My note.\n${body}`);
  edit(copy, 'bin/hook.mjs', body => body.replace('export const END_WAIT = 60_000;', 'export const END_WAIT = 30_000;'));
  const options = { into: project, releases: folderReleases(dir) };

  const check = await update('check', options);
  assert.equal(check.lines[0], 'current=0.8.0 newest=0.9.0');
  for (const file of ['skills/ask/SKILL.md', 'bin/hook.mjs', 'lib/daily-off.mjs', 'skills/tidy/SKILL.md']) assert.ok(check.lines.includes(`changed=${file}`), file);
  assert.ok(!check.lines.includes('changed=VERSION'));

  const plan = await update('plan', options);
  assert.deepEqual(plan.lines, ['current=0.8.0 newest=0.9.0', 'clash=bin/hook.mjs places=1', 'merge=bin/saving.mjs', 'take=hooks/claude.json',
    'delete=lib/daily-off.mjs', 'take=skills/ask/SKILL.md', 'keep=skills/save/SKILL.md', 'add=skills/tidy/SKILL.md']);
  assert.match((await update('show', { ...options, path: 'bin/hook.mjs' })).lines[0],
    /<<<<<<< yours\nexport const END_WAIT = 30_000;\n=======\nexport const END_WAIT = 90_000;\n>>>>>>> release/);
  assert.equal((await update('show', { ...options, path: 'bin/saving.mjs' })).code, 1);

  const refused = await update('apply', options);
  assert.equal(refused.code, 1);
  assert.deepEqual(refused.lines.slice(1), ['clash=bin/hook.mjs: --choose bin/hook.mjs=mine|release|both']);
  assert.ok(existsSync(join(copy, 'lib', 'daily-off.mjs')));
  assert.equal(readRelease(project).version, '0.8.0');

  const applied = await update('apply', { ...options, choices: { 'bin/hook.mjs': 'mine' } });
  assert.equal(applied.code, 0);
  assert.equal(applied.lines[0], 'updated=0.9.0');
  const read = path => readFileSync(join(copy, path), 'utf8');
  assert.match(read('skills/ask/SKILL.md'), /A line from the release\.\n$/);
  assert.match(read('skills/save/SKILL.md'), /My own line\.\n$/);
  assert.match(read('bin/saving.mjs'), /^\/\/ My note\.\n[\s\S]*\/\/ The release ends here\.\n$/);
  assert.ok(read('bin/hook.mjs').includes('export const END_WAIT = 30_000;') && !read('bin/hook.mjs').includes('<<<<<<<'));
  assert.ok(!existsSync(join(copy, 'lib', 'daily-off.mjs')));
  assert.deepEqual(readRelease(project), { version: '0.9.0', ref: 'relay-v0.9.0' });
  assert.equal(readlinkSync(join(project, '.claude', 'skills', 'relay-tidy')), '../../.agents/relay/skills/tidy');
  assert.ok(applied.lines.includes('linked=.claude/skills/relay-tidy'));
  // The release's new Stop hook takes the old one's place; the person's own hook stays.
  const { hooks } = JSON.parse(readFileSync(join(project, '.claude', 'settings.json'), 'utf8'));
  assert.deepEqual(hooks.Stop.map(group => group.hooks[0].timeout), [12]);
  assert.deepEqual(hooks.PreToolUse[0], OWN_HOOK);

  assert.deepEqual((await update('check', options)).lines, ['up_to_date=0.9.0']);
});

test('an update in a project with no copy says how to install, and the command line reads each choice', async () => {
  const project = gitProject();
  assert.match((await update('check', { into: project, releases: folderReleases(releases()) })).lines[0], /not installed in this project/);
  assert.equal((await update('nothing', {})).code, 2);
  assert.deepEqual(parse(['apply', '--choose', 'bin/a.mjs=mine', '--choose', 'b.md=both', '--into', '/p']),
    { command: 'apply', choices: { 'bin/a.mjs': 'mine', 'b.md': 'both' }, into: '/p' });
  assert.equal(parse(['apply', '--choose', 'a=maybe']).bad, true);
  assert.equal(parse(['show', 'bin/hook.mjs']).path, 'bin/hook.mjs');
  assert.ok(compareVersions('0.10.0', '0.9.0') > 0 && compareVersions('0.8.0', '0.8.0') === 0);
});
