import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { apiAddress, forgetComputer, home, keyFile, openState, parseComputer, readComputer, serverOrigin, stateDir, writeComputer } from '../lib/config.mjs';
import { computer, SECRET } from './fake.mjs';

const mode = path => statSync(path).mode & 0o777;
const temp = () => mkdtempSync(join(tmpdir(), 'relay-config-'));

test('the folder is RELAY_EVERYTHING_HOME, else relay-everything in XDG_CONFIG_HOME, else in ~/.config', () => {
  assert.equal(home({ RELAY_EVERYTHING_HOME: '/x/here', XDG_CONFIG_HOME: '/y' }), '/x/here');
  assert.equal(home({ XDG_CONFIG_HOME: '/y' }), '/y/relay-everything');
  assert.equal(home({ HOME: '/home/sam' }), '/home/sam/.config/relay-everything');
  assert.equal(keyFile({ XDG_CONFIG_HOME: '/y' }), '/y/relay-everything/computer.json');
  assert.equal(stateDir({ XDG_CONFIG_HOME: '/y' }), '/y/relay-everything/state');
});

test('writes the key file readable only by this login, in a folder only it can open, and reads it back', () => {
  const env = { XDG_CONFIG_HOME: temp() };
  assert.equal(readComputer(env), null);
  writeComputer(env, computer());
  assert.deepEqual(readComputer(env), computer());
  assert.equal(mode(keyFile(env)), 0o600);
  assert.equal(mode(home(env)), 0o700);
  assert.deepEqual(JSON.parse(readFileSync(keyFile(env), 'utf8')), { relay: 1, ...computer() });
  openState(env);
  assert.equal(mode(stateDir(env)), 0o700);
  assert.equal(forgetComputer(env), true);
  assert.equal(readComputer(env), null);
  assert.equal(forgetComputer(env), false);
});

test('takes only an https server, or http on this computer, with no path, and refuses a key file it did not write', () => {
  assert.equal(serverOrigin('https://relay.example.com/'), 'https://relay.example.com');
  assert.equal(serverOrigin(' https://relay.example.com '), 'https://relay.example.com');
  assert.equal(serverOrigin('http://localhost:8787'), 'http://localhost:8787');
  assert.equal(serverOrigin('http://127.0.0.1:9000/'), 'http://127.0.0.1:9000');
  for (const wrong of ['http://relay.example.com', 'https://relay.example.com/apps', `https://user${'@'}relay.example.com`,
    'https://relay.example.com/?a=1', 'relay.example.com', '', undefined]) {
    assert.equal(serverOrigin(wrong), null, String(wrong));
  }
  assert.equal(apiAddress('https://connector.example.com/v1/'), 'https://connector.example.com/v1');
  assert.equal(apiAddress('http://connector.example.com/v1'), null);
  for (const wrong of [{ ...computer(), relay: 2 }, { ...computer(), key: 'rek_short' }, { ...computer(), key: `${SECRET} ` },
    { ...computer(), server: 'http://relay.example.com' }, { ...computer(), api: 'not an address' }]) {
    assert.equal(parseComputer({ relay: 1, ...wrong }), null);
  }
  assert.equal(parseComputer({ relay: 1, ...computer(), name: 'x'.repeat(80) }).name.length, 60);
  assert.throws(() => writeComputer({ XDG_CONFIG_HOME: temp() }, { ...computer(), key: 'nope' }), /can not use/);
  const env = { RELAY_EVERYTHING_HOME: temp() };
  writeFileSync(keyFile(env), '{');
  assert.equal(readComputer(env), null);
});

test('copies the projects with saving off from the old plugin data folder, once', () => {
  const old = temp();
  writeFileSync(join(old, 'off.json'), JSON.stringify(['/home/sam/secret-project', 7]));
  const env = { RELAY_EVERYTHING_HOME: join(temp(), 'relay-everything'), CLAUDE_PLUGIN_DATA: old };
  const store = openState(env);
  assert.equal(store.isOff('/home/sam/secret-project'), true);
  // Turned on again here, it stays on: the old folder is not copied a second time.
  store.setOff('/home/sam/secret-project', false);
  assert.equal(openState(env).isOff('/home/sam/secret-project'), false);
  // A folder with no off.json, or one that can't be read, changes nothing.
  const empty = { RELAY_EVERYTHING_HOME: join(temp(), 'relay-everything'), CLAUDE_PLUGIN_DATA: temp() };
  assert.equal(openState(empty).isOff('/home/sam/secret-project'), false);
  const broken = temp();
  writeFileSync(join(broken, 'off.json'), '{');
  assert.equal(openState({ ...empty, CLAUDE_PLUGIN_DATA: broken }).isOff('/home/sam/secret-project'), false);
});
