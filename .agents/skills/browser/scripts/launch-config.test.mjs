// The proxy part of launch-config.py: the browser's language and time zone follow the address sites see.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fakeLibrary } from './lib/fake-camoufox.mjs';

const SCRIPT = fileURLToPath(new URL('./launch-config.py', import.meta.url));
const PINS = ['--library', '0.5.9', '--build', 'v158.0.1-beta.41'];

/** Runs launch-config.py on a fake library; resolves to its exit code and its one JSON line. */
function run(library, ...args) {
  const dir = mkdtempSync(join(tmpdir(), 'launch-config-test-'));
  try {
    const lib = fakeLibrary(dir, library);
    const done = spawnSync('python3', [SCRIPT, ...PINS, ...args], { encoding: 'utf8', env: { PATH: process.env.PATH, PYTHONPATH: lib, HOME: dir } });
    return { status: done.status, out: JSON.parse(done.stdout), stdout: done.stdout };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('the browser starts in English for the proxy address\'s country, with that address for its time zone', () => {
  const { status, out, stdout } = run({}, '--proxy', 'http://127.0.0.1:4000', '--display', ':7');
  assert.equal(status, 0);
  assert.equal(stdout.trim().split('\n').length, 1, 'the library\'s own lines stay off stdout');
  assert.equal(out.locale, 'en-CA');
  const { given } = out.options;
  assert.equal(given.locale, 'en-CA');
  assert.equal(given.geoip, '203.0.113.7');
  assert.deepEqual(given.proxy, { server: 'http://127.0.0.1:4000' });
});

test('a failed country lookup starts in US English with no geoip', () => {
  const { out } = run({ country: null });
  assert.equal(out.locale, 'en-US');
  assert.equal(out.options.given.geoip, null);
});
