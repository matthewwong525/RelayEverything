#!/usr/bin/env node
// The `ask` skill's one command: reads the person's Relay Everything through the web API, or adds a note, with this
// computer's key, and prints the JSON answer.
// usage: node relay.mjs <command> [value] [--field value ...]   (add-note reads the note from stdin)
import { randomUUID } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { readComputer } from '../lib/config.mjs';
import { withSandbox } from '../lib/sandbox.mjs';
import { api, reason } from '../lib/server.mjs';

export const CHAT_KEY = "This computer's key only saves chats. Type /relay:connect to connect it again.";
export const NOT_CONNECTED = 'This computer is not connected to Relay Everything. Type /relay:connect to connect it.';
const USAGE = 'Commands: me, notes, note <id>, day <YYYY-MM-DD>, health <type>, nights, workouts, places, calendar, chats, '
  + 'chat <id>, add-note. Give fields as --name value, such as --from 2026-11-03 --to 2026-11-04.';

// Each command: its route, and the field its one value fills. `id` and `day` go in the path.
const COMMANDS = {
  me: { path: () => '/me', zone: false },
  notes: { path: () => '/notes' },
  note: { path: value => `/notes/${encodeURIComponent(value)}`, needs: 'the note id' },
  day: { path: value => `/days/${encodeURIComponent(value)}`, needs: 'the day, as YYYY-MM-DD' },
  health: { path: () => '/health', field: 'type', needs: 'the kind, such as steps or sleep' },
  nights: { path: () => '/nights' },
  workouts: { path: () => '/workouts' },
  places: { path: () => '/places' },
  calendar: { path: () => '/calendar' },
  chats: { path: () => '/chats' },
  chat: { path: value => `/chats/${encodeURIComponent(value)}`, needs: 'the chat id' },
  'add-note': { path: () => '/notes', add: true },
};
// Other names the skill may use for a field.
const ALIASES = { per: 'bucket', at: 'createdAt', zone: 'timezone', query: 'q' };

/** The command, its one value, and its `--name value` fields; a `--name` with no value is `true`. */
export function parseArgs(args) {
  const [command, ...rest] = args;
  const fields = {};
  const values = [];
  for (let at = 0; at < rest.length; at++) {
    const flag = /^--([A-Za-z][\w-]*)(?:=(.*))?$/.exec(rest[at]);
    if (!flag) values.push(rest[at]);
    else {
      const name = ALIASES[flag[1]] ?? flag[1];
      if (flag[2] !== undefined) fields[name] = flag[2];
      else if (rest[at + 1] !== undefined && !rest[at + 1].startsWith('--')) fields[name] = rest[++at];
      else fields[name] = 'true';
    }
  }
  return { command, value: values[0], fields };
}

/** This computer's time zone, as an IANA name. */
export const computerZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;

/** Runs one command and answers `{ code, text }`: the JSON answer, or a line that says what went wrong. */
export async function relay(args, { env = process.env, input = '', fetcher = fetch, zone = computerZone() } = {}) {
  const { command, value, fields } = parseArgs(args);
  const spec = COMMANDS[command];
  if (!spec) return { code: 2, text: USAGE };
  if (spec.needs && !value) return { code: 2, text: `Give ${spec.needs}: node relay.mjs ${command} <value>.` };
  const computer = readComputer(env);
  if (!computer) return { code: 1, text: NOT_CONNECTED };
  if (spec.field) fields[spec.field] = value;
  if (spec.zone !== false && !fields.timezone && zone) fields.timezone = zone;
  let body;
  if (spec.add) {
    const text = String(input ?? '').trim();
    if (!text) return { code: 2, text: 'Give the note on stdin.' };
    body = { clientId: randomUUID(), text, ...fields };
    for (const key of ['lat', 'lon', 'accuracy']) if (key in body) body[key] = Number(body[key]);
  }
  let answer;
  for (const last of [false, true]) {
    try {
      answer = await api(computer, spec.path(value), { query: body ? {} : fields, body, fetcher });
      break;
    } catch (error) {
      // A lost answer to add-note is sent again with the same clientId, so the note is stored once.
      if (last || !spec.add) return { code: 1, text: withSandbox(`Relay Everything at ${computer.api} could not be reached. Try again in a minute.`, error) };
    }
  }
  const { status, json } = answer;
  if (status === 200 || status === 201) return { code: 0, text: JSON.stringify(json) };
  const why = reason(json) ?? `It answered ${status}.`;
  // The server sends an old chat key's refusal as CHAT_KEY itself; a key that is turned off or unknown has its own.
  if (why === CHAT_KEY) return { code: 1, text: CHAT_KEY };
  if (status === 401 || status === 403) return { code: 1, text: `Relay Everything refused this computer's key: ${why} Type /relay:connect to connect again.` };
  return { code: 1, text: `Relay Everything refused the request: ${why}` };
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const args = process.argv.slice(2);
  let input = '';
  if (args[0] === 'add-note') for await (const part of process.stdin) input += part;
  const { code, text } = await relay(args, { input });
  console.log(text);
  process.exitCode = code;
}
