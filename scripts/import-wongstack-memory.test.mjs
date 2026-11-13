// The WongStack memory import, against a source that refuses every write and a stand-in Relay Everything import route.
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { run } from './import-wongstack-memory.mjs';

const ME = 'wongos-subject-1';
const COMPUTER = { api: 'https://relay.example.test/v1', key: `rek_${'k'.repeat(43)}` };
const WRITES = ['digest', 'write', 'defineTag', 'putSession', 'putTranscript', 'putRun'];
const quiet = () => {};

/** A source memory store: `facts` by number, sessions, tags and transcripts; every write throws and is counted. */
function sourceStore() {
  const data = { facts: [], sessions: new Map(), transcripts: new Map(), tags: [{ name: 'battery', definition: 'The battery.', alias_of: null, uses: 2 }] };
  const writes = [];
  const fact = (id, more = {}) => data.facts.push({ id, slug: 'demo', type: 'project', body: `Fact ${id}.`, author: 'm@example.com',
    created_at: `2026-01-${String(id % 28 + 1).padStart(2, '0')}T00:00:00Z`, session_id: null, superseded_by: null, owner_subject: ME,
    shared: 1, sources: [], tags: ['battery'], ...more });
  const store = {
    caller: async () => ({ role: 'admin', subject: ME, email: 'm@example.com' }),
    stats: async () => {
      const live = data.facts.filter(row => row.superseded_by === null);
      const types = [...new Set(live.map(row => row.type))].sort().map(type => ({ type, n: live.filter(row => row.type === type).length }));
      return { types, totals: { facts: data.facts.length, live: live.length, sessions: data.sessions.size, private: 0 }, consolidations: [] };
    },
    // As D1 does, a query that binds more than 100 variables is refused.
    facts: async queries => queries.map(query => {
      if (query.ids.length > 100) throw new Error('D1_ERROR: too many SQL variables');
      return data.facts.filter(row => query.ids.includes(row.id));
    }),
    tags: async () => data.tags,
    session: async ({ id }) => data.sessions.get(id) ?? null,
    transcript: async ({ factId }) => {
      const row = data.facts.find(item => item.id === factId);
      return data.transcripts.get(row.session_id) ?? { missing: 'no transcript was stored for this session', session: row.session_id };
    },
  };
  for (const op of WRITES) store[op] = async () => { writes.push(op); throw new Error(`the source refuses ${op}`); };
  return { store, data, writes, fact };
}

/** The import route as design §10 gives it, over an in-memory space whose facts are keyed by `n`. */
function relaySpace() {
  const space = { facts: new Map(), imported: new Map(), sessions: new Map(), tags: new Map(), transcripts: new Map(), used: false, calls: [] };
  const highest = () => Math.max(0, ...space.facts.keys());
  const answers = {
    status: () => ({ imported: space.imported.size, used: space.used, highest: highest() }),
    start: () => ({ moved: 0 }),
    chunk: ({ subject, facts, sessions, tags }) => {
      let added = 0, skipped = 0;
      const renumbered = [];
      for (const fact of facts) {
        if (space.imported.has(fact.id)) { skipped += 1; continue; }
        const n = space.facts.has(fact.id) ? highest() + 1 : fact.id;
        if (n !== fact.id) renumbered.push({ old: fact.id, new: n });
        space.facts.set(n, { ...fact, n, owner: fact.owner_subject === subject ? 'ana' : fact.owner_subject, replacedBy: null });
        space.imported.set(fact.id, n);
        added += 1;
      }
      for (const row of sessions) if (!space.sessions.has(row.id)) space.sessions.set(row.id, row);
      for (const tag of tags) if (!space.tags.has(tag.name)) space.tags.set(tag.name, tag);
      return { added, skipped, renumbered };
    },
    finish: ({ links }) => {
      let linked = 0;
      for (const { id, by } of links) {
        if (!space.imported.has(by)) return null;
        const old = space.facts.get(space.imported.get(id));
        if (old.replacedBy !== null) continue;
        old.replacedBy = space.imported.get(by);
        linked += 1;
      }
      const counts = { live: {}, all: {} };
      const imported = new Set(space.imported.values());
      for (const n of imported) {
        const row = space.facts.get(n);
        counts.all[row.type] = (counts.all[row.type] ?? 0) + 1;
        // Live unless an imported fact replaced it: a fact the space wrote since is not in the source.
        if (!imported.has(row.replacedBy)) counts.live[row.type] = (counts.live[row.type] ?? 0) + 1;
      }
      return { linked, counts };
    },
  };
  const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
  const fetch = async (url, init) => {
    assert.equal(init.headers.Authorization, `Bearer ${COMPUTER.key}`);
    const { pathname, searchParams } = new URL(url);
    if (pathname === '/v1/memory/import/transcript') {
      const id = searchParams.get('session');
      space.calls.push(`transcript ${id}`);
      if (space.transcripts.has(id)) return json({ skipped: true });
      space.transcripts.set(id, new Uint8Array(await new Response(init.body).arrayBuffer()));
      return json({ key: `memory/transcripts/${id}` });
    }
    assert.equal(pathname, '/v1/memory/import');
    const body = JSON.parse(init.body);
    const kind = body.start ? 'start' : body.finish ? 'finish' : body.facts ? 'chunk' : 'status';
    space.calls.push(kind);
    const answer = answers[kind](body.finish ?? body);
    return answer ? json(answer) : json({ error: 'invalid_request', error_description: 'A link names a fact not imported.' }, 400);
  };
  return { space, fetch };
}

/** A source of 450 facts in three sessions, two replaced and one a thread, with two transcripts. */
function filledSource() {
  const source = sourceStore();
  for (let id = 1; id <= 450; id += 1) source.fact(id, { session_id: `claude:${'0'.repeat(7)}${id % 3}`, type: id === 7 ? 'thread' : 'project' });
  source.data.facts[2].superseded_by = 10;
  source.data.facts[4].superseded_by = 300;
  for (const n of [0, 1, 2]) source.data.sessions.set(`claude:${'0'.repeat(7)}${n}`, { id: `claude:${'0'.repeat(7)}${n}`, agent: 'claude', owner_subject: ME });
  source.data.transcripts.set(`claude:${'0'.repeat(7)}0`, new TextEncoder().encode('{"type":"user"}\n'));
  source.data.transcripts.set(`claude:${'0'.repeat(7)}1`, new TextEncoder().encode('{"type":"assistant"}\n'));
  return source;
}

test('every fact, session, tag and transcript arrives, nothing is written to the source, and the counts match', async () => {
  const source = filledSource();
  const { space, fetch } = relaySpace();
  const result = await run({ source: source.store, computer: COMPUTER, fetch, log: quiet });
  assert.equal(result.ok, true, result.differences.join('; '));
  assert.deepEqual([result.added, result.skipped, result.renumbered, result.linked], [450, 0, [], 2]);
  assert.deepEqual([...space.imported.keys()], Array.from({ length: 450 }, (_, at) => at + 1));
  assert.equal(space.facts.get(328).body, 'Fact 328.', 'a fact keeps its number');
  assert.deepEqual([space.facts.get(3).replacedBy, space.facts.get(5).replacedBy], [10, 300]);
  assert.deepEqual([space.sessions.size, [...space.tags.keys()]], [3, ['battery']]);
  assert.deepEqual(result.transcripts, { kept: 2, skipped: 0, missing: 1 });
  assert.equal(new TextDecoder().decode(space.transcripts.get(`claude:${'0'.repeat(7)}1`)), '{"type":"assistant"}\n');
  assert.deepEqual(space.calls.filter(call => !call.startsWith('transcript')), ['status', 'start', 'chunk', 'chunk', 'chunk', 'finish']);
  assert.deepEqual(source.writes, []);
});

test('facts on both sides of a 5,000-number gap all arrive', async () => {
  const source = sourceStore();
  for (let id = 1; id <= 100; id += 1) source.fact(id);
  for (let id = 5101; id <= 5200; id += 1) source.fact(id);
  const { space, fetch } = relaySpace();
  const result = await run({ source: source.store, computer: COMPUTER, fetch, log: quiet });
  assert.equal(result.ok, true, result.differences.join('; '));
  assert.equal(result.added, 200);
  assert.deepEqual([space.facts.has(100), space.facts.has(5101), space.facts.has(5200)], [true, true, true]);
});

test('a second run adds only the source\'s new facts, with a new number where memory took the old one, and links remapped', async () => {
  const source = filledSource();
  const { space, fetch } = relaySpace();
  await run({ source: source.store, computer: COMPUTER, fetch, log: quiet });
  // After the switch, memory saves #451 in the space, while the old store took #451 and #452 before it stopped.
  space.facts.set(451, { n: 451, type: 'project', body: 'Saved in the space.', replacedBy: null });
  space.used = true;
  source.fact(451, { type: 'feedback', body: 'New in the old store.' });
  source.fact(452, { body: 'Replaces fact 20.' });
  source.data.facts[450].superseded_by = 452;
  source.data.facts[19].superseded_by = 451;
  space.calls.length = 0;
  const result = await run({ source: source.store, computer: COMPUTER, fetch, log: quiet });
  assert.equal(result.ok, true, result.differences.join('; '));
  assert.deepEqual([result.added, result.skipped, result.renumbered, result.linked], [2, 450, [{ old: 451, new: 452 }, { old: 452, new: 453 }], 2]);
  assert.deepEqual([space.facts.get(451).body, space.facts.get(452).body], ['Saved in the space.', 'New in the old store.']);
  assert.equal(space.facts.get(452).replacedBy, 453, 'a link names both facts by their new numbers');
  assert.equal(space.facts.get(20).replacedBy, 452);
  assert.deepEqual([result.transcripts.kept, result.transcripts.skipped], [0, 2]);
  assert.ok(!space.calls.includes('start'), 'a later run sends no start');
  assert.deepEqual(source.writes, []);
});

test('a dry run reads and counts, and sends nothing', async () => {
  const source = filledSource();
  const lines = [];
  const result = await run({ source: source.store, dryRun: true, fetch: () => assert.fail('a dry run sends nothing'), log: line => lines.push(line) });
  assert.deepEqual([result.dryRun, result.read.facts.length, result.read.highest], [true, 450, 450]);
  assert.match(lines[0], /^Source: 450 facts \(448 live\), 3 sessions, 1 tags, highest #450\.$/);
});

test('counts that differ from the source fail the run, and a refused finish stops it with the server\'s words', async () => {
  const source = filledSource();
  const { space, fetch } = relaySpace();
  const dropping = async (url, init) => {
    const answer = await fetch(url, init);
    if (url.includes('/transcript') || !JSON.parse(init.body).finish) return answer;
    const body = await answer.json();
    body.counts.live.project -= 1;
    return Response.json(body);
  };
  const lines = [];
  const result = await run({ source: source.store, computer: COMPUTER, fetch: dropping, log: line => lines.push(line) });
  assert.equal(result.ok, false);
  assert.match(lines.at(-1), /^Counts differ from the source: live project: source 447, space 446\.$/);
  source.data.facts[5].superseded_by = 999;
  space.calls.length = 0;
  await assert.rejects(run({ source: source.store, computer: COMPUTER, fetch, log: quiet }), /HTTP 400\): A link names a fact not imported\./);
});

test('it reads a checkout\'s own memory with the profile it is given, and needs a connected computer to write', async () => {
  const root = mkdtempSync(join(tmpdir(), 'wong-import-'));
  const lib = join(root, '.agents', 'skills', 'memory', 'scripts', 'lib');
  mkdirSync(lib, { recursive: true });
  writeFileSync(join(lib, 'store.mjs'), `export const repoContext = root => ({ root });
export const openStore = async ctx => globalThis.importSource(ctx, process.env.WONG_MEMORY_PROFILE);\n`);
  const seen = [];
  globalThis.importSource = (ctx, profile) => { seen.push([ctx.root, profile]); return filledSource().store; };
  const home = process.env.RELAY_EVERYTHING_HOME;
  process.env.RELAY_EVERYTHING_HOME = join(root, 'no-relay-home');
  try {
    await assert.rejects(run({ from: root, profile: join(root, 'old-store.mjs'), log: quiet }), /not connected to Relay Everything/);
  } finally {
    if (home === undefined) delete process.env.RELAY_EVERYTHING_HOME; else process.env.RELAY_EVERYTHING_HOME = home;
    delete process.env.WONG_MEMORY_PROFILE;
  }
  assert.deepEqual(seen, [[root, join(root, 'old-store.mjs')]]);
  await assert.rejects(run({ from: join(root, 'missing'), log: quiet }), /holds no WongStack memory/);
});

test('a catch-up run\'s counts match when a fact saved in the space since the switch replaced an imported one', async () => {
  const source = filledSource();
  const { space, fetch } = relaySpace();
  await run({ source: source.store, computer: COMPUTER, fetch, log: quiet });
  // After the switch, memory saves #451 in the space and it replaces imported #40, which the old store still holds live.
  space.facts.set(451, { n: 451, type: 'project', body: 'Replaces fact 40.', replacedBy: null });
  space.facts.get(40).replacedBy = 451;
  space.used = true;
  const result = await run({ source: source.store, computer: COMPUTER, fetch, log: quiet });
  assert.equal(result.ok, true, result.differences.join('; '));
  assert.deepEqual([result.added, result.skipped, result.linked], [0, 450, 0]);
  assert.equal(space.facts.get(40).replacedBy, 451, 'the space keeps its own link');
});
