// Run with: node --test scripts/publish-relay-server.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { publish } from './publish-relay-server.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SHA = execFileSync('git', ['-C', ROOT, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim().slice(0, 7);
const CONFIGS = ['wrangler.spaces.jsonc', 'wrangler.relay-mcp.jsonc', 'wrangler.relay.jsonc'];
const ALL = 'relay-everything-spaces-staging,relay-everything-mcp-staging,relay-everything-server-staging,relay-everything-server';

// The real configs stand in for the export, so a renamed Worker fails here too.
const exportTree = (_root, _sha, work) => {
  mkdirSync(join(work, 'app'));
  for (const name of CONFIGS) copyFileSync(join(ROOT, 'app', name), join(work, 'app', name));
};

/** A runner that records each call; a build leaves the redirect the vite plugin would, naming `built(env)`. */
function fakeRunner({ fail, built = env => (env === 'staging' ? 'relay-everything-server-staging' : 'relay-everything-server') } = {}) {
  const calls = [];
  const run = (cmd, args, { cwd, env }) => {
    calls.push({ line: [cmd, ...args].join(' '), env: env.CLOUDFLARE_ENV, config: env.RELAY_CONFIG });
    if (fail?.(cmd, args, env)) throw new Error('exit 1');
    if (args.includes('build:relay-only')) {
      mkdirSync(join(cwd, '.wrangler/deploy'), { recursive: true });
      mkdirSync(join(cwd, 'dist/server'), { recursive: true });
      writeFileSync(join(cwd, 'dist/server/wrangler.json'), JSON.stringify({ name: built(env.CLOUDFLARE_ENV) }));
      writeFileSync(join(cwd, '.wrangler/deploy/config.json'), JSON.stringify({ configPath: '../../dist/server/wrangler.json' }));
    }
  };
  return { run, calls };
}

const go = (runner, opts = {}) => publish({ root: ROOT, ref: 'HEAD', run: runner.run, exportTree, env: { CLOUDFLARE_ENV: 'stray' }, ...opts });

test('staging spaces, connector and server deploy in order, then the live server', () => {
  const runner = fakeRunner();
  assert.equal(go(runner), `result=deployed ref=${SHA} workers=${ALL}`);
  assert.deepEqual(runner.calls.map(call => call.line), [
    'npm ci --no-audit --no-fund',
    'node ../scripts/build-relay-web.mjs',
    'npx wrangler deploy -c wrangler.spaces.jsonc --env staging',
    'npx wrangler deploy -c wrangler.relay-mcp.jsonc --env staging',
    'npm run build:relay-only',
    'npx wrangler deploy',
    'npm run build:relay-only',
    'npx wrangler deploy',
  ]);
  const builds = runner.calls.filter(call => call.line.includes('build:relay-only'));
  assert.deepEqual(builds.map(call => [call.env, call.config]), [['staging', 'wrangler.relay.jsonc'], [undefined, 'wrangler.relay.jsonc']]);
  assert.ok(runner.calls.filter(call => call.line === 'npx wrangler deploy').every(call => call.env === undefined));
});

test('a staging server failure stops before live', () => {
  const runner = fakeRunner({ fail: (_cmd, args, env) => args.includes('build:relay-only') && env.CLOUDFLARE_ENV === 'staging' });
  assert.equal(go(runner), `result=failed step=staging-server ref=${SHA}`);
  assert.equal(runner.calls.filter(call => call.line.includes('build:relay-only')).length, 1);
  assert.ok(!runner.calls.some(call => call.line === 'npx wrangler deploy'));
});

test('a build redirect naming the wrong Worker is refused before its deploy', () => {
  const runner = fakeRunner({ built: () => 'relay-everything-server' });
  assert.equal(go(runner), `result=failed step=staging-server ref=${SHA}`);
  assert.ok(!runner.calls.some(call => call.line === 'npx wrangler deploy'));
  const live = fakeRunner({ built: () => 'relay-everything-server-staging' });
  assert.equal(go(live), `result=failed step=live-server ref=${SHA}`);
  assert.equal(live.calls.filter(call => call.line === 'npx wrangler deploy').length, 1);
});

test('--dry-run builds each part and deploys nothing', () => {
  const runner = fakeRunner();
  assert.equal(go(runner, { dryRun: true }), `result=dry-run ref=${SHA} workers=${ALL}`);
  const deploys = runner.calls.filter(call => call.line.includes('wrangler deploy'));
  assert.equal(deploys.length, 4);
  assert.ok(deploys.every(call => call.line.includes('--dry-run')));
});

test('--staging-only leaves live alone, and an install failure names its step', () => {
  const runner = fakeRunner();
  assert.equal(go(runner, { stagingOnly: true }),
    `result=deployed ref=${SHA} workers=relay-everything-spaces-staging,relay-everything-mcp-staging,relay-everything-server-staging`);
  assert.equal(runner.calls.filter(call => call.line.includes('build:relay-only')).length, 1);
  assert.equal(go(fakeRunner({ fail: cmd => cmd === 'npm' })), `result=failed step=install ref=${SHA}`);
});

test('a failed page build stops before any deploy', () => {
  const runner = fakeRunner({ fail: cmd => cmd === 'node' });
  assert.equal(go(runner), `result=failed step=web ref=${SHA}`);
  assert.ok(!runner.calls.some(call => call.line.includes('wrangler')));
});

test('an unknown --ref still prints one result line', () => {
  assert.equal(go(fakeRunner(), { ref: 'no-such-ref' }), 'result=failed step=ref ref=no-such-ref');
});
