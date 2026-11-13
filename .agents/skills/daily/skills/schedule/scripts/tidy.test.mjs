// Run with: node --test .claude/skills/daily/skills/schedule/scripts/tidy.test.mjs
// The tidy-up closes no workspace: an idle, saved Paseo worktree stays open after `tidy.mjs sweep`.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const TIDY = path.join(path.dirname(fileURLToPath(import.meta.url)), 'tidy.mjs');
const GIT = ['-c', 'user.name=Tidy Test', '-c', 'user.email=tidy@example.com', '-c', 'commit.gpgsign=false', '-c', 'init.defaultBranch=main'];
const git = (cwd, ...args) => execFileSync('git', [...GIT, '-C', cwd, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();

// A fake `paseo` that shows one idle worktree, answers every call, and logs each call's arguments as one line.
const FAKE_PASEO = `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2).filter(arg => arg !== '--json');
fs.appendFileSync(process.env.FAKE_PASEO_LOG, args.join(' ') + '\\n');
const wt = process.env.FAKE_WORKTREE;
const old = '2020-01-01T00:00:00.000Z';
let out = {};
if (args[0] === 'workspace' && args[1] === 'ls') out = [{ workspaceId: 'ws-old', cwd: wt, isolation: 'worktree', name: 'old-chat' }];
else if (args[0] === 'ls') out = [{ id: 'agent-old', status: 'idle', cwd: wt }];
else if (args[0] === 'inspect') out = { UpdatedAt: old };
process.stdout.write(JSON.stringify(out));
`;

function setUp() {
  const base = realpathSync(mkdtempSync(path.join(tmpdir(), 'tidy-test-')));
  const remote = path.join(base, 'remote.git');
  const primary = path.join(base, 'primary');
  const paseoHome = path.join(base, 'paseo');
  const worktree = path.join(paseoHome, 'worktrees', 'repo', 'old-chat');
  const temp = path.join(base, 'tmp');
  mkdirSync(primary);
  mkdirSync(temp);
  mkdirSync(path.dirname(worktree), { recursive: true });
  execFileSync('git', [...GIT, 'init', '-q', '--bare', remote]);
  git(primary, 'init', '-q');
  writeFileSync(path.join(primary, 'README.md'), 'test\n');
  git(primary, 'add', 'README.md');
  git(primary, 'commit', '-q', '-m', 'start');
  git(primary, 'remote', 'add', 'origin', remote);
  git(primary, 'push', '-q', 'origin', 'main');
  git(primary, 'worktree', 'add', '-q', '-b', 'old-chat', worktree);
  git(worktree, 'push', '-q', 'origin', 'old-chat');
  const old = new Date('2020-01-01T00:00:00Z');
  utimesSync(path.join(git(worktree, 'rev-parse', '--path-format=absolute', '--git-dir'), 'HEAD'), old, old);
  const bin = path.join(base, 'paseo-bin');
  writeFileSync(bin, FAKE_PASEO);
  chmodSync(bin, 0o755);
  return { base, primary, worktree, paseoHome, temp, bin, log: path.join(base, 'paseo.log') };
}

test('the sweep closes no idle, saved workspace', t => {
  const s = setUp();
  t.after(() => rmSync(s.base, { recursive: true, force: true }));
  const env = { ...process.env, TIDY_PASEO_BIN: s.bin, PASEO_HOME: s.paseoHome, TMPDIR: s.temp, FAKE_PASEO_LOG: s.log, FAKE_WORKTREE: s.worktree };
  delete env.PASEO_AGENT_ID;
  const out = JSON.parse(execFileSync(process.execPath, [TIDY, 'sweep'], { cwd: s.primary, env, encoding: 'utf8' }));
  assert.equal(out.ok, true);
  assert.deepEqual(out.closed, []);
  const calls = existsSync(s.log) ? readFileSync(s.log, 'utf8') : '';
  assert.doesNotMatch(calls, /workspace archive/);
  assert.ok(existsSync(s.worktree), 'the worktree is still on disk');
});
