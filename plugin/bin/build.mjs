#!/usr/bin/env node
// The daily build of the person's knowledge web: the agent's one narrow command, which has no health, day, place,
// calendar or photo read, and the detached `run` that claims the day, starts the agent and syncs.
import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { appendFileSync, closeSync, existsSync, lstatSync, mkdirSync, openSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { copyOf, home, readComputer } from '../lib/config.mjs';
import { appOf, buildCommand, childEnv, shellWord, STOP_AFTER } from '../lib/headless.mjs';
import { api } from '../lib/server.mjs';
import { frontmatter, linksIn, readTopic, topicPages, wordsOf } from '../lib/topics.mjs';
import { sync } from './knowledge.mjs';
import { computerZone, NOT_CONNECTED, parseArgs, relay } from './relay.mjs';

const self = fileURLToPath(import.meta.url);
const PROMPTS = fileURLToPath(new URL('../build/', import.meta.url));
/** The most a build reads: chats and notes, newest first. */
export const MOST_CHATS = 20;
export const MOST_NOTES = 100;
/** A chat is read once it has been quiet this long, so the chat in progress waits. */
export const QUIET = 3_600_000;
/** What `check-facts` and `related` show. */
export const MOST_CLOSE = 5;
export const MOST_RELATED = 10;
const MOST_PAGES = 200;
const ID = /^[\w-]{1,64}$/;
export const USAGE = 'Commands: work, chat <id> [--after <seq>], note <id>..., notes --q|--tag, facts --q|--tag|--source, columns, check-facts <json>, '
  + 'related <topic>, add-facts <json>, tag fact|note <id> --add --remove, remove-page topics/<name>.md, done chat <id> <seq> | done note <id>, '
  + 'status, off, on, now.';
export const CHATS_WAIT = 'Your Relay Everything server lists chats only with search words, so chats wait for a newer server.';

const settingsFile = env => join(home(env), 'build.json');
const runLog = env => join(home(env), 'build', 'run.log');
const relayDir = copy => join(copy, '.relay');

export function readSettings(env) {
  try { return JSON.parse(readFileSync(settingsFile(env), 'utf8')); } catch { return {}; }
}

function writeSettings(env, change) {
  const next = { ...readSettings(env), ...change };
  mkdirSync(home(env), { recursive: true });
  writeFileSync(settingsFile(env), JSON.stringify(next), { mode: 0o600 });
  return next;
}

/** The day in the zone, as YYYY-MM-DD. */
export const dayOf = (time, zone = computerZone()) => new Intl.DateTimeFormat('en-CA', { timeZone: zone }).format(new Date(time));

/** Whether a chat start should start today's build: the build is on here, and today was not tried yet. */
export const buildDue = (env, now = Date.now(), zone = computerZone()) => {
  const settings = readSettings(env);
  return !settings.off && settings.tried !== dayOf(now, zone);
};

/** Marks today tried, so a second chat start, or a failed run, starts nothing more today. */
export const markTried = (env, now = Date.now(), zone = computerZone()) => writeSettings(env, { tried: dayOf(now, zone) });

const lines = path => (existsSync(path) ? readFileSync(path, 'utf8').split('\n').map(line => line.trim()).filter(Boolean) : []);

/** The read record: each chat's last message read, the highest wins, and each note read. */
export function readRecord(copy) {
  const chats = new Map();
  const notes = new Set();
  for (const line of lines(join(relayDir(copy), 'read.log'))) {
    const [kind, id, seq] = line.split(/\s+/);
    if (kind === 'note') notes.add(id);
    else if (kind === 'chat' && Number(seq) > (chats.get(id) ?? -1)) chats.set(id, Number(seq));
  }
  return { chats, notes };
}

/**
 * A note as the build reads it: only its own words and their details, by name, so the place, the places nearby, the
 * day's health and any field a newer server adds never reach the build.
 */
const NOTE_FIELDS = ['id', 'title', 'source', 'text', 'recordedAt', 'device', 'audio', 'attachments', 'tags'];
const noteOf = note => Object.fromEntries(NOTE_FIELDS.filter(name => note?.[name] !== undefined).map(name => [name, note[name]]));

/** Appends one line of what this run did, for the done line; only a build run keeps it. */
function logRun(env, entry) {
  if (!env.RELAY_BUILD_RUN) return;
  mkdirSync(dirname(runLog(env)), { recursive: true });
  appendFileSync(runLog(env), `${JSON.stringify(entry)}\n`);
}

/** Every page of one list, up to MOST_PAGES. */
async function pages(computer, path, query, key, fetcher) {
  const all = [];
  let cursor;
  for (let page = 0; page < MOST_PAGES; page++) {
    const { status, json } = await api(computer, path, { query: { ...query, ...cursor && { cursor } }, fetcher });
    if (status !== 200) return { status, items: all };
    all.push(...json?.[key] ?? []);
    cursor = json?.nextCursor;
    if (!cursor) break;
  }
  return { status: 200, items: all };
}

/**
 * The work list: quiet chats past the read record that memory did not read, and notes not in it, newest first, at
 * most MOST_CHATS and MOST_NOTES, each with where to read from and its day, and how many more are left.
 */
export async function work({ env = process.env, fetcher = fetch, now = Date.now(), zone = computerZone() } = {}) {
  const computer = readComputer(env);
  if (!computer) return { code: 1, text: NOT_CONNECTED };
  const record = readRecord(copyOf(env));
  const chats = await pages(computer, '/chats', { limit: '20', timezone: zone }, 'chats', fetcher);
  const notes = await pages(computer, '/notes', { from: '2001-01-01', to: '2286-01-01', limit: '100', timezone: zone }, 'notes', fetcher);
  if (notes.status !== 200) return { code: 1, text: `Relay Everything refused the list of notes: it answered ${notes.status}.` };
  // A chat that memory already read is left out: its facts are in the space.
  const unreadChats = chats.items.filter(chat => !chat.memory && now - Date.parse(chat.lastAt) >= QUIET
    && chat.messages - 1 > (record.chats.get(chat.id) ?? -1))
    .map(chat => ({ id: chat.id, title: chat.title, project: chat.project, after: record.chats.get(chat.id) ?? -1, messages: chat.messages,
      day: chat.lastAt.slice(0, 10) }));
  const unreadNotes = notes.items.filter(note => !record.notes.has(note.id))
    .map(note => ({ id: note.id, title: note.title, day: note.recordedAt.slice(0, 10) }));
  const answer = { chats: unreadChats.slice(0, MOST_CHATS), notes: unreadNotes.slice(0, MOST_NOTES),
    left: { chats: Math.max(0, unreadChats.length - MOST_CHATS), notes: Math.max(0, unreadNotes.length - MOST_NOTES) } };
  // An older server needs words to list chats, and answers 400 without them.
  if (chats.status === 400) answer.chatsWait = CHATS_WAIT;
  else if (chats.status !== 200) return { code: 1, text: `Relay Everything refused the list of chats: it answered ${chats.status}.` };
  return { code: 0, text: JSON.stringify(answer), json: answer };
}

/** A fact's clientId from its sources and text, so a resend, in this run or the next, stores it once. */
export const clientIdOf = fact => `b-${createHash('sha256').update(JSON.stringify([fact.sources ?? [], fact.fields?.text ?? ''])).digest('hex').slice(0, 40)}`;

const json = text => { try { return JSON.parse(text); } catch { return undefined; } };
const factsIn = input => { const given = json(input); return Array.isArray(given) ? given : given?.facts; };
const shortFact = fact => ({ id: fact.id, kind: fact.fields?.kind, text: fact.fields?.text, tags: fact.tags });

async function addFacts(options) {
  const facts = factsIn(options.input);
  if (!Array.isArray(facts) || !facts.every(fact => fact && typeof fact === 'object')) return { code: 2, text: 'Give the facts as a JSON list: add-facts \'<json>\'.' };
  const sent = facts.map(fact => ({ clientId: clientIdOf(fact), ...fact }));
  const done = await relay(['add-facts'], { ...options, input: JSON.stringify(sent) });
  if (done.code === 0) {
    const stored = new Set((json(done.text)?.facts ?? []).filter(fact => fact.added).map(fact => fact.clientId));
    const added = sent.filter(fact => stored.has(fact.clientId));
    logRun(options.env, { did: 'facts', added: added.length, replaced: added.reduce((sum, fact) => sum + (fact.replaces?.length ?? 0), 0),
      tags: [...new Set(added.flatMap(fact => fact.tags ?? []))] });
  }
  return done;
}

/** For each candidate fact, the live facts that share a tag and those that hold its longest words, MOST_CLOSE each. */
async function checkFacts(options) {
  const facts = factsIn(options.input);
  if (!Array.isArray(facts)) return { code: 2, text: 'Give the candidate facts as a JSON list: check-facts \'<json>\'.' };
  const read = async args => {
    const done = await relay(['facts', ...args, '--limit', String(MOST_CLOSE)], options);
    if (done.code !== 0) throw done;
    return json(done.text)?.facts ?? [];
  };
  try {
    const answer = [];
    for (const fact of facts) {
      const byTag = new Map();
      for (const tag of fact.tags ?? []) for (const found of await read(['--tag', tag])) byTag.set(found.id, found);
      const words = [...new Set(wordsOf(fact.fields?.text).filter(word => word.length >= 4))].sort((a, b) => b.length - a.length).slice(0, 2);
      const byWords = words.length ? await read(['--q', words.join(' ')]) : [];
      answer.push({ text: fact.fields?.text, byTag: [...byTag.values()].slice(0, MOST_CLOSE).map(shortFact), byWords: byWords.map(shortFact) });
    }
    return { code: 0, text: JSON.stringify(answer) };
  } catch (failed) {
    return failed;
  }
}

/** A topic's own name or one of its parts: `bike` holds `bike/charging`. */
const within = (tag, topic) => tag === topic || tag.startsWith(`${topic}/`);

/**
 * The topics that share facts, sources or notes with one topic, at most MOST_RELATED, ranked by how much they
 * share, each with a sample shared fact and whether a page already links the other.
 */
async function related(topic, options) {
  const read = async (path, query) => {
    const { status, json: got } = await api(options.computer, path, { ...query, fetcher: options.fetcher });
    if (status !== 200) throw { code: 1, text: `Relay Everything refused a read of ${path}: it answered ${status}.` };
    return got;
  };
  const found = new Map();
  const count = (tags, kind, fact) => {
    for (const tag of new Set(tags)) {
      if (within(tag, topic)) continue;
      const one = found.get(tag) ?? { topic: tag, facts: 0, sources: 0, notes: 0, sample: null };
      one[kind]++;
      one.sample ??= fact?.fields?.text ?? null;
      found.set(tag, one);
    }
  };
  try {
    const facts = (await read('/memory', { query: { tag: topic, limit: '50' } })).facts ?? [];
    for (const fact of facts) count(fact.tags, 'facts', fact);
    // Only chats count as shared sources: a note's topics count on their own, and a day is shared by everything on it.
    const sources = [...new Set(facts.flatMap(fact => fact.sources ?? []).map(source => source.split('#')[0]))]
      .filter(source => source.startsWith('relay:chat/')).slice(0, MOST_RELATED);
    for (const source of sources) {
      const others = (await read('/memory', { query: { source, limit: '50' } })).facts ?? [];
      count(others.filter(fact => !fact.tags.some(tag => within(tag, topic))).flatMap(fact => fact.tags), 'sources',
        others.find(fact => !fact.tags.some(tag => within(tag, topic))));
    }
    const notes = (await read('/notes', { query: { tag: topic, limit: '10' } })).notes ?? [];
    // A note's answer lists no topics; an empty change answers them and changes nothing.
    for (const note of notes) count((await read(`/notes/${encodeURIComponent(note.id)}/tags`, { body: { add: [], remove: [] } })).tags ?? [], 'notes');
  } catch (failed) {
    return failed;
  }
  const copy = copyOf(options.env);
  const pages = topicPages(copy);
  const out = readTopic(copy, topic, pages)?.links ?? [];
  const into = pages.has(topic) ? linksIn(copy, topic, pages) : [];
  const ranked = [...found.values()].sort((a, b) => (b.facts + b.sources + b.notes) - (a.facts + a.sources + a.notes) || a.topic.localeCompare(b.topic))
    .slice(0, MOST_RELATED).map(one => ({ ...one, page: pages.has(one.topic),
      linked: out.includes(one.topic) ? 'this page links it' : into.includes(one.topic) ? 'it links this page' : null }));
  return { code: 0, text: JSON.stringify({ topic, related: ranked }) };
}

/** Marks one item read in the web's read record, so a stopped build keeps what it did. */
function done({ value, second, third, env }) {
  if (!['chat', 'note'].includes(value) || !ID.test(second ?? '') || (value === 'chat' && !/^\d{1,8}$/.test(third ?? ''))) {
    return { code: 2, text: 'Give done chat <id> <last seq read>, or done note <id>.' };
  }
  const dir = relayDir(copyOf(env));
  mkdirSync(dir, { recursive: true });
  appendFileSync(join(dir, 'read.log'), `${value} ${second}${value === 'chat' ? ` ${third}` : ''}\n`);
  logRun(env, { did: value, id: second });
  return { code: 0, text: `Marked ${value} ${second} read.` };
}

async function notesRead(ids, options) {
  if (!ids.length || !ids.every(id => ID.test(id))) return { code: 2, text: 'Give one or more note ids: note <id>...' };
  const read = [];
  for (const id of ids) {
    const one = await relay(['note', id], options);
    if (one.code !== 0) return one;
    read.push(noteOf(json(one.text)));
  }
  return { code: 0, text: JSON.stringify(ids.length === 1 ? read[0] : { notes: read }) };
}

/** A topic page's path in the copy: under `topics/`, a `.md` file, with no `.` or `..` part. */
const PAGE_PATH = /^topics\/(?:[\w-]+\/)*[\w-]+\.md$/;

/** Removes one topic page from the copy, as a join needs; the build's grant can't delete a file, and this deletes nothing else. */
function removePage({ value, env }) {
  const path = String(value ?? '');
  if (!PAGE_PATH.test(path)) return { code: 2, text: 'Give one page in topics/: remove-page topics/<name>.md.' };
  const copy = copyOf(env);
  const file = join(copy, ...path.split('/'));
  let real;
  try {
    if (!lstatSync(file).isFile()) throw new Error('not a file');
    real = realpathSync(dirname(file));
  } catch {
    return { code: 1, text: `No page is at ${path}.` };
  }
  const topics = realpathSync(join(copy, 'topics'));
  if (real !== topics && !real.startsWith(`${topics}${sep}`)) return { code: 2, text: `${path} is not in topics/.` };
  rmSync(file);
  return { code: 0, text: `Removed ${path}.` };
}

/** Only the fields the build may give, as `--name value` flags for relay.mjs. */
const flags = (fields, keep) => Object.entries(fields).filter(([name]) => keep.includes(name)).flatMap(([name, value]) => [`--${name}`, value]);

const AGENT = {
  work: options => work(options),
  chat: ({ value, fields, ...options }) => (ID.test(value ?? '') ? relay(['chat', value, ...(Number(fields.after) >= 0 ? ['--cursor', String(fields.after)] : [])], options)
    : { code: 2, text: 'Give the chat id: chat <id> --after <seq>.' }),
  note: ({ ids, ...options }) => notesRead(ids, options),
  notes: async ({ fields, ...options }) => {
    if (!fields.q && !fields.tag) return { code: 2, text: 'Give --q <words> or --tag <topic>.' };
    const found = await relay(['notes', ...flags(fields, ['q', 'tag', 'limit', 'cursor'])], options);
    if (found.code !== 0) return found;
    const { notes = [], nextCursor = null } = json(found.text) ?? {};
    return { code: 0, text: JSON.stringify({ notes: notes.map(noteOf), nextCursor }) };
  },
  facts: ({ fields, ...options }) => relay(['facts', ...flags(fields, ['q', 'tag', 'source', 'kind', 'all', 'limit', 'cursor'])], options),
  columns: options => relay(['columns'], options),
  'check-facts': options => checkFacts(options),
  'add-facts': options => addFacts(options),
  related: ({ value, ...options }) => (value ? related(String(value).toLowerCase().replace(/^#/, ''), options) : { code: 2, text: 'Give the topic: related <topic>.' }),
  tag: async ({ value, second, fields, ...options }) => {
    const changed = await relay(['tag', value, second, ...flags(fields, ['add', 'remove'])], options);
    if (changed.code === 0) logRun(options.env, { did: 'tag', kind: value, tags: (fields.add ?? '').split(',').map(tag => tag.trim()).filter(Boolean) });
    return changed;
  },
  'remove-page': options => removePage(options),
  done: options => done(options),
};

/** What `status` shows: the switch, the last build and how much is still to read, with no network call. */
export function status({ env = process.env, zone = computerZone() } = {}) {
  const settings = readSettings(env);
  const said = [settings.off ? 'The daily build is off on this computer. Type /relay-build on to start it again.'
    : 'The daily build is on for this computer: it starts with the first chat of each day.'];
  const log = lines(join(relayDir(copyOf(env)), 'builds.log'));
  const claim = log.filter(line => !line.split(' ')[1]?.startsWith('done')).at(-1);
  if (!claim) said.push('No build has run yet.');
  else {
    const [day, at, ...rest] = claim.split(' ');
    const clock = new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: zone }).format(new Date(at));
    said.push(`Last build: ${day} ${clock}, on ${rest.slice(0, -1).join(' ') || 'a computer'}`);
    const counts = Object.fromEntries((log.filter(line => line.startsWith(`${day} done`)).at(-1) ?? '').split(' ').slice(2).map(pair => pair.split('=')));
    if (counts.chats !== undefined) {
      said.push(`  ${counts.chats} chats, ${counts.notes} notes read`, `  ${counts.facts} facts added, ${counts.replaced} replaced`);
      const made = (counts.new ?? '').split(',').filter(Boolean);
      if (made.length) said.push(`  ${made.length} new topics: ${made.join(', ')}`);
    } else said.push('  It has not ended, or it stopped before its counts.');
  }
  if (settings.left) said.push(`Still to read: ${settings.left.chats} chats, ${settings.left.notes} notes`);
  if (settings.error) said.push(`The last try on this computer: ${settings.error}`);
  return { code: 0, text: said.join('\n') };
}

/** Today's claims in the web, earliest first: `{ day, at, name, id }`. */
export function claims(copy, day) {
  return lines(join(relayDir(copy), 'builds.log')).map(line => line.split(' ')).filter(([first, at]) => first === day && at !== 'done')
    .map(([first, at, ...rest]) => ({ day: first, at, name: rest.slice(0, -1).join(' '), id: rest.at(-1) }))
    .sort((a, b) => a.at.localeCompare(b.at) || a.id.localeCompare(b.id));
}

/** The prompt files with the build's command in place of `{{build}}`. */
const promptOf = (name, command) => readFileSync(join(PROMPTS, name), 'utf8').replaceAll('{{build}}', command);

/** The helpers as Claude Code's `--agents` JSON, from their files' frontmatter and text. */
export function helpers(command) {
  return Object.fromEntries(['reader', 'gardener'].map(name => {
    const { fields, body } = frontmatter(promptOf(`${name}.md`, command));
    return [name, { description: fields.description, prompt: body.trim(), tools: fields.tools.split(',').map(tool => tool.trim()) }];
  }));
}

/** Codex's prompt: one agent does the readers' work, then the gardener's, in order. */
export const codexPrompt = command => [promptOf('CODEX.md', command), ...['reader', 'gardener'].map(name => frontmatter(promptOf(`${name}.md`, command)).body)].join('\n\n');

/** Starts the agent, and stops it after STOP_AFTER: answers when it ends. */
function startAgent([command, args], { cwd, env }) {
  return new Promise(resolve => {
    const child = spawn(command, args, { cwd, env, detached: true, stdio: 'ignore' });
    const stop = setTimeout(() => { try { process.kill(-child.pid, 'SIGTERM'); } catch { child.kill('SIGTERM'); } }, STOP_AFTER);
    child.on('error', error => { clearTimeout(stop); resolve({ error: `${command} could not start: ${error.code ?? error.message}` }); });
    child.on('exit', code => { clearTimeout(stop); resolve({ code }); });
  });
}

/** The topics the web knew before this run: each page in the copy, and each topic an earlier build counted new. */
function knownTopics(copy) {
  const known = new Set(topicPages(copy).keys());
  for (const line of lines(join(relayDir(copy), 'builds.log'))) {
    for (const tag of (/^\S+ done .*\bnew=(\S*)$/.exec(line)?.[1] ?? '').split(',').filter(Boolean)) known.add(tag);
  }
  return known;
}

/** The SHA-256 of each earlier default `FORMAT.md`: a web that still has one word for word gets the new default. */
const OLD_FORMATS = new Set(['4224d5c920c5f963262a2323869cb3617e7f1ae037355cce011dc4729ddcb15e',
  'd96a833793c90806bef3f551c40a7ae42741c51c8fcc83c03df6aebb43dfc9c3']);
/** The default `FORMAT.md`, the same as `schema/knowledge/FORMAT.md`. */
export const FORMAT = join(PROMPTS, 'FORMAT.md');

/** Gives the copy the new default `FORMAT.md` when it has an old default; a `FORMAT.md` the person changed stays. */
function freshFormat(copy) {
  const path = join(copy, 'FORMAT.md');
  if (!existsSync(path) || !OLD_FORMATS.has(createHash('sha256').update(readFileSync(path)).digest('hex'))) return false;
  writeFileSync(path, readFileSync(FORMAT));
  return true;
}

/** What this run did, from its log: counts and the topics first used in it. */
function counted(env, before) {
  const entries = lines(runLog(env)).map(json).filter(Boolean);
  const sum = (did, key) => entries.filter(entry => entry.did === did).reduce((total, entry) => total + (key ? entry[key] : 1), 0);
  const made = [...new Set(entries.filter(entry => entry.did === 'facts' || entry.did === 'tag').flatMap(entry => entry.tags ?? []))]
    .filter(tag => !before.has(tag)).sort();
  return { facts: sum('facts', 'added'), replaced: sum('facts', 'replaced'), notes: sum('note'), chats: sum('chat'), new: made };
}

/** One lock per computer, so two starts on it never build at once; a lock older than the stop is left over. */
function lock(env) {
  const path = join(home(env), 'build', 'lock');
  mkdirSync(dirname(path), { recursive: true });
  try {
    if (Date.now() - statSync(path).mtimeMs > STOP_AFTER + 10 * 60_000) rmSync(path, { force: true });
  } catch { /* No lock yet. */ }
  try {
    closeSync(openSync(path, 'wx'));
    return () => rmSync(path, { force: true });
  } catch {
    return null;
  }
}

/**
 * One build: claim the day in the web, stop when another computer claimed it first, then start the agent on the
 * work list, append the done line and sync. `startAgent` and `syncWeb` are for tests.
 */
export async function run({ env = process.env, app = appOf(env), fetcher = fetch, now = Date.now, zone = computerZone(),
  syncWeb = options => sync(options), agent = startAgent } = {}) {
  const computer = readComputer(env);
  if (!computer) return { code: 1, text: NOT_CONNECTED };
  const unlock = lock(env);
  if (!unlock) return { code: 0, text: 'A build is already running on this computer.' };
  const stop = text => { writeSettings(env, { error: text }); return { code: 1, text }; };
  try {
    const day = dayOf(now(), zone);
    const settings = writeSettings(env, { tried: day, error: null, id: readSettings(env).id ?? randomUUID().slice(0, 8) });
    const copy = copyOf(env);
    const synced = await syncWeb({ env, fetcher, now: true });
    if (synced.code !== 0) return stop(synced.lines.join(' '));
    const first = claims(copy, day)[0];
    if (first && first.id !== settings.id) return { code: 0, text: `${first.name || 'Another computer'} builds your web today.` };
    if (!first) {
      mkdirSync(relayDir(copy), { recursive: true });
      appendFileSync(join(relayDir(copy), 'builds.log'), `${day} ${new Date(now()).toISOString()} ${computer.name || 'Computer'} ${settings.id}\n`);
      const sent = await syncWeb({ env, fetcher, now: true });
      if (sent.code !== 0) return stop(sent.lines.join(' '));
      const winner = claims(copy, day)[0];
      if (winner.id !== settings.id) return { code: 0, text: `${winner.name || 'Another computer'} builds your web today.` };
    }
    // The last sync of this run sends the new default.
    freshFormat(copy);
    const list = await work({ env, fetcher, now: now(), zone });
    if (list.code !== 0) return stop(list.text);
    const before = knownTopics(copy);
    rmSync(runLog(env), { force: true });
    if (list.json.chats.length || list.json.notes.length) {
      const command = `node ${shellWord(self)}`;
      const model = env.RELAY_BUILD_MODEL?.trim() || undefined;
      const prompt = app === 'codex' ? codexPrompt(command) : promptOf('PROMPT.md', command);
      const ended = await agent(buildCommand({ app, prompt, model, command, agents: helpers(command), copy, writable: [copy, dirname(runLog(env))] }),
        { cwd: copy, env: childEnv(env) });
      if (ended.error) writeSettings(env, { error: ended.error });
    }
    const did = counted(env, before);
    writeSettings(env, { left: { chats: Math.max(0, list.json.chats.length + list.json.left.chats - did.chats),
      notes: Math.max(0, list.json.notes.length + list.json.left.notes - did.notes) } });
    mkdirSync(relayDir(copy), { recursive: true });
    appendFileSync(join(relayDir(copy), 'builds.log'),
      `${day} done facts=${did.facts} replaced=${did.replaced} notes=${did.notes} chats=${did.chats} new=${did.new.join(',')}\n`);
    const last = await syncWeb({ env, fetcher, now: true });
    if (last.code !== 0) return stop(last.lines.join(' '));
    return { code: 0, text: `Built: ${did.chats} chats and ${did.notes} notes read, ${did.facts} facts added.` };
  } finally {
    unlock();
  }
}

/** Starts a build on its own, as a chat start does. */
export function startRun(env, app) {
  spawn(process.execPath, [self, 'run', '--app', app], { detached: true, stdio: 'ignore', env }).unref();
}

/** The commands that take a JSON list: as their one argument, or on stdin when it has none. */
const JSON_INPUT = ['add-facts', 'check-facts'];

/** Runs one command and answers `{ code, text }`. */
export async function build(args, { env = process.env, input = '', fetcher = fetch, zone = computerZone(), start = startRun } = {}) {
  const { command, value, second, fields } = parseArgs(args);
  if (command === 'status') return status({ env, zone });
  if (command === 'off' || command === 'on') {
    writeSettings(env, { off: command === 'off' });
    return status({ env, zone });
  }
  if (command === 'now') {
    if (!readComputer(env)) return { code: 1, text: NOT_CONNECTED };
    start(env, appOf(env));
    return { code: 0, text: 'A build started on its own. It runs up to 30 minutes. Type /relay-build to see what it did.' };
  }
  if (command === 'run') return run({ env, app: fields.app === 'codex' ? 'codex' : 'claude', fetcher, zone });
  if (!AGENT[command]) return { code: 2, text: USAGE };
  if (command === 'done') return done({ value, second, third: args[3], env });
  if (command === 'remove-page') return removePage({ value, env });
  const computer = readComputer(env);
  if (!computer) return { code: 1, text: NOT_CONNECTED };
  const ids = args.slice(1).filter(arg => !arg.startsWith('--'));
  // The facts come as one argument: Claude Code's narrow grant refuses a heredoc or `<` that holds `{`. Stdin still works.
  const given = JSON_INPUT.includes(command) && value !== undefined ? value : input;
  return AGENT[command]({ value, second, fields, ids, env, input: given, fetcher, zone, computer });
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const args = process.argv.slice(2);
  let input = '';
  if (JSON_INPUT.includes(args[0]) && args[1] === undefined) for await (const part of process.stdin) input += part;
  const { code, text } = await build(args, { input });
  console.log(text);
  process.exitCode = code;
}
