#!/usr/bin/env node
// The `ask` skill's one command: reads the person's Relay Everything through the web API, adds a note or facts,
// changes the memory's columns and topics, or runs agents' commands, with this computer's key, and prints the JSON
// answer. `around` and `topic` join several reads into one answer.
import { randomUUID } from 'node:crypto';
import { readFileSync, realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { copyOf, readComputer } from '../lib/config.mjs';
import { withSandbox } from '../lib/sandbox.mjs';
import { api, reason } from '../lib/server.mjs';
import { linksIn, readTopic, TOPIC, topicPages } from '../lib/topics.mjs';

export const CHAT_KEY = "This computer's key only saves chats. Type /relay:connect to connect it again.";
export const NOT_CONNECTED = 'This computer is not connected to Relay Everything. Type /relay:connect to connect it.';
const USAGE = 'Commands: me, notes, note <id>, day <YYYY-MM-DD>, health <type>, nights, workouts, places, points <id>, calendar, '
  + 'chats --q <words>, chat <id>, around <note id> or --at <time>, topic <name>, add-note, facts, fact <id>, add-facts, columns, change-columns, '
  + 'tag <fact|note> <id>, db "<sql>" [--params <JSON list>], db --file <path>, db tables. Give fields as --name value, such as --from 2026-11-03 --to 2026-11-04. add-note, add-facts and '
  + 'change-columns read stdin.';
/** `around`'s window each way, in hours: 2 unless asked, and at most 12. */
export const AROUND_HOURS = 2;
export const MOST_HOURS = 12;
/** What a topic pull reads: its newest facts, its notes, and the chats its facts came from. */
const TOPIC_FACTS = 10;
const TOPIC_NOTES = 5;
const TOPIC_CHATS = 3;

// Each command: its route, the field its one value fills, and what it sends: `id` and `day` go in the path; `send`
// reads stdin, and `resend` sends again after a lost answer, as its clientIds store it once.
const COMMANDS = {
  me: { path: () => '/me', zone: false },
  notes: { path: () => '/notes' },
  note: { path: value => `/notes/${encodeURIComponent(value)}`, needs: 'the note id' },
  day: { path: value => `/days/${encodeURIComponent(value)}`, needs: 'the day, as YYYY-MM-DD' },
  health: { path: () => '/health', field: 'type', needs: 'the kind, such as steps or sleep' },
  nights: { path: () => '/nights' },
  workouts: { path: () => '/workouts' },
  places: { path: () => '/places' },
  points: { path: () => '/points', field: 'id' },
  calendar: { path: () => '/calendar' },
  chats: { path: () => '/chats' },
  chat: { path: value => `/chats/${encodeURIComponent(value)}`, needs: 'the chat id' },
  'add-note': { path: () => '/notes', send: 'note', resend: true },
  facts: { path: () => '/memory' },
  fact: { path: value => `/memory/${encodeURIComponent(value)}`, needs: 'the fact id' },
  'add-facts': { path: () => '/memory', send: 'facts', resend: true, zone: false },
  columns: { path: () => '/memory/columns', zone: false },
  'change-columns': { path: () => '/memory/columns', send: 'json', zone: false },
  tag: { path: (value, id) => `/${value === 'note' ? 'notes' : 'memory'}/${encodeURIComponent(id)}/tags`, send: 'tags', zone: false,
    needs: 'fact or note, then its id', two: ['fact', 'note'] },
  db: { path: value => (value === 'tables' ? '/db/tables' : '/db'), send: 'db', zone: false },
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
  return { command, value: values[0], second: values[1], fields };
}

/** JSON from stdin, or undefined when it is not JSON. */
function json(input) {
  try { return JSON.parse(String(input ?? '')); } catch { return undefined; }
}

/** A comma list from one `--add` or `--remove`, such as `bike/charging,battery`. */
const list = text => (text ?? '').split(',').map(tag => tag.trim()).filter(Boolean);

/** A file's commands, one batch: each ends with `;` at the end of a line. */
const commands = text => text.split(/;[ \t]*$/m).map(sql => sql.trim()).filter(Boolean).map(sql => ({ sql }));

/** What `db` sends: one command, a file's commands, or nothing for `db tables`. */
function dbBody(value, fields) {
  if (fields.file) {
    try { return { body: { batch: commands(readFileSync(fields.file, 'utf8')) } }; } catch { return { error: `Can't read ${fields.file}.` }; }
  }
  if (value === 'tables') return {};
  if (!value) return { error: 'Give a command: node relay.mjs db "<sql>", db --file <path>, or db tables.' };
  const params = fields.params === undefined ? [] : json(fields.params);
  return Array.isArray(params) ? { body: { sql: value, params } } : { error: 'Give --params as a JSON list, such as \'["Dune", 1]\'.' };
}

/** What a command sends: `{ body }`, or `{ error }`, a line that says what to give. */
function bodyOf(send, fields, input, value) {
  if (send === 'db') return dbBody(value, fields);
  if (send === 'note') {
    const text = String(input ?? '').trim();
    if (!text) return { error: 'Give the note on stdin.' };
    const body = { clientId: randomUUID(), text, ...fields };
    for (const key of ['lat', 'lon', 'accuracy']) if (key in body) body[key] = Number(body[key]);
    return { body };
  }
  if (send === 'tags') return { body: { add: list(fields.add), remove: list(fields.remove) } };
  const given = json(input);
  if (send === 'json') return given && typeof given === 'object' ? { body: given } : { error: 'Give the change as a JSON object on stdin.' };
  const facts = Array.isArray(given) ? given : given?.facts;
  if (!Array.isArray(facts) || !facts.every(fact => fact && typeof fact === 'object')) return { error: 'Give the facts as a JSON list on stdin.' };
  return { body: { facts: facts.map(fact => ({ clientId: randomUUID(), ...fact })) } };
}

/** This computer's time zone, as an IANA name. */
export const computerZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;

/** A refusal's line: an old chat key's own, a key's, or the request's. */
function refused(status, json) {
  const why = reason(json) ?? `It answered ${status}.`;
  // The server sends an old chat key's refusal as CHAT_KEY itself; a key that is turned off or unknown has its own.
  if (why === CHAT_KEY) return { key: true, text: CHAT_KEY };
  if (status === 401 || status === 403) return { key: true, text: `Relay Everything refused this computer's key: ${why} Type /relay:connect to connect again.` };
  return { key: false, text: `Relay Everything refused the request: ${why}` };
}

const unreachable = (computer, error) => withSandbox(`Relay Everything at ${computer.api} could not be reached. Try again in a minute.`, error);

/** One read of a joined answer: `{ json }`, or `{ error, key }`, where `key` says the key itself was refused. */
async function part(computer, path, query, fetcher) {
  try {
    const { status, json } = await api(computer, path, { query, fetcher });
    if (status === 200) return { json };
    const { key, text } = refused(status, json);
    return { error: text, key };
  } catch (error) {
    return { error: unreachable(computer, error), down: true };
  }
}

/**
 * Runs named reads at once: `{ values, errors }`, a failed read's line under its name, so the rest still shows; or
 * `{ stop }` when the key is refused. Before any read of the answer has come back (`read` false), it also stops when
 * no read gets an answer, because every other read fails alike; after one, a lost answer goes under `errors`, so the
 * parts already read still show.
 */
async function gather(computer, reads, fetcher, read = false) {
  const names = Object.keys(reads);
  const got = await Promise.all(names.map(name => part(computer, ...reads[name], fetcher)));
  const stop = got.find(one => one.key) ?? (!read && got.length && got.every(one => one.down) ? got[0] : null);
  if (stop) return { stop: { code: 1, text: stop.error } };
  const values = {};
  const errors = {};
  names.forEach((name, at) => { if (got[at].error) errors[name] = got[at].error; else values[name] = got[at].json; });
  return { values, errors };
}

/** A joined answer, with `errors` only when a read failed. */
const answered = (answer, errors) => ({ code: 0, text: JSON.stringify(Object.keys(errors).length ? { ...answer, errors } : answer) });

const TIME = /^(\d{4}-\d{2}-\d{2})(?:T(\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?))?(Z|[+-]\d{2}:?\d{2})?$/;
const HOUR = 3_600_000;
const pad = number => String(number).padStart(2, '0');

/**
 * A time moved by some hours. A time with an offset moves in real time and keeps its offset; one with none moves as
 * clock text, which the server reads in the time zone, as it reads every other time.
 */
export function shiftTime(text, hours) {
  const [, date, clock = '00:00', offset] = TIME.exec(text);
  const minutes = !offset || offset === 'Z' ? 0
    : (offset[0] === '-' ? -1 : 1) * (Number(offset.slice(1, 3)) * 60 + Number(offset.slice(-2)));
  const at = Date.parse(`${date}T${clock}Z`) - minutes * 60_000 + hours * HOUR;
  const shifted = new Date(at + minutes * 60_000).toISOString().slice(0, 19);
  if (!offset) return shifted;
  return offset === 'Z' ? `${shifted}Z` : `${shifted}${offset[0]}${pad(Math.floor(Math.abs(minutes) / 60))}:${pad(Math.abs(minutes) % 60)}`;
}

/** The day a time falls on in the zone: a time with an offset by the zone's clock, one with none by its own date. */
export function dayIn(text, zone) {
  const [, date, , offset] = TIME.exec(text);
  if (!offset) return date;
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' })
    .formatToParts(new Date(Date.parse(text.replace(/([+-]\d{2})(\d{2})$/, '$1:$2')))).map(({ type, value }) => [type, value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

/**
 * Everything around a note or a time, in one answer: the note, its day's summary, and the notes, places, calendar
 * events and hourly steps and heart rate from `hours` before to `hours` after.
 */
async function around(computer, { value, fields, zone, fetcher }) {
  const timezone = fields.timezone ?? zone;
  const hours = fields.hours === undefined ? AROUND_HOURS : Number(fields.hours);
  if (!(hours >= 1 && hours <= MOST_HOURS)) return { code: 2, text: `Give --hours from 1 to ${MOST_HOURS}: the window is at most ${MOST_HOURS} hours each way.` };
  const zoned = { timezone };
  const answer = {};
  let at = fields.createdAt;
  if (value) {
    const note = await part(computer, `/notes/${encodeURIComponent(value)}`, zoned, fetcher);
    if (note.error) return { code: 1, text: note.error };
    answer.note = note.json;
    at = note.json?.recordedAt ?? note.json?.createdAt;
  }
  if (typeof at !== 'string' || !TIME.test(at)) {
    return { code: 2, text: 'Give a note id, or --at <time> as 2026-11-04T14:20 or a time with its offset: node relay.mjs around <note id>.' };
  }
  const [from, to] = [shiftTime(at, -hours), shiftTime(at, hours)];
  const span = { from, to, timezone };
  const got = await gather(computer, {
    day: [`/days/${dayIn(at, timezone)}`, zoned],
    notes: ['/notes', span],
    places: ['/places', span],
    calendar: ['/calendar', span],
    'health.steps': ['/health', { type: 'steps', bucket: 'hour', ...span }],
    'health.heart_rate': ['/health', { type: 'heart_rate', bucket: 'hour', ...span }],
  }, fetcher, Boolean(answer.note));
  if (got.stop) return got.stop;
  const { 'health.steps': steps, 'health.heart_rate': heartRate, ...read } = got.values;
  return answered({ at, from, to, timezone, hours, ...answer, ...read, health: { steps, heart_rate: heartRate } }, got.errors);
}

/** The chat ids that facts name in their sources, such as `relay:chat/7f3a#120`, in the facts' order. */
const chatIds = facts => [...new Set((facts ?? []).flatMap(fact => fact?.sources ?? [])
  .map(source => /^relay:chat\/([^#\s]+)/.exec(String(source))?.[1]).filter(Boolean))];

/**
 * A topic and one step around it, in one answer: its page and the topics it links and that link it, from this
 * computer's copy; its newest facts and notes, and the titles and summaries of the chats those facts came from.
 */
async function topic(computer, { value, env, zone, fields, fetcher }) {
  const name = String(value).toLowerCase().replace(/^#/, '').replace(/^\/+|\/+$/g, '');
  if (!TOPIC.test(name)) return { code: 2, text: 'Give a topic name, such as battery or bike/charging: node relay.mjs topic <name>.' };
  const timezone = fields.timezone ?? zone;
  const dir = copyOf(env);
  const pages = topicPages(dir);
  const page = readTopic(dir, name, pages);
  const answer = { topic: name, summary: page?.summary ?? null, page: page?.text ?? null,
    linked: { out: page?.links ?? [], in: page ? linksIn(dir, name, pages) : [] } };
  const first = await gather(computer, {
    facts: ['/memory', { tag: name, limit: String(TOPIC_FACTS), timezone }],
    notes: ['/notes', { tag: name, limit: String(TOPIC_NOTES), timezone }],
  }, fetcher);
  if (first.stop) return first.stop;
  const facts = first.values.facts?.facts ?? [];
  const ids = chatIds(facts).slice(0, TOPIC_CHATS);
  const chats = await gather(computer, Object.fromEntries(ids.map(id => [`chat ${id}`, [`/chats/${encodeURIComponent(id)}`, { timezone }]])), fetcher,
    Object.keys(first.values).length > 0);
  if (chats.stop) return chats.stop;
  const shown = ids.filter(id => chats.values[`chat ${id}`]).map(id => {
    const { title, project, app, startedAt, lastAt, saves } = chats.values[`chat ${id}`];
    // The server sends a chat's saves newest first: the first is its latest summary.
    return { id, title, project, app, startedAt, lastAt, summary: saves?.[0]?.text ?? null };
  });
  return answered({ ...answer, facts, notes: first.values.notes?.notes ?? [], chats: shown }, { ...first.errors, ...chats.errors });
}

const JOINED = { around: { run: around }, topic: { run: topic, needs: 'the topic name' } };

/** Runs one command and answers `{ code, text }`: the JSON answer, or a line that says what went wrong. */
export async function relay(args, { env = process.env, input = '', fetcher = fetch, zone = computerZone() } = {}) {
  const { command, value, second, fields } = parseArgs(args);
  if (JOINED[command]) {
    if (JOINED[command].needs && !value) return { code: 2, text: `Give ${JOINED[command].needs}: node relay.mjs ${command} <value>.` };
    const computer = readComputer(env);
    if (!computer) return { code: 1, text: NOT_CONNECTED };
    return JOINED[command].run(computer, { value, fields, env, zone, fetcher });
  }
  const spec = COMMANDS[command];
  if (!spec) return { code: 2, text: USAGE };
  if (spec.needs && (!value || (spec.two && (!spec.two.includes(value) || !second)))) {
    return { code: 2, text: `Give ${spec.needs}: node relay.mjs ${command} <value>.` };
  }
  const computer = readComputer(env);
  if (!computer) return { code: 1, text: NOT_CONNECTED };
  if (spec.field) fields[spec.field] = value;
  if (spec.zone !== false && !fields.timezone && zone) fields.timezone = zone;
  const { body, error: missing } = spec.send ? bodyOf(spec.send, fields, input, value) : {};
  if (missing) return { code: 2, text: missing };
  let answer;
  for (const last of [false, true]) {
    try {
      answer = await api(computer, spec.path(value, second), { query: body ? {} : fields, body, fetcher });
      break;
    } catch (error) {
      if (last || !spec.resend) return { code: 1, text: unreachable(computer, error) };
    }
  }
  const { status, json } = answer;
  if (status === 200 || status === 201) return { code: 0, text: JSON.stringify(json) };
  return { code: 1, text: refused(status, json).text };
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const args = process.argv.slice(2);
  let input = '';
  if (COMMANDS[args[0]]?.send && !['tags', 'db'].includes(COMMANDS[args[0]].send)) for await (const part of process.stdin) input += part;
  const { code, text } = await relay(args, { input });
  console.log(text);
  process.exitCode = code;
}
