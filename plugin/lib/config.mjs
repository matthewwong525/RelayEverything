// The computer's own Relay Everything folder, shared by Claude Code and Codex: the key file `computer.json` and the
// hooks' state in `state/`. It sits outside the plugin, so an update or a second app keeps the one key.
// `RELAY_EVERYTHING_HOME` points elsewhere, for tests and a trial.
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { state } from './state.mjs';

export const DEFAULT_SERVER = 'https://app.relayeverything.com';
export const KEY = /^rek_[A-Za-z0-9_-]{43}$/;
const NAME_CHARACTERS = 60;

/** The folder: `RELAY_EVERYTHING_HOME`, else `relay-everything` in the person's config folder. */
export function home(env = process.env) {
  if (env.RELAY_EVERYTHING_HOME) return env.RELAY_EVERYTHING_HOME;
  return join(env.XDG_CONFIG_HOME || join(env.HOME || homedir(), '.config'), 'relay-everything');
}

export const keyFile = env => join(home(env), 'computer.json');
export const stateDir = env => join(home(env), 'state');
/** This computer's copy of the person's knowledge web. */
export const copyOf = env => join(home(env), 'knowledge');

/** Makes the folder, readable only by this login. */
export function ensureHome(env) {
  const dir = home(env);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  chmodSync(dir, 0o700);
  return dir;
}

/**
 * A server's origin from what the person typed: https, or http only on this computer for a local server. Null for
 * anything else, such as a path, a user name or a query.
 */
export function serverOrigin(text) {
  let url;
  try {
    url = new URL(String(text ?? '').trim());
  } catch {
    return null;
  }
  const local = url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if ((url.protocol !== 'https:' && !local) || url.username || url.password || url.search || url.hash) return null;
  if (url.pathname !== '/' && url.pathname !== '') return null;
  return url.origin;
}

/** The web API's address from the key's answer: https, or http on this computer, with a path such as `/v1`. */
export function apiAddress(text) {
  let url;
  try {
    url = new URL(String(text ?? ''));
  } catch {
    return null;
  }
  const local = url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if ((url.protocol !== 'https:' && !local) || url.username || url.password || url.search || url.hash) return null;
  return `${url.origin}${url.pathname.replace(/\/+$/, '')}`;
}

/** The computer's key file as `{ server, key, api, name, memory }`, or null when it is missing or not one this plugin
 *  wrote. `memory` is the person's choice at /relay-connect; a file from before it reads as off. */
export function parseComputer(value) {
  if (value?.relay !== 1 || !KEY.test(value.key ?? '')) return null;
  const server = serverOrigin(value.server);
  const api = apiAddress(value.api);
  if (!server || !api) return null;
  return { server, key: value.key, api, name: String(value.name ?? '').slice(0, NAME_CHARACTERS), memory: value.memory === true };
}

export function readComputer(env = process.env) {
  try {
    return parseComputer(JSON.parse(readFileSync(keyFile(env), 'utf8')));
  } catch {
    return null;
  }
}

/** Writes the key file, mode 0600, through a new file so a stop halfway leaves the old one whole. */
export function writeComputer(env, value) {
  const computer = parseComputer({ relay: 1, ...value });
  if (!computer) throw new Error('The server sent a key this plugin can not use.');
  ensureHome(env);
  const next = `${keyFile(env)}.${process.pid}.tmp`;
  writeFileSync(next, `${JSON.stringify({ relay: 1, ...computer }, null, 1)}\n`, { mode: 0o600 });
  chmodSync(next, 0o600);
  renameSync(next, keyFile(env));
  return computer;
}

export function forgetComputer(env) {
  const had = existsSync(keyFile(env));
  rmSync(keyFile(env), { force: true });
  return had;
}

/**
 * The hooks' state in the shared folder. The first time it sees an old plugin data folder (version 0.2 kept its state
 * in Claude Code's `CLAUDE_PLUGIN_DATA`), it copies that folder's projects with saving off, once.
 */
export function openState(env = process.env, now = Date.now) {
  ensureHome(env);
  const store = state(stateDir(env), now);
  chmodSync(stateDir(env), 0o700);
  const old = env.CLAUDE_PLUGIN_DATA;
  if (old && old !== stateDir(env)) {
    try {
      copyOldOff(store, stateDir(env), old);
    } catch {
      // An old folder that can't be read leaves saving on, as it was before 0.2.
    }
  }
  return store;
}

/** The hooks' state only to read, for a folder this command can not write, as in a sandbox. */
export const readState = (env = process.env) => state(stateDir(env), Date.now, { make: false });

function copyOldOff(store, dir, old) {
  const copied = join(dir, 'copied.json');
  let done = [];
  try {
    done = JSON.parse(readFileSync(copied, 'utf8'));
  } catch {
    // Nothing copied yet.
  }
  if (done.includes(old) || !existsSync(join(old, 'off.json'))) return;
  const off = JSON.parse(readFileSync(join(old, 'off.json'), 'utf8'));
  for (const root of Array.isArray(off) ? off : []) if (typeof root === 'string' && !store.isOff(root)) store.setOff(root, true);
  writeFileSync(copied, JSON.stringify([...done, old]), { mode: 0o600 });
}
