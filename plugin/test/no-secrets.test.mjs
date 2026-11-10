import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { SHAPES } from '../lib/hide.mjs';

// The plugin is public and installs on any computer: it holds no key, no private server's address and no email.
// It may name only Relay Everything's public addresses: the website, the shared server and the public AI connector.
const PLUGIN = fileURLToPath(new URL('..', import.meta.url));
const PUBLIC = new Set(['relayeverything.com', 'app.relayeverything.com', 'mcp.relayeverything.com']);
const privateRelay = text => [...text.matchAll(/(https?):\/\/([A-Za-z0-9.-]+)/g)]
  .some(([, scheme, host]) => /relayeverything\.com/i.test(host) && !(scheme === 'https' && PUBLIC.has(host.toLowerCase().replace(/\.+$/, ''))));
const ADDRESS = [/workers\.dev/i, /cloudflareaccess\.com/i, /relay-(?:ring|everything)(?:-mcp)?(?:-staging)?\.[a-z]/i, { test: privateRelay }];
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}/;

const files = dir => readdirSync(dir, { withFileTypes: true })
  .flatMap(entry => entry.isDirectory() ? files(join(dir, entry.name)) : [join(dir, entry.name)]);

test('no file in plugin/ holds a key shape, a private address or an email', () => {
  const found = files(PLUGIN).flatMap(path => {
    const text = readFileSync(path, 'utf8');
    // This file holds refused addresses on purpose, to test the check.
    const own = path === fileURLToPath(import.meta.url);
    const why = SHAPES.find(([, shape]) => new RegExp(shape.source).test(text))?.[0]
      ?? (!own && ADDRESS.some(address => address.test(text)) ? 'a private address' : EMAIL.test(text) ? 'an email' : null);
    return why ? [`${relative(PLUGIN, path)}: ${why}`] : [];
  });
  assert.deepEqual(found, []);
  assert.ok(files(PLUGIN).length > 10);
});

test('the address check lets the public addresses through and stops any other', () => {
  const caught = text => ADDRESS.some(address => address.test(text));
  for (const text of ['https://relayeverything.com', 'see https://app.relayeverything.com.', '`https://mcp.relayeverything.com/mcp`']) {
    assert.equal(caught(text), false, text);
  }
  for (const text of ['https://admin.relayeverything.com', 'https://app.relayeverything.com.evil.example', 'http://app.relayeverything.com', 'x.workers.dev']) {
    assert.equal(caught(text), true, text);
  }
});
