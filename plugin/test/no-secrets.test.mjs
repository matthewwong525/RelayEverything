import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { SHAPES } from '../lib/hide.mjs';

// The plugin is public and installs on any computer: it holds no key, no Relay server's address and no email.
const PLUGIN = fileURLToPath(new URL('..', import.meta.url));
const ADDRESS = [/workers\.dev/i, /cloudflareaccess\.com/i, /relay-ring(?:-mcp)?(?:-staging)?\.[a-z]/i];
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}/;

const files = dir => readdirSync(dir, { withFileTypes: true })
  .flatMap(entry => entry.isDirectory() ? files(join(dir, entry.name)) : [join(dir, entry.name)]);

test('no file in plugin/ holds a key shape, a Relay address or an email', () => {
  const found = files(PLUGIN).flatMap(path => {
    const text = readFileSync(path, 'utf8');
    const why = SHAPES.find(([, shape]) => new RegExp(shape.source).test(text))?.[0]
      ?? (ADDRESS.some(address => address.test(text)) ? 'a Relay address' : EMAIL.test(text) ? 'an email' : null);
    return why ? [`${relative(PLUGIN, path)}: ${why}`] : [];
  });
  assert.deepEqual(found, []);
  assert.ok(files(PLUGIN).length > 10);
});
