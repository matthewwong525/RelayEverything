// Run with: node --test scripts/public-check.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { blocked, checkHistory, checkTree, envSecrets, listNotes } from './public-check.mjs';

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), 'public-check.mjs');
const AUTHOR = 'author@relay.dev';
// Built here, so this file holds no key-shaped text of its own.
const TOKEN = `ghp_${'a'.repeat(36)}`;
const VALUE = 'abcdefgh12345678';

function repo(t) {
  const dir = mkdtempSync(join(tmpdir(), 'public-check-test-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', ['-C', dir, '-c', 'user.name=Author', '-c', `user.email=${AUTHOR}`, ...args], { encoding: 'utf8' }).trim();
  git('init', '-q', '-b', 'main');
  const commit = (files, message = 'save') => {
    for (const [path, body] of Object.entries(files)) {
      mkdirSync(dirname(join(dir, path)), { recursive: true });
      if (body === null) rmSync(join(dir, path));
      else writeFileSync(join(dir, path), body);
    }
    git('add', '-A');
    git('commit', '-q', '-m', message);
    return git('rev-parse', 'HEAD').slice(0, 10);
  };
  return { dir, commit };
}

const cli = (dir, ...args) => {
  try {
    return { code: 0, out: execFileSync('node', [SCRIPT, ...args], { cwd: dir, encoding: 'utf8' }) };
  } catch (error) {
    return { code: error.status, out: error.stdout };
  }
};

test('an ordinary project passes, .env.example and the author email too', t => {
  const { dir, commit } = repo(t);
  commit({ 'README.md': `Write to ${AUTHOR}.\n`, '.env.example': 'API_TOKEN=\n', 'app/.dev.vars.example': 'KEY=\n' });
  assert.deepEqual(checkTree(dir, [VALUE]), []);
  assert.deepEqual(checkHistory(dir, [VALUE]), []);
  assert.deepEqual(listNotes(dir), []);
  assert.equal(cli(dir, '--history').out.trim(), 'result=clean');
});

test('a key, a .p8 file and a .env value each refuse with commit:path, never the value', t => {
  const { dir, commit } = repo(t);
  const sha = commit({ 'lib/api.dart': `const t = "${TOKEN}";\n`, 'ios/AuthKey_ABC.p8': 'x\n', 'lib/cfg.dart': `x ${VALUE} y\n` });
  const hits = checkHistory(dir, envSecrets(`TOKEN=${VALUE}\nSHORT=1\n`));
  assert.deepEqual(hits.sort(), [
    `${sha}:ios/AuthKey_ABC.p8 (a key file or private note)`,
    `${sha}:lib/api.dart (text shaped like a key)`,
    `${sha}:lib/cfg.dart (a value from .env)`,
  ]);
  assert.ok(!JSON.stringify(hits).includes(TOKEN) && !JSON.stringify(hits).includes(VALUE));
});

test('a key removed by a later commit is still found in history, not in the tree', t => {
  const { dir, commit } = repo(t);
  const old = commit({ 'config.js': `token = "${TOKEN}"\n` });
  commit({ 'config.js': 'token = process.env.TOKEN\n' });
  assert.deepEqual(checkTree(dir, []), []);
  assert.deepEqual(checkHistory(dir, []), [`${old}:config.js (text shaped like a key)`]);
});

test('the command reads .env values on this computer, fails, and never prints them', t => {
  const { dir, commit } = repo(t);
  commit({ '.gitignore': '.env\n', 'app.js': `const id = "${VALUE}";\n` });
  writeFileSync(join(dir, '.env'), `CLOUDFLARE_API_TOKEN=${VALUE}\nCLOUDFLARE_ACCOUNT_ID=0123456789abcdef\n`);
  writeFileSync(join(dir, 'new.js'), `const a = "0123456789abcdef";\n`);
  for (const mode of ['--tree', '--history']) {
    const { code, out } = cli(dir, mode);
    assert.equal(code, 1);
    assert.match(out, /^result=refused .*app\.js \(a value from \.env\)$/m);
    assert.ok(!out.includes(VALUE));
  }
  assert.doesNotMatch(cli(dir, '--tree').out, /new\.js/);
});

test('--tree reads a new, uncommitted file and the values in app/.dev.vars', t => {
  const { dir, commit } = repo(t);
  commit({ '.gitignore': '.env\napp/.dev.vars\n', 'app.js': 'ok\n' });
  writeFileSync(join(dir, '.env'), `CLOUDFLARE_API_TOKEN=${VALUE}\n`);
  writeFileSync(join(dir, 'draft.js'), `const k = "${VALUE}";\n`);
  let { code, out } = cli(dir, '--tree');
  assert.equal(code, 1);
  assert.match(out, /^result=refused .*draft\.js \(a value from \.env\)$/m);
  assert.ok(!out.includes(VALUE));
  rmSync(join(dir, 'draft.js'));
  const devValue = 'dev-vars-secret-5f1c9a2e7b3d';
  mkdirSync(join(dir, 'app'), { recursive: true });
  writeFileSync(join(dir, 'app/.dev.vars'), `SOME_SECRET=${devValue}\n`);
  writeFileSync(join(dir, 'later.js'), `const s = "${devValue}";\n`);
  ({ code, out } = cli(dir, '--tree'));
  assert.equal(code, 1);
  assert.match(out, /later\.js/);
  assert.ok(!out.includes(devValue));
});

test('--notes lists a phone number without failing, naming the line and never the number', t => {
  const { dir, commit } = repo(t);
  const sha = commit({ 'wiki/people.md': '# People\n\nCall 415-555-0134 after six.\n', 'src/a.js': 'call("415-555-0134")\n' });
  assert.deepEqual(listNotes(dir), [`${sha}:wiki/people.md:3 a phone number`]);
  const { code, out } = cli(dir, '--notes');
  assert.equal(code, 0);
  assert.ok(!out.includes('555'));
  assert.match(out, /^result=listed 1$/m);
});

test('--notes names emails, places and health values but not example addresses', t => {
  const { dir, commit } = repo(t);
  const sha = commit({ 'openspec/plan.md': 'friend@gmail.com\nyou@example.com\n43.6532, -79.3832\n72 bpm\n12 King Street\n' });
  assert.deepEqual(listNotes(dir), [
    `${sha}:openspec/plan.md:1 an email address`,
    `${sha}:openspec/plan.md:3 a location value`,
    `${sha}:openspec/plan.md:4 a health value`,
    `${sha}:openspec/plan.md:5 a street address`,
  ]);
});

test('key files and private notes are refused by path', () => {
  const paths = ['.env', 'android/.env.local', 'app/.dev.vars', 'android/key.properties', 'android/upload.jks', 'notes/plan.md',
    'todo.private.md', 'ios/dist.cer', 'ios/dist.p12', 'ios/Relay.mobileprovision'];
  assert.deepEqual(blocked(paths.map(path => ({ path, text: '' })), []).map(stop => stop.path), paths);
});

test('words that hold "sk-" are not keys', () => {
  assert.deepEqual(blocked([{ path: 'a.md', text: 'the risk-assessment-for-the-whole-project' }], []), []);
});
