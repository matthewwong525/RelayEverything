// Run with: node --test scripts/publish-relay-site.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';
import { deployedUrl, privateValues, publish, readFiles, refusal, siteBlocked } from './publish-relay-site.mjs';

const file = (path, text) => ({ path, text });
const AUD = '8c34a3dc4b254dd4d3f4e10d7c5c8648cb2c4abd82a3704054adc3c385ce0dc2';
const APP_ID = 'c148207d-66b5-4373-a690-8942de361acb';

test('a clean page passes', () => {
  const page = file('start/index.html', '<a href="https://relay.example.workers.dev/">Relay</a> <a href="https://relay-staging.example.workers.dev/">x</a>');
  assert.deepEqual(siteBlocked([page], [AUD]), []);
  assert.equal(refusal([page], ['a-private-value'], [AUD]), null);
});

test('each private kind is refused, naming the file and never the value', () => {
  const values = {
    'a.html': 'write to someone@example.com',
    'b.html': 'sign in at team.cloudflareaccess.com',
    'c.html': 'the private site at relay-ring.example.workers.dev',
    'd.js': `aud:"${AUD.toUpperCase()}"`,
    'e.json': `{"app":"${APP_ID}"}`,
  };
  const stops = siteBlocked(Object.entries(values).map(([path, text]) => file(path, text)), [AUD, APP_ID]);
  assert.deepEqual(stops, [
    { path: 'a.html', why: 'an email address' },
    { path: 'b.html', why: 'a Cloudflare Access address' },
    { path: 'c.html', why: 'another Worker\'s address' },
    { path: 'd.js', why: 'a value from app/wrangler.jsonc' },
    { path: 'e.json', why: 'a value from app/wrangler.jsonc' },
  ]);
  const line = refusal([file('a.html', values['a.html']), file('k.js', `t="ghp_${'a'.repeat(36)}"`), file('.env', 'x')], [], []);
  assert.equal(line, 'result=refused k.js (text shaped like a key), .env (a key file or private note), a.html (an email address)');
  for (const value of [...Object.values(values), 'ghp_']) assert.ok(!line.includes(value));
});

test('the private values come from the private site\'s config', () => {
  const config = `{ "vars": { "OWNER": "owner@example.com", "CF_ACCESS_AUD": "${AUD}", "CF_ACCESS_APP_ID": "${APP_ID}", "NAME": "relay-ring" },
    "d1": [{ "database_id": "${APP_ID}" }] }`;
  assert.deepEqual(privateValues(config), ['owner@example.com', AUD, APP_ID]);
  assert.deepEqual(privateValues('{}'), []);
});

test('library code may credit its authors by email, but never holds a private one', () => {
  const credit = file('_astro/ui.js', 'var t=`Jan Claasen <jan@cloudcannon.com>`');
  assert.deepEqual(siteBlocked([credit], ['owner@example.com']), []);
  assert.deepEqual(siteBlocked([file('_astro/ui.js', 'var o="owner@example.com"')], ['owner@example.com']),
    [{ path: '_astro/ui.js', why: 'a value from app/wrangler.jsonc' }]);
});

test('a built folder is read as text: pictures by name, a compressed search index unpacked', () => {
  const dir = mkdtempSync(join(tmpdir(), 'relay-site-test-'));
  try {
    mkdirSync(join(dir, 'pagefind'));
    writeFileSync(join(dir, 'index.html'), '<h1>Relay</h1>');
    writeFileSync(join(dir, 'ring.png'), 'someone@example.com');
    writeFileSync(join(dir, 'pagefind', 'one.pf_fragment'), gzipSync('mail someone@example.com'));
    const files = readFiles(dir).sort((a, b) => a.path.localeCompare(b.path));
    assert.deepEqual(files, [file('index.html', '<h1>Relay</h1>'), file('pagefind/one.pf_fragment', 'mail someone@example.com'), file('ring.png', '')]);
    assert.deepEqual(siteBlocked(files, []).map(stop => stop.path), ['pagefind/one.pf_fragment']);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('the deployed address is read from wrangler\'s output', () => {
  assert.equal(deployedUrl('Deployed relay triggers\n  https://relay.someone.workers.dev\n'), 'https://relay.someone.workers.dev');
  assert.equal(deployedUrl('  https://relay-staging.someone.workers.dev'), 'https://relay-staging.someone.workers.dev');
  assert.equal(deployedUrl('Deployed relay triggers\n  relayeverything.com (custom domain)\n  www.relayeverything.com (custom domain)\n'),
    'https://relayeverything.com');
  assert.equal(deployedUrl('no address'), null);
});

/** A temporary repo with these files in one commit, removed after `body` runs. */
function withRepo(files, body) {
  const repo = mkdtempSync(join(tmpdir(), 'relay-site-repo-'));
  const git = (...args) => execFileSync('git', ['-C', repo, ...args], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
  try {
    git('init', '-q', '-b', 'main');
    for (const [path, text] of Object.entries(files)) {
      mkdirSync(join(repo, path, '..'), { recursive: true });
      writeFileSync(join(repo, path), text);
    }
    git('add', '-A');
    git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-q', '-m', 'start');
    body(repo, `commit=${git('rev-parse', '--short=7', 'HEAD')}`);
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
}

test('a commit with no site/ folder publishes nothing', () => {
  withRepo({ 'README.md': 'no site\n' }, (root, commit) => {
    assert.equal(publish({ root, ref: 'HEAD' }), `result=empty ${commit}`);
  });
});

test('a private value in site/ stops the publish before anything is installed or deployed', () => {
  withRepo({ 'app/wrangler.jsonc': '{}', 'site/x.md': 'the private site at relay-ring.example.workers.dev' }, root => {
    // With no package.json in site/, reaching the install step would return result=failed install instead.
    assert.equal(publish({ root, ref: 'HEAD', dryRun: true }), 'result=refused x.md (another Worker\'s address)');
  });
});
