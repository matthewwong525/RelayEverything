#!/usr/bin/env node
// Moves a WongStack project's memory into this computer's Relay Everything space, once, and again to catch up. It
// reads the source only through that checkout's memory. wiki/stack/relay-knowledge-web.md#move-a-wongstack-memory-in
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { readComputer } from '../plugin/lib/config.mjs';
import { isMain, parseCli, usageError } from './lib-cli.mjs';

const USAGE = 'usage: import-wongstack-memory.mjs --from <WongStack checkout> [--profile <file>] [--dry-run]';
const CHUNK = 200;
// A run of empty number ranges this long ends the read, so a store that counts a fact it never gives stops.
const EMPTY_RANGES = 50;
// The only requests the import makes of the source: a store that refuses every write still works.
const READS = ['caller', 'facts', 'tags', 'session', 'transcript', 'stats'];

/** The source store with only its read requests, so no code path here can write to it. */
const readOnly = store => Object.fromEntries(READS.map(op => [op, (...args) => store[op](...args)]));

/** The checkout's own memory store, opened with `profile` when given, else the checkout's profile. */
async function openSource(from, profile) {
  const root = resolve(from);
  const lib = ['.claude', '.agents'].map(dir => join(root, dir, 'skills', 'memory', 'scripts', 'lib', 'store.mjs')).find(existsSync);
  if (!lib) throw new Error(`${root} holds no WongStack memory: no .claude/skills/memory or .agents/skills/memory.`);
  if (profile) process.env.WONG_MEMORY_PROFILE = resolve(profile);
  const { openStore, repoContext } = await import(pathToFileURL(lib).href);
  return openStore(repoContext(root));
}

/** Every fact in the source, replaced ones too, read by number ranges until the count reaches the source's total. */
async function readFacts(source, total) {
  const facts = [];
  for (let start = 1, empty = 0; facts.length < total && empty < EMPTY_RANGES; start += CHUNK) {
    const ids = Array.from({ length: CHUNK }, (_, at) => start + at);
    const [found] = await source.facts([{ ids, all: true, everyone: true, withTags: true }]);
    empty = found.length ? 0 : empty + 1;
    facts.push(...found);
  }
  return facts.sort((a, b) => a.id - b.id);
}

/** Each session the facts came from, as the source keeps it; one the source does not give is left out. */
async function readSessions(source, facts) {
  const ids = [...new Set(facts.map(fact => fact.session_id).filter(Boolean))];
  const rows = await Promise.all(ids.map(id => source.session({ id })));
  return rows.filter(Boolean);
}

/** What the source holds, read once. */
async function readSource(source) {
  const [who, stats, tags] = await Promise.all([source.caller(), source.stats(), source.tags()]);
  const facts = await readFacts(source, Number(stats.totals.facts));
  const sessions = await readSessions(source, facts);
  return { who, stats, tags, facts, sessions, highest: facts.reduce((top, fact) => Math.max(top, fact.id), 0) };
}

/** A POST to the space's import route with this computer's key; a refusal throws its words. */
function spaceClient(computer, send) {
  const post = async (path, body, type = 'application/json') => {
    const response = await send(`${computer.api}/memory/import${path}`, { method: 'POST', body,
      headers: { Authorization: `Bearer ${computer.key}`, 'Content-Type': type } });
    const answer = await response.json().catch(() => ({}));
    const why = answer.error_description ?? answer.error ?? 'no reason given';
    if (!response.ok) throw new Error(`Relay Everything refused the import (HTTP ${response.status}): ${why}`);
    return answer;
  };
  return {
    send: body => post('', JSON.stringify(body)),
    transcript: (session, bytes) => post(`/transcript?session=${encodeURIComponent(session)}`, bytes, 'application/octet-stream'),
  };
}

/** The facts in chunks of CHUNK, in number order, each with the sessions it names first; the tags go with the first. */
function chunks({ who, facts, sessions, tags }) {
  const byId = new Map(sessions.map(row => [row.id, row]));
  const sent = new Set();
  const parts = [];
  for (let at = 0; at === 0 || at < facts.length; at += CHUNK) {
    const part = facts.slice(at, at + CHUNK);
    const named = [...new Set(part.map(fact => fact.session_id))].filter(id => byId.has(id) && !sent.has(id));
    for (const id of named) sent.add(id);
    parts.push({ subject: who.subject ?? null, facts: part, sessions: named.map(id => byId.get(id)), tags: at === 0 ? tags : [] });
  }
  return parts;
}

/** Each session's transcript, read through its first fact and sent to the space: kept, already there, or missing. */
async function sendTranscripts(source, space, { facts, sessions }) {
  const tally = { kept: 0, skipped: 0, missing: 0 };
  for (const { id } of sessions) {
    const first = facts.find(fact => fact.session_id === id);
    const bytes = await source.transcript({ factId: first.id });
    if (!(bytes instanceof Uint8Array)) { tally.missing += 1; continue; }
    const answer = await space.transcript(id, bytes);
    tally[answer.skipped ? 'skipped' : 'kept'] += 1;
  }
  return tally;
}

/** Where the space's counts of imported facts differ from the source's own: live by kind, and all facts. */
function differences(stats, counts) {
  const live = Object.fromEntries(stats.types.map(({ type, n }) => [type, Number(n)]));
  const kinds = [...new Set([...Object.keys(live), ...Object.keys(counts.live)])].sort();
  const lines = kinds.filter(kind => (live[kind] ?? 0) !== (counts.live[kind] ?? 0))
    .map(kind => `live ${kind}: source ${live[kind] ?? 0}, space ${counts.live[kind] ?? 0}`);
  const all = Object.values(counts.all).reduce((sum, n) => sum + n, 0);
  if (Number(stats.totals.facts) !== all) lines.push(`all facts: source ${stats.totals.facts}, space ${all}`);
  return lines;
}

const counted = read => `${read.facts.length} facts (${read.facts.filter(fact => fact.superseded_by == null).length} live), ` +
  `${read.sessions.length} sessions, ${read.tags.length} tags, highest #${read.highest}`;

/** One import run. `source`, `computer` and `fetch` default to the checkout's store, this computer's key and fetch. */
export async function run({ from, profile, dryRun = false, source, computer, fetch: send = fetch, log = console.log }) {
  const reader = readOnly(source ?? await openSource(from, profile));
  const read = await readSource(reader);
  log(`Source: ${counted(read)}.`);
  if (dryRun) return { ok: true, dryRun: true, read };
  const key = computer ?? readComputer();
  if (!key) throw new Error('This computer is not connected to Relay Everything. Type /relay:connect first.');
  const space = spaceClient(key, send);
  const status = await space.send({});
  if (status.imported === 0) {
    const { moved } = await space.send({ start: { highest: read.highest } });
    log(`Start: moved ${moved} of the space's own facts above #${read.highest}.`);
  }
  const total = { added: 0, skipped: 0, renumbered: [] };
  for (const part of chunks(read)) {
    const answer = await space.send(part);
    total.added += answer.added;
    total.skipped += answer.skipped;
    total.renumbered.push(...answer.renumbered);
  }
  log(`Facts: ${total.added} added, ${total.skipped} there already${total.renumbered.map(({ old, new: now }) => `, #${old} is now #${now}`).join('')}.`);
  const transcripts = await sendTranscripts(reader, space, read);
  log(`Transcripts: ${transcripts.kept} kept, ${transcripts.skipped} there already, ${transcripts.missing} missing in the source.`);
  const links = read.facts.filter(fact => fact.superseded_by != null).map(fact => ({ id: fact.id, by: fact.superseded_by }));
  const finish = await space.send({ finish: { links } });
  const wrong = differences(read.stats, finish.counts);
  log(wrong.length ? `Counts differ from the source: ${wrong.join('; ')}.` : `Counts match the source: ${finish.linked} links set in this run.`);
  return { ok: wrong.length === 0, ...total, transcripts, linked: finish.linked, counts: finish.counts, differences: wrong };
}

if (isMain(import.meta.url)) {
  const { values } = parseCli({ usage: USAGE, options: { from: { type: 'string' }, profile: { type: 'string' }, 'dry-run': { type: 'boolean' } } });
  if (!values.from) usageError(USAGE, 'Name the WongStack checkout with --from.');
  run({ from: values.from, profile: values.profile, dryRun: values['dry-run'] })
    .then(result => process.exit(result.ok ? 0 : 1))
    .catch(error => { console.error(error.message); process.exit(1); });
}
