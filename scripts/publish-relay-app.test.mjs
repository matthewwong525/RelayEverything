// Run with: node --test scripts/publish-relay-app.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { blocked, envSecrets } from './publish-relay-app.mjs';

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
