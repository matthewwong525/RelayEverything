#!/usr/bin/env node
// `/relay-saving [on|off]`: turns saving to Relay Everything on or off for this project, in Claude Code and Codex alike,
// or says which it is and when it last sent.
// usage: node saving.mjs [on|off]
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { home, openState, readComputer, readState } from '../lib/config.mjs';
import { withSandbox } from '../lib/sandbox.mjs';
import { gitTop, projectName, projectRoot, savingOff } from '../lib/transcript.mjs';

const MINUTE = 60_000;

/** How long ago `at` was, in plain words. */
export function ago(at, now) {
  const minutes = Math.floor(Math.max(0, now - at) / MINUTE);
  const count = (value, unit) => `${value} ${unit}${value === 1 ? '' : 's'} ago`;
  if (minutes < 1) return 'less than a minute ago';
  if (minutes < 60) return count(minutes, 'minute');
  if (minutes < 48 * 60) return count(Math.floor(minutes / 60), 'hour');
  return count(Math.floor(minutes / (24 * 60)), 'day');
}

/** When a chat in the project at `root` last went to Relay Everything, as a line to print. */
function lastSent(store, root, now) {
  const at = Math.max(0, ...Object.values(store.sessions()).filter(item => item.root === root).map(item => item.sentAt ?? 0));
  return at ? `This project last sent a chat to Relay Everything ${ago(at, now)}.` : 'No chat from this project has gone to Relay Everything yet.';
}

/** The lines to print for `choice` in the project at `cwd`. */
export function saving(store, cwd, choice, env = {}, now = Date.now()) {
  const root = projectRoot(cwd);
  const top = gitTop(cwd);
  const name = projectName(root);
  if (choice === 'on' || choice === 'off') {
    store.setOff(root, choice === 'off');
    // An entry for this worktree alone, made before worktrees counted as their main repository, goes with an on.
    if (choice === 'on' && top !== root) store.setOff(top, false);
  } else if (choice) return [`Type /relay-saving on, /relay-saving off, or /relay-saving to see which it is.`];
  const lines = savingOff(store, root, top)
    ? [`Saving to Relay Everything is off for ${name}.`, 'Chats in this project stay on this computer. Type /relay-saving on to save them again.']
    : [`Saving to Relay Everything is on for ${name}.`, 'Each chat here goes to your Relay Everything server as you talk, from Claude Code or Codex. Type /relay-saving off to stop.'];
  lines.push(lastSent(store, root, now));
  if (!readComputer(env)) lines.push('This computer is not connected, so no chat is saved now. Type /relay-connect to connect it.');
  return env.RELAY_SAVE === '0' ? [...lines, 'RELAY_SAVE is 0 where this app started, so no chat is saved now.'] : lines;
}

/** The lines to print when run as the skill runs it. Only `on` or `off` must write; a look reads what it can. */
export function run(choice, { env = process.env, cwd = process.cwd() } = {}) {
  let store;
  try {
    store = openState(env);
  } catch (error) {
    if (choice === 'on' || choice === 'off') return { code: 1, lines: [withSandbox(`The folder ${home(env)} could not be written, so saving did not change.`, error)] };
    store = readState(env);
  }
  return { code: 0, lines: saving(store, cwd, choice, env) };
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const { code, lines } = run(process.argv[2]);
  console.log(lines.join('\n'));
  process.exitCode = code;
}
