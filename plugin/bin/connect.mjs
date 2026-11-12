#!/usr/bin/env node
// `/relay:connect`: connects this computer to Relay Everything by a sign-in link, with no key to copy.
//   start [server]  asks the server for a link and a code, and starts a waiter that runs on its own for 10 minutes
//   wait            waits up to 90 seconds for the person to click Connect, then checks for a second connector
//   status          says whether this computer is connected
//   forget          deletes this computer's key file
//   memory [on|off] turns Relay Everything's memory on or off on this computer, or says which it is
import { spawn, spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { hostname } from 'node:os';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { withSandbox } from '../lib/sandbox.mjs';
import { DEFAULT_SERVER, forgetComputer, home, openState, readComputer, serverOrigin, stateDir, writeComputer } from '../lib/config.mjs';
import { whyOff } from '../lib/memory.mjs';

const self = fileURLToPath(import.meta.url);
export const EVERY = 3_000;
export const LINK_LIFE = 10 * 60_000;
export const WAIT = 90_000;
const LIST_WAIT = 20_000;
const NAME_CHARACTERS = 60;
// The public AI connector's host. Any other server's connector host comes from its key's `api` address.
const CONNECTOR_HOSTS = /^mcp\.relayeverything\.com$/i;

const base64url = bytes => Buffer.from(bytes).toString('base64url');
/** A new secret for the trade, and its SHA-256, which is all the link holds. */
export function makeVerifier() {
  const verifier = base64url(randomBytes(32));
  return { verifier, challenge: base64url(createHash('sha256').update(verifier).digest()) };
}

const pendingFile = env => join(stateDir(env), 'connect.json');
function readPending(env) {
  try {
    return JSON.parse(readFileSync(pendingFile(env), 'utf8'));
  } catch {
    return null;
  }
}
function writePending(env, value) {
  const next = `${pendingFile(env)}.${process.pid}.tmp`;
  writeFileSync(next, JSON.stringify(value), { mode: 0o600 });
  renameSync(next, pendingFile(env));
}

const quoted = name => `"${name}"`;
const connectedLine = computer => `Relay Everything is connected as ${quoted(computer.name || 'this computer')}, at ${computer.server}.`;

/** Asks the server for a link and a code, keeps the secret in the state folder, and starts the waiter. */
export async function start(server, { env = process.env, fetcher = fetch, waiter = startWaiter, name = hostname(), now = Date.now } = {}) {
  const origin = serverOrigin(server || DEFAULT_SERVER);
  if (!origin) return { code: 2, lines: ['Give the server as its address alone, such as https://<your-relay-server>.'] };
  const { verifier, challenge } = makeVerifier();
  let response;
  try {
    response = await fetcher(`${origin}/apps/relay/sign-in/computer/start`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ challenge, name: String(name).slice(0, NAME_CHARACTERS) || 'Computer' }),
      signal: AbortSignal.timeout(30_000),
    });
  } catch (error) {
    return { code: 1, lines: [withSandbox(`Relay Everything at ${origin} could not be reached. Check the address and the network, then try again.`, error)] };
  }
  if (response.status === 429) return { code: 1, lines: ['Relay Everything had too many tries from this network. Wait a few minutes, then type /relay:connect again.'] };
  const json = await response.json().catch(() => null);
  if (response.status !== 200 || typeof json?.link !== 'string' || typeof json?.words !== 'string') {
    return { code: 1, lines: [`${origin} did not answer as a Relay Everything server does (status ${response.status}). Check the address.`] };
  }
  const startedAt = now();
  try {
    openState(env);
    writePending(env, { server: origin, verifier, link: json.link, words: json.words, startedAt, result: 'waiting' });
  } catch (error) {
    return { code: 1, lines: [withSandbox(`The folder ${home(env)} could not be written, so this computer can not keep its key.`, error)] };
  }
  waiter(env, startedAt);
  return {
    code: 0,
    lines: [
      `Open this link on any phone or computer: ${json.link}`,
      `Check that the page shows this code: ${json.words}`,
      'Then click Connect. The link works for 10 minutes, once.',
    ],
  };
}

function startWaiter(env, startedAt) {
  spawn(process.execPath, [self, 'poll', String(startedAt)], { detached: true, stdio: 'ignore', env }).unref();
}

/**
 * The waiter: trades the secret for the key every few seconds, until the person clicks Connect, the server says the
 * link is gone, or 10 minutes pass. It stops when a newer start replaced its link.
 */
export async function poll(startedAt, { env = process.env, fetcher = fetch, every = EVERY, life = LINK_LIFE, now = Date.now } = {}) {
  const ours = () => {
    const pending = readPending(env);
    return pending?.startedAt === startedAt && pending.result === 'waiting' ? pending : null;
  };
  for (let first = true; now() < startedAt + life; first = false) {
    if (!first) await sleep(every);
    const pending = ours();
    if (!pending) return 'replaced';
    let response;
    try {
      response = await fetcher(`${pending.server}/apps/relay/sign-in/computer/key`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ verifier: pending.verifier }),
        signal: AbortSignal.timeout(30_000),
      });
    } catch {
      continue;
    }
    if (response.status === 202) continue;
    const json = await response.json().catch(() => null);
    if (response.status === 200 && json) {
      try {
        // A computer connected again keeps the person's memory choice until the skill asks again.
        const computer = writeComputer(env, { server: json.server || pending.server, key: json.key, api: json.api, name: json.name,
          memory: readComputer(env)?.memory === true });
        writePending(env, { startedAt, result: 'connected', name: computer.name });
        return 'connected';
      } catch {
        writePending(env, { startedAt, result: 'failed' });
        return 'failed';
      }
    }
    if (response.status === 400) {
      writePending(env, { startedAt, result: 'expired' });
      return 'expired';
    }
  }
  if (ours()) writePending(env, { startedAt, result: 'expired' });
  return 'expired';
}

const ENDS = {
  expired: 'Nobody clicked Connect in time, so no key was made. Type /relay:connect to start again.',
  ended: 'The sign-in link ended before this computer got its key. Type /relay:connect to start again.',
  failed: 'The server sent a key this plugin can not use. Type /relay:connect to start again.',
};

/** Waits for the waiter's answer, then names any second Relay Everything connector. */
export async function wait({ env = process.env, limit = WAIT, every = 1_000, run = runCommand, now = Date.now, remove = rmSync } = {}) {
  const until = now() + limit;
  // A folder that can't be written, as in a sandbox, keeps the answer file: the answer still shows, and stays true.
  const clear = () => {
    try {
      remove(pendingFile(env), { force: true });
    } catch {
      // The next wait reads the same answer again.
    }
  };
  for (;;) {
    const pending = readPending(env);
    if (!pending) {
      const computer = readComputer(env);
      return computer ? { code: 0, lines: [connectedLine(computer)] }
        : { code: 1, lines: ['No sign-in link is waiting. Type /relay:connect to start one.'] };
    }
    if (pending.result === 'connected') {
      const computer = readComputer(env);
      clear();
      if (!computer) return { code: 1, lines: ['The key file is gone. Type /relay:connect to start again.'] };
      return { code: 0, lines: [connectedLine(computer), ...codexHooksLine(env), ...doubles(computer, run)] };
    }
    // Only the waiter writes `expired`: a waiter that died leaves the link `waiting` after it ended.
    const result = pending.result === 'waiting' && now() >= pending.startedAt + LINK_LIFE ? 'ended' : pending.result;
    if (ENDS[result]) {
      clear();
      return { code: 1, lines: [ENDS[result]] };
    }
    if (now() >= until) {
      return { code: 3, lines: ['Not connected yet. When you have clicked Connect, ask me to check again.'] };
    }
    await sleep(every);
  }
}

/** In Codex, chats save only after the person trusts the plugin's hooks once. */
const codexHooksLine = env => (env.CODEX_THREAD_ID
  ? ['In Codex, chats save only after you trust the plugin\'s hooks: start Codex again and pick "Trust all and continue", or open /hooks.']
  : []);

export function status(env = process.env) {
  const computer = readComputer(env);
  const pending = readPending(env);
  const lines = [computer ? connectedLine(computer) : 'This computer is not connected to Relay Everything. Type /relay:connect to connect it.'];
  if (pending?.result === 'waiting' && pending.startedAt + LINK_LIFE > Date.now()) {
    lines.push(`A sign-in link is waiting for Connect, with the code ${pending.words}.`);
  }
  return { code: computer ? 0 : 1, lines };
}

export function forget(env = process.env) {
  rmSync(pendingFile(env), { force: true });
  const had = forgetComputer(env);
  return { code: 0, lines: [had
    ? 'This computer no longer has its Relay Everything key. To stop the key for good, open Connect your AI on your Relay Everything page and click Disconnect.'
    : 'This computer had no Relay Everything key.'] };
}

export const MEMORY_ON = 'Memory is on. Relay Everything keeps short facts from each chat on this computer, such as what you '
  + 'decided, prefer and left open, in your own Relay Everything space, and each new chat starts with them. Type /relay:memory off to stop.';
export const MEMORY_OFF = 'Memory is off. Chats still save to Relay Everything, and your topics still show. Type /relay:memory on to start it.';

/** `/relay:memory on|off`, and the setup choice at /relay:connect: keeps the choice in the key file, or says it. */
export function remember(choice, { env = process.env, cwd = process.cwd() } = {}) {
  const computer = readComputer(env);
  if (!computer) return { code: 1, lines: ['This computer is not connected to Relay Everything. Type /relay:connect to connect it.'] };
  if (choice && choice !== 'on' && choice !== 'off') return { code: 2, lines: ['Type /relay:memory on, /relay:memory off, or /relay:memory to see which it is.'] };
  let now = computer;
  if (choice) {
    try {
      now = writeComputer(env, { ...computer, memory: choice === 'on' });
    } catch (error) {
      return { code: 1, lines: [withSandbox(`The folder ${home(env)} could not be written, so memory did not change.`, error)] };
    }
  }
  if (!now.memory) return { code: 0, lines: [MEMORY_OFF] };
  const why = whyOff(env, cwd, now);
  return { code: 0, lines: [MEMORY_ON, ...why ? [`It does not run in this folder now: ${why}.`] : []] };
}

function runCommand(command, args) {
  return spawnSync(command, args, { encoding: 'utf8', timeout: LIST_WAIT, stdio: ['ignore', 'pipe', 'pipe'] });
}

function hostOf(text) {
  try {
    return new URL(text).hostname.toLowerCase();
  } catch {
    return '';
  }
}

/** True for a connector entry that is Relay Everything's: on its connector's host, or named relay or Relay Everything. */
export function isRelayEntry(name, address, computer) {
  const host = hostOf(address);
  const own = hostOf(computer?.api ?? '');
  return /^relay$/i.test(name.trim()) || /relay\s*everything/i.test(name) || Boolean(host && (host === own || CONNECTOR_HOSTS.test(host)));
}

/** Claude Code's `claude mcp list` lines as `{ name, address }`. */
export function claudeEntries(text) {
  return String(text ?? '').split('\n').flatMap(line => {
    const found = /^(.+?): (.+?)(?: \([A-Za-z]+\))? - /.exec(line.trim());
    return found ? [{ name: found[1], address: found[2].trim() }] : [];
  });
}

/** Codex's `codex mcp list --json` as `{ name, address }`. */
export function codexEntries(text) {
  try {
    const list = JSON.parse(text);
    return Array.isArray(list) ? list.map(item => ({ name: String(item?.name ?? ''), address: String(item?.transport?.url ?? '') })) : [];
  } catch {
    return [];
  }
}

const said = done => (done && !done.error && done.status === 0 ? done.stdout : null);
const shellWord = word => (/^[\w.@:/-]+$/.test(word) ? word : `'${word.replaceAll("'", "'\\''")}'`);

/**
 * The lines that name each Relay Everything connector Claude Code or Codex on this computer also has, with the
 * command that removes it. It removes nothing: the skill asks the person first.
 */
export function doubles(computer, run = runCommand) {
  const lines = [];
  const claude = said(run('claude', ['mcp', 'list']));
  for (const { name, address } of claudeEntries(claude).filter(entry => isRelayEntry(entry.name, entry.address, computer))) {
    if (/^claude\.ai\s/i.test(name)) {
      lines.push(`Claude Code also has the Relay Everything AI connector from your Claude account (${quoted(name)}). The plugin does the same job. `
        + 'To turn it off here, type /mcp in Claude Code and turn it off. To remove it everywhere, remove it in the Claude app\'s connector settings.');
      continue;
    }
    const scope = /Scope:\s*(User|Local|Project)\b/i.exec(said(run('claude', ['mcp', 'get', name])) ?? '')?.[1]?.toLowerCase();
    lines.push(`Claude Code also has the Relay Everything AI connector (${quoted(name)}). The plugin does the same job, so you can remove it to save space: `
      + `claude mcp remove ${shellWord(name)}${scope ? ` -s ${scope}` : ''}`);
  }
  const codex = said(run('codex', ['mcp', 'list', '--json']));
  for (const { name } of codexEntries(codex).filter(entry => isRelayEntry(entry.name, entry.address, computer))) {
    lines.push(`Codex also has the Relay Everything AI connector (${quoted(name)}). The plugin does the same job, so you can remove it to save space: `
      + `codex mcp remove ${shellWord(name)}`);
  }
  return lines;
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const [command, value] = process.argv.slice(2);
  if (command === 'poll') await poll(Number(value)).catch(() => {});
  else {
    let done;
    try {
      done = command === 'start' ? await start(value)
        : command === 'wait' ? await wait()
          : command === 'status' ? status()
            : command === 'forget' ? forget()
              : command === 'memory' ? remember(value)
                : { code: 2, lines: ['Type /relay:connect, or give start [server], wait, status, forget or memory [on|off].'] };
    } catch (error) {
      done = { code: 1, lines: [withSandbox('Relay Everything could not finish this step on this computer. Try again in a minute.', error)] };
    }
    console.log(done.lines.join('\n'));
    process.exitCode = done.code;
  }
}
