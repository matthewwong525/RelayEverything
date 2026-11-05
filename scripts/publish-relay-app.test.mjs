// Run with: node --test scripts/publish-relay-app.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { blocked, branchProblem, envSecrets, pushFolder } from './publish-relay-app.mjs';

const file = (path, text = 'hello') => ({ path, text });

test('an ordinary app passes', () => {
  assert.deepEqual(blocked([file('README.md'), file('lib/main.dart'), file('.env.example', 'API_URL=')], []), []);
});

test('key files and private notes are refused', () => {
  const paths = ['.env', 'android/.env.local', 'android/key.properties', 'android/upload.jks', 'notes/plan.md', 'todo.private.md'];
  assert.deepEqual(blocked(paths.map(path => file(path)), []).map(stop => stop.path), paths);
});

test('a key in the text is refused without echoing it', () => {
  const token = `ghp_${'a'.repeat(36)}`;
  const [stop] = blocked([file('lib/api.dart', `const t = "${token}";`)], []);
  assert.equal(stop.path, 'lib/api.dart');
  assert.ok(!JSON.stringify(stop).includes(token));
});

test('a value from .env is refused', () => {
  const secrets = envSecrets('CLOUDFLARE_API_TOKEN=abcdefgh12345678\nSHORT=1\nEMPTY=\n');
  assert.deepEqual(secrets, ['abcdefgh12345678']);
  assert.equal(blocked([file('lib/a.dart', 'x abcdefgh12345678 y')], secrets)[0].why, 'a value from .env');
});

test('Apple signing files are refused', () => {
  const paths = ['ios/AuthKey_ABC123.p8', 'ios/dist.cer', 'ios/dist.p12', 'ios/request.certSigningRequest', 'ios/Relay.mobileprovision', 'ios/Relay.provisionprofile'];
  assert.deepEqual(blocked(paths.map(path => file(path)), []).map(stop => stop.path), paths);
});

test('--branch takes a branch name other than main', () => {
  assert.equal(branchProblem(undefined), null);
  assert.equal(branchProblem('relay-app-first-version'), null);
  assert.match(branchProblem('main'), /leave out --branch/);
  assert.match(branchProblem('bad..name'), /not a branch name/);
});

test('a branch push leaves main as it was, and a second push builds on the branch', () => {
  const work = mkdtempSync(join(tmpdir(), 'relay-publish-test-'));
  const git = (...args) => execFileSync('git', args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
  const ident = ['-c', 'user.name=Test', '-c', 'user.email=test@example.com'];
  try {
    const remote = join(work, 'remote.git');
    git('init', '-q', '--bare', '-b', 'main', remote);
    const seed = join(work, 'seed');
    git('clone', '-q', remote, seed);
    writeFileSync(join(seed, 'README.md'), 'main\n');
    git('-C', seed, 'add', '-A');
    git(...ident, '-C', seed, 'commit', '-q', '-m', 'main');
    git('-C', seed, 'push', '-q', 'origin', 'HEAD:refs/heads/main');
    const main = git('-C', remote, 'rev-parse', 'main');
    const send = (n, text) => {
      const app = join(work, `app${n}`);
      const clone = join(work, `clone${n}`);
      mkdirSync(app);
      writeFileSync(join(app, 'README.md'), text);
      git('clone', '-q', remote, clone);
      git('-C', clone, 'config', 'user.name', 'Test');
      git('-C', clone, 'config', 'user.email', 'test@example.com');
      return pushFolder({ app, clone, branch: 'try', message: `push ${n}` });
    };
    assert.equal(send(1, 'first\n'), 'pushed');
    assert.equal(send(2, 'second\n'), 'pushed');
    assert.equal(send(3, 'second\n'), 'unchanged');
    assert.equal(git('-C', remote, 'rev-parse', 'main'), main);
    assert.equal(git('-C', remote, 'show', 'try:README.md'), 'second');
    assert.equal(git('-C', remote, 'rev-list', '--count', 'try'), '3');
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
