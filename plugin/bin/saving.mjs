#!/usr/bin/env node
// `/relay:saving [on|off]`: turns saving to Relay on or off for this project, or says which it is and when it last sent.
// usage: node saving.mjs --data <plugin data folder> [on|off]
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dataDir, state } from '../lib/state.mjs';
import { projectName, projectRoot } from '../lib/transcript.mjs';

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

/** When a chat in the project at `root` last went to Relay, as a line to print. */
function lastSent(store, root, now) {
  const at = Math.max(0, ...Object.values(store.sessions()).filter(item => item.root === root).map(item => item.sentAt ?? 0));
  return at ? `This project last sent a chat to Relay ${ago(at, now)}.` : 'No chat from this project has gone to Relay yet.';
}

/** The lines to print for `choice` in the project at `cwd`. */
export function saving(store, cwd, choice, env = {}, now = Date.now()) {
  const root = projectRoot(cwd);
  const name = projectName(root);
  if (choice === 'on' || choice === 'off') store.setOff(root, choice === 'off');
  else if (choice) return [`Type /relay:saving on, /relay:saving off, or /relay:saving to see which it is.`];
  const lines = store.isOff(root)
    ? [`Saving to Relay is off for ${name}.`, 'Chats in this project stay on this computer. Type /relay:saving on to save them again.']
    : [`Saving to Relay is on for ${name}.`, 'Each chat here goes to your Relay server as you talk. Type /relay:saving off to stop.'];
  lines.push(lastSent(store, root, now));
  return env.RELAY_SAVE === '0' ? [...lines, 'RELAY_SAVE is 0 where Claude Code started, so no chat is saved now.'] : lines;
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const args = process.argv.slice(2);
  const choice = args.filter((arg, at) => arg !== '--data' && args[at - 1] !== '--data')[0];
  console.log(saving(state(dataDir(process.env, args)), process.cwd(), choice, process.env).join('\n'));
}
