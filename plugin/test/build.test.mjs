import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, readFileSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { build, buildDue, CHATS_WAIT, claims, clientIdOf, FORMAT, MOST_CHATS, MOST_NOTES, readRecord, readSettings, run, status,
  USAGE, work } from '../bin/build.mjs';
import { sync } from '../bin/knowledge.mjs';
import { copyOf, writeComputer } from '../lib/config.mjs';
import { childEnv } from '../lib/headless.mjs';
import { computer, copy, page, relayHome, web } from './fake.mjs';

const ZONE = 'America/Toronto';
const NOW = Date.parse('2026-11-10T17:00:00Z');
const HOUR = 3_600_000;
/** A time in Toronto's clock with its offset, as the web API answers times. */
const local = at => `${new Date(at - 5 * HOUR).toISOString().slice(0, 19)}-05:00`;

/**
 * A web API that keeps chats, notes, facts and their topics as the real routes do, pages by an index cursor, and,
 * given a `remote`, answers the knowledge pass. `oldServer` refuses a chat list with no words, as before this change.
 */
function fakeWeb({ chats = [], notes = [], facts = [], noteTags = {}, remote, oldServer = false } = {}) {
  const calls = [];
  const within = (tag, topic) => tag === topic || tag.startsWith(`${topic}/`);
  const fetcher = async (url, init) => {
    const { pathname, searchParams } = new URL(url);
    const query = Object.fromEntries(searchParams);
    const body = init.body ? JSON.parse(init.body) : undefined;
    const path = pathname.replace(/^\/v1/, '');
    calls.push({ method: init.method, path, query, body });
    const answer = (json, status = 200) => new Response(JSON.stringify(json), { status, headers: { 'content-type': 'application/json' } });
    const pageOf = (items, key, limit) => {
      const start = Number(query.cursor ?? 0);
      return answer({ [key]: items.slice(start, start + limit), nextCursor: start + limit < items.length ? String(start + limit) : null });
    };
    if (path === '/knowledge/access') return answer({ remote, token: 'art_v1_made-up-pass', expiresAt: '2026-11-10T18:00:00.000Z' });
    if (path === '/chats') return oldServer && !query.q ? answer({ error: 'invalid_request', error_description: '`q`: Required' }, 400)
      : pageOf(chats, 'chats', Number(query.limit ?? 10));
    if (path.startsWith('/chats/')) return answer({ id: decodeURIComponent(path.slice(7)), messages: [], nextCursor: null });
    const tagged = /^\/notes\/([^/]+)\/tags$/.exec(path);
    if (tagged) {
      const id = decodeURIComponent(tagged[1]);
      noteTags[id] = [...new Set([...(noteTags[id] ?? []).filter(tag => !body.remove.includes(tag)), ...body.add])].sort();
      return answer({ id, tags: noteTags[id] });
    }
    // As the real route answers one note: with the places near it and its day's health.
    if (path.startsWith('/notes/')) {
      const one = notes.find(note => note.id === decodeURIComponent(path.slice(7)));
      return answer({ ...one, placesNearby: [{ id: 's1', name: 'Dentist on King St', lat: 43.61, lon: -79.31, start: one.recordedAt, end: one.recordedAt }],
        day: { day: one.recordedAt.slice(0, 10), steps: 8123, sleepMinutes: 431, heartRate: { min: 52, max: 141, average: 67 },
          workouts: { count: 1, minutes: 47 } } });
    }
    if (path === '/notes') {
      const found = query.tag ? notes.filter(note => (noteTags[note.id] ?? []).some(tag => within(tag, query.tag))) : notes;
      return pageOf(found, 'notes', Number(query.limit ?? 20));
    }
    if (path === '/memory' && init.method === 'POST') {
      const stored = body.facts.map(fact => {
        const held = facts.find(one => one.clientId === fact.clientId);
        if (held) return { clientId: fact.clientId, id: held.id, added: false };
        facts.push({ ...fact, id: `f${'abcdefgh'[facts.length % 8]}${facts.length}xy` });
        return { clientId: fact.clientId, id: facts.at(-1).id, added: true };
      });
      return answer({ facts: stored }, stored.some(fact => fact.added) ? 201 : 200);
    }
    if (path === '/memory') {
      const words = (query.q ?? '').toLowerCase().split(/\s+/).filter(Boolean);
      const found = facts.filter(fact => (!query.tag || fact.tags.some(tag => within(tag, query.tag)))
        && (!query.source || fact.sources.some(source => source === query.source || source.startsWith(`${query.source}#`)))
        && words.every(word => fact.fields.text.toLowerCase().includes(word)));
      return pageOf(found, 'facts', Number(query.limit ?? 20));
    }
    return answer({ error: 'not_found', error_description: 'No such route.' }, 404);
  };
  return { calls, fetcher, facts, noteTags };
}

const chat = (id, { quietHours = 2, messages = 5 } = {}) => ({ id, title: `Chat ${id}`, project: 'bike', app: 'claude-code',
  startedAt: local(NOW - (quietHours + 1) * HOUR), lastAt: local(NOW - quietHours * HOUR), messages, savedByAi: false });
const note = (id, hoursAgo = 3) => ({ id, title: `Note ${id}`, source: 'typed', text: `Note ${id} text`, recordedAt: local(NOW - hoursAgo * HOUR),
  device: 'Phone', audio: false, place: { lat: 43.65, lon: -79.38, accuracy: 8, name: 'Home', from: 'phone' }, attachments: [] });
/** What a note's place, the places near it and its day's health hold: none of it may reach the build. */
const HIDDEN = ['"place"', 'placesNearby', '"steps"', 'sleepMinutes', 'heartRate', '"workouts"', '43.65', '43.61', 'Dentist', 'Home', '8123'];
const hides = text => HIDDEN.filter(word => text.includes(word));
const fact = (id, tags, sources, text) => ({ id, clientId: `seed-${id}`, tags, sources, replaces: [], fields: { kind: 'fact', text } });

/** A connected Relay Everything folder with this read record in its copy of the web. */
function homeWith(read = '') {
  const env = relayHome();
  copy({ '.relay/read.log': read }, copyOf(env));
  return env;
}
const ask = (env, args, server, more = {}) => build(args, { env, fetcher: server.fetcher, zone: ZONE, ...more });
const listed = async (env, server) => (await work({ env, fetcher: server.fetcher, now: NOW, zone: ZONE })).json;

test('work lists a new chat from the start, a grown one from its last read, and leaves out a read chat and the one in progress', async () => {
  const env = homeWith('chat c-grown 4\nchat c-read 2\nchat c-grown 1\nnote n-read\n');
  const server = fakeWeb({ chats: [chat('c-live', { quietHours: 1 / 6 }), chat('c-new'), chat('c-grown', { messages: 10 }), chat('c-read', { messages: 3 })],
    notes: [note('n-new'), note('n-read')] });
  const got = await listed(env, server);
  assert.deepEqual(got.chats.map(({ id, after, messages, day }) => [id, after, messages, day]), [['c-new', -1, 5, '2026-11-10'], ['c-grown', 4, 10, '2026-11-10']]);
  assert.deepEqual(got.notes, [{ id: 'n-new', title: 'Note n-new', day: '2026-11-10' }]);
  assert.deepEqual(got.left, { chats: 0, notes: 0 });
  // Chats are listed with no words, and the place of a note never reaches the list.
  assert.ok(server.calls.filter(call => call.path === '/chats').every(call => call.query.q === undefined));
  assert.deepEqual(hides(JSON.stringify(got)), []);
});

test('work reads at most 20 chats and 100 notes, newest first, and counts what is left', async () => {
  const env = homeWith();
  const server = fakeWeb({ chats: Array.from({ length: 25 }, (_, at) => chat(`c${at}`, { quietHours: 2 + at })),
    notes: Array.from({ length: 130 }, (_, at) => note(`n${at}`, 2 + at)) });
  const got = await listed(env, server);
  assert.equal(got.chats.length, MOST_CHATS);
  assert.equal(got.notes.length, MOST_NOTES);
  assert.deepEqual([got.chats[0].id, got.chats.at(-1).id, got.notes[0].id], ['c0', 'c19', 'n0']);
  assert.deepEqual(got.left, { chats: 5, notes: 30 });
});

test('on an older server that needs words for chats, work lists the notes only and says why', async () => {
  const server = fakeWeb({ chats: [chat('c1')], notes: [note('n1')], oldServer: true });
  const got = await listed(homeWith(), server);
  assert.deepEqual([got.chats, got.notes.map(one => one.id), got.chatsWait], [[], ['n1'], CHATS_WAIT]);
});

test('the agent\'s commands read a chat from its seq, notes with no place, facts, and mark items read in the web', async () => {
  const env = homeWith();
  const server = fakeWeb({ notes: [note('n1'), note('n2')], noteTags: { n1: ['bike'] } });
  assert.equal((await ask(env, ['chat', 'c1', '--after', '4'], server)).code, 0);
  assert.equal((await ask(env, ['chat', 'c2', '--after', '-1'], server)).code, 0);
  assert.deepEqual(server.calls.map(call => [call.path, call.query.cursor]), [['/chats/c1', '4'], ['/chats/c2', undefined]]);
  const one = (await ask(env, ['note', 'n1'], server)).text;
  assert.deepEqual(JSON.parse(one), { id: 'n1', title: 'Note n1', source: 'typed', text: 'Note n1 text', recordedAt: note('n1').recordedAt,
    device: 'Phone', audio: false, attachments: [] });
  assert.deepEqual(hides(one), []);
  const two = (await ask(env, ['note', 'n1', 'n2'], server)).text;
  assert.deepEqual(JSON.parse(two).notes.map(read => read.id), ['n1', 'n2']);
  assert.deepEqual(hides(two), []);
  const found = (await ask(env, ['notes', '--tag', 'bike'], server)).text;
  assert.deepEqual(JSON.parse(found), { notes: [JSON.parse(one)], nextCursor: null });
  assert.deepEqual(hides(found), []);
  assert.equal((await ask(env, ['notes'], server)).code, 2);
  assert.equal((await ask(env, ['facts', '--tag', 'bike', '--from', '2026-01-01'], server)).code, 0);
  assert.deepEqual(server.calls.at(-1).query, { tag: 'bike', timezone: ZONE });
  assert.equal((await ask(env, ['tag', 'note', 'n2', '--add', 'bike-charger,travel'], server)).code, 0);
  assert.deepEqual(server.noteTags.n2, ['bike-charger', 'travel']);
  assert.deepEqual(await ask(env, ['done', 'chat', 'c1', '9'], server), { code: 0, text: 'Marked chat c1 read.' });
  assert.equal((await ask(env, ['done', 'note', 'n1'], server)).code, 0);
  assert.equal((await ask(env, ['done', 'chat', 'c1'], server)).code, 2);
  assert.equal(readFileSync(join(copyOf(env), '.relay', 'read.log'), 'utf8'), 'chat c1 9\nnote n1\n');
  const record = readRecord(copyOf(env));
  assert.deepEqual([record.chats.get('c1'), record.notes.has('n1')], [9, true]);
});

test('the build\'s command has no health, day, place, point, calendar or photo read', async () => {
  const server = fakeWeb();
  for (const command of ['day', 'health', 'nights', 'workouts', 'places', 'points', 'calendar', 'photos', 'around', 'topic', 'add-note', 'me']) {
    assert.deepEqual(await ask(homeWith(), [command, '2026-11-10'], server), { code: 2, text: USAGE }, command);
  }
  assert.deepEqual(server.calls, []);
});

test('add-facts gives each fact a clientId from its source and text, so a resend keeps one fact', async () => {
  const env = { ...homeWith(), RELAY_BUILD_RUN: '1' };
  const server = fakeWeb();
  const facts = [{ tags: ['bike-battery'], sources: ['relay:chat/c1#41'], replaces: ['fold1'], fields: { kind: 'decision', text: 'The battery is 500 Wh.' } }];
  const input = JSON.stringify(facts);
  assert.equal((await ask(env, ['add-facts'], server, { input })).code, 0);
  assert.equal((await ask(env, ['add-facts'], server, { input })).code, 0);
  assert.equal(server.facts.length, 1);
  assert.equal(server.facts[0].clientId, clientIdOf(facts[0]));
  assert.match(clientIdOf(facts[0]), /^[A-Za-z0-9-]{8,64}$/);
  assert.notEqual(clientIdOf(facts[0]), clientIdOf({ ...facts[0], sources: ['relay:chat/c1#42'] }));
  assert.equal((await ask(env, ['add-facts'], server, { input: 'no' })).code, 2);
});

test('check-facts shows the live facts that share a tag and those that share the longest words, at most 5 each', async () => {
  const facts = [fact('fa1', ['bike-battery'], ['relay:chat/c1#3'], 'The battery is 400 Wh.'),
    fact('fa2', ['travel'], ['relay:note/n1'], 'The battery lasted the whole ride.'),
    ...Array.from({ length: 7 }, (_, at) => fact(`fb${at}`, ['bike-battery'], ['relay:note/n2'], `Battery note ${at}.`))];
  const server = fakeWeb({ facts });
  const input = JSON.stringify([{ tags: ['bike-battery'], sources: ['relay:chat/c2#9'], fields: { kind: 'decision', text: 'The battery is 500 Wh, not 400.' } }]);
  const [shown] = JSON.parse((await ask(homeWith(), ['check-facts'], server, { input })).text);
  assert.equal(shown.byTag.length, 5);
  assert.deepEqual(shown.byTag[0], { id: 'fa1', kind: 'fact', text: 'The battery is 400 Wh.', tags: ['bike-battery'] });
  assert.deepEqual(shown.byWords.map(one => one.id).slice(0, 2), ['fa1', 'fa2']);
  assert.ok(server.calls.every(call => call.method === 'GET' && Number(call.query.limit) === 5));
});

test('add-facts and check-facts take the list as their one argument, as the narrow grant allows, and stdin still works', async () => {
  const env = { ...homeWith(), RELAY_BUILD_RUN: '1' };
  const server = fakeWeb();
  const facts = [{ tags: ['bike-charger'], sources: ['relay:note/n1'], fields: { kind: 'plan', text: 'Order Sam’s 2 m XT60 cable.' } }];
  const [shown] = JSON.parse((await ask(env, ['check-facts', JSON.stringify(facts)], server)).text);
  assert.equal(shown.text, 'Order Sam’s 2 m XT60 cable.');
  assert.equal((await ask(env, ['add-facts', JSON.stringify(facts)], server)).code, 0);
  assert.equal((await ask(env, ['add-facts'], server, { input: JSON.stringify(facts) })).code, 0);
  assert.deepEqual(server.facts.map(one => one.clientId), [clientIdOf(facts[0])]);
  assert.equal((await ask(env, ['add-facts', 'no'], server, { input: JSON.stringify(facts) })).code, 2);
});

test('the command line with the list as an argument answers without waiting for stdin', async () => {
  const child = spawn(process.execPath, [fileURLToPath(new URL('../bin/build.mjs', import.meta.url)), 'check-facts', '[]'],
    { env: { ...process.env, ...relayHome({ connected: false }) }, stdio: ['pipe', 'pipe', 'ignore'] });
  let out = '';
  child.stdout.on('data', part => { out += part; });
  // stdin stays open: an old build would wait on it for ever.
  const code = await Promise.race([new Promise(done => child.on('exit', done)), new Promise(done => setTimeout(() => done('waited'), 5000))]);
  child.kill();
  assert.equal(code, 1);
  assert.match(out, /not connected/);
});

test('related ranks the topics that share a fact, a chat or a note, says when a page links one, and finds none for a lone topic', async () => {
  const facts = [fact('fa1', ['bike-battery', 'bike-charger'], ['relay:chat/c1#3'], 'The battery charges on the dock.'),
    fact('fa2', ['bike-battery'], ['relay:chat/c1#5'], 'The battery is 500 Wh.'),
    fact('fa3', ['travel'], ['relay:chat/c1#8'], 'The trip to Ottawa is in May.'),
    fact('fa4', ['garden'], ['relay:note/n9'], 'The garden needs a fence.'),
    // A day is shared by everything on it, so a shared day makes no link.
    fact('fa5', ['bike-battery'], ['relay:day/2026-11-09'], 'The battery was charged on Monday.'),
    fact('fa6', ['weather'], ['relay:day/2026-11-09'], 'It rained on Monday.')];
  const server = fakeWeb({ facts, notes: [note('n1')], noteTags: { n1: ['bike-battery', 'sam'] } });
  const env = homeWith();
  copy({ 'topics/bike-battery.md': page('Bike battery', 'Size', 'It charges on the [dock](bike-charger.md).'),
    'topics/bike-charger.md': page('Bike charger', 'The dock'), 'topics/travel.md': page('Travel', 'Trips') }, copyOf(env));
  const { topic, related } = JSON.parse((await ask(env, ['related', 'bike-battery'], server)).text);
  assert.equal(topic, 'bike-battery');
  assert.deepEqual(related, [
    { topic: 'bike-charger', facts: 1, sources: 0, notes: 0, sample: 'The battery charges on the dock.', page: true, linked: 'this page links it' },
    { topic: 'sam', facts: 0, sources: 0, notes: 1, sample: null, page: false, linked: null },
    { topic: 'travel', facts: 0, sources: 1, notes: 0, sample: 'The trip to Ottawa is in May.', page: true, linked: null }]);
  assert.ok(!server.calls.some(call => call.query.source?.startsWith('relay:day/')));
  // A note's topics are read by a change of nothing.
  assert.deepEqual(server.calls.find(call => call.method === 'POST').body, { add: [], remove: [] });
  assert.deepEqual(server.noteTags.n1, ['bike-battery', 'sam']);
  assert.deepEqual(JSON.parse((await ask(env, ['related', 'garden'], server)).text).related, []);
});

/** A connected computer with its own name, whose copy syncs with `remote`. */
function computerHome(name) {
  const env = relayHome({ connected: false });
  writeComputer(env, { ...computer(), name });
  return env;
}
const git = (args, cwd) => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();

test('a run claims the day, starts the agent on the work list, appends the done line, and a second computer stops', async () => {
  const remote = web();
  const server = fakeWeb({ remote, chats: [chat('c1')], notes: [note('n1'), note('n2')] });
  const laptop = computerHome('Laptop');
  const started = [];
  const agent = async ([command, args], { cwd, env }) => {
    started.push({ command, cwd, env, prompt: args[1] });
    const facts = [{ tags: ['garden'], sources: ['relay:note/n1'], fields: { kind: 'plan', text: 'Plant garlic in October.' } },
      { tags: ['bike-battery'], sources: ['relay:chat/c1#4'], replaces: ['fold1'], fields: { kind: 'decision', text: 'The battery is 500 Wh.' } }];
    await build(['add-facts'], { env, fetcher: server.fetcher, zone: ZONE, input: JSON.stringify(facts) });
    await build(['tag', 'note', 'n1', '--add', 'garden'], { env, fetcher: server.fetcher, zone: ZONE });
    await build(['done', 'chat', 'c1', '4'], { env });
    await build(['done', 'note', 'n1'], { env });
    return { code: 0 };
  };
  const said = await run({ env: laptop, fetcher: server.fetcher, now: () => NOW, zone: ZONE, agent });
  assert.deepEqual(said, { code: 0, text: 'Built: 1 chats and 1 notes read, 2 facts added.' });
  assert.equal(started.length, 1);
  assert.equal(started[0].command, 'claude');
  assert.equal(started[0].cwd, copyOf(laptop));
  assert.deepEqual([started[0].env.RELAY_SAVE, started[0].env.RELAY_BUILD_RUN], ['0', '1']);
  assert.match(started[0].prompt, /build\.mjs work/);
  const log = git(['show', 'main:.relay/builds.log'], remote).split('\n');
  assert.match(log[0], /^2026-11-10 2026-11-10T17:00:00\.000Z Laptop [\w-]{8}$/);
  assert.equal(log[1], '2026-11-10 done facts=2 replaced=1 notes=1 chats=1 new=bike-battery,garden');
  assert.equal(git(['show', 'main:.relay/read.log'], remote), 'chat c1 4\nnote n1');
  assert.deepEqual(readSettings(laptop).left, { chats: 0, notes: 1 });
  assert.equal(readSettings(laptop).tried, '2026-11-10');
  assert.equal(buildDue(laptop, NOW, ZONE), false);
  // The desktop finds the day claimed after its sync, and stops before it reads anything.
  const desktop = computerHome('Desktop');
  const before = server.calls.length;
  const second = await run({ env: desktop, fetcher: server.fetcher, now: () => NOW + HOUR, zone: ZONE, agent });
  assert.deepEqual(second, { code: 0, text: 'Laptop builds your web today.' });
  assert.equal(started.length, 1);
  assert.ok(server.calls.slice(before).every(call => call.path === '/knowledge/access'));
  // Status reads the build from the copy and this computer's file alone.
  const shown = status({ env: laptop, zone: ZONE }).text.split('\n');
  assert.deepEqual(shown, ['The daily build is on for this computer: it starts with the first chat of each day.', 'Last build: 2026-11-10 12:00, on Laptop',
    '  1 chats, 1 notes read', '  2 facts added, 1 replaced', '  2 new topics: bike-battery, garden', 'Still to read: 0 chats, 1 notes']);
});

test('a claim that loses to an earlier one from another computer, joined in by the sync, stops before any read', async () => {
  const remote = web();
  const server = fakeWeb({ remote, chats: [chat('c1')], notes: [note('n1')] });
  const [laptop, desktop] = [computerHome('Laptop'), computerHome('Desktop')];
  await sync({ env: desktop, fetcher: server.fetcher, now: true });
  let syncs = 0;
  // Between the laptop's claim and its second sync, the desktop sends a claim made a minute before it.
  const syncWeb = async options => {
    if (syncs++ === 1) {
      copy({ '.relay/builds.log': '2026-11-10 2026-11-10T16:59:00.000Z Desktop d-esk001\n' }, copyOf(desktop));
      await sync({ env: desktop, fetcher: server.fetcher, now: true });
    }
    return sync(options);
  };
  const started = [];
  const said = await run({ env: laptop, fetcher: server.fetcher, now: () => NOW, zone: ZONE, syncWeb, agent: async () => started.push(1) });
  assert.deepEqual(said, { code: 0, text: 'Desktop builds your web today.' });
  assert.deepEqual(started, []);
  assert.ok(!server.calls.some(call => call.path === '/chats' || call.path === '/notes'));
  // The union join keeps both lines in the laptop's copy, earliest first.
  const lines = claims(copyOf(laptop), '2026-11-10');
  assert.deepEqual(lines.map(claim => claim.name), ['Desktop', 'Laptop']);
});

test('status, off, on and now: kept in build.json on this computer, with no network call', async () => {
  const env = homeWith();
  const offline = async () => { throw new Error('No call.'); };
  assert.equal((await build(['status'], { env, fetcher: offline })).text,
    'The daily build is on for this computer: it starts with the first chat of each day.\nNo build has run yet.');
  assert.match((await build(['off'], { env, fetcher: offline })).text, /^The daily build is off on this computer\./);
  assert.equal(readSettings(env).off, true);
  assert.equal(buildDue(env, NOW, ZONE), false);
  assert.match((await build(['on'], { env, fetcher: offline })).text, /^The daily build is on/);
  assert.equal(buildDue(env, NOW, ZONE), true);
  const started = [];
  const now = await build(['now'], { env: { ...env, CODEX_THREAD_ID: 't1' }, fetcher: offline, start: (_, app) => started.push(app) });
  assert.equal(now.code, 0);
  assert.deepEqual(started, ['codex']);
  assert.equal((await build(['now'], { env: relayHome({ connected: false }), start: () => started.push('no') })).code, 1);
  assert.equal(started.length, 1);
});

test('remove-page removes one page in topics/ of the copy, and refuses any other path', async () => {
  const env = homeWith();
  const dir = copyOf(env);
  copy({ 'topics/bikebattery.md': page('Bike battery', 'Size'), 'topics/bike/charging.md': page('Charging', 'The dock'), 'topics/notes.txt': 'A list.\n',
    'README.md': '# Topics\n', 'FORMAT.md': '# The rules\n' }, dir);
  const outside = copy({ 'secret.md': '# Not a topic\n' });
  symlinkSync(outside, join(dir, 'topics', 'away'));
  symlinkSync(join(outside, 'secret.md'), join(dir, 'topics', 'link.md'));
  const server = fakeWeb();
  assert.deepEqual(await ask(env, ['remove-page', 'topics/bikebattery.md'], server), { code: 0, text: 'Removed topics/bikebattery.md.' });
  assert.equal(existsSync(join(dir, 'topics', 'bikebattery.md')), false);
  assert.equal((await ask(env, ['remove-page', 'topics/bike/charging.md'], server)).code, 0);
  assert.equal(existsSync(join(dir, 'topics', 'bike', 'charging.md')), false);
  for (const path of ['README.md', 'FORMAT.md', '.relay/read.log', 'topics/notes.txt', 'topics/../README.md', '../secret.md', `${tmpdir()}/x.md`,
    'topics/./x.md', 'topics\\x.md', 'topics/', 'topics/bike', 'topics/x.md/', null]) {
    assert.equal((await ask(env, ['remove-page', ...path === null ? [] : [path]], server)).code, 2, String(path));
  }
  assert.deepEqual(await ask(env, ['remove-page', 'topics/away/secret.md'], server), { code: 2, text: 'topics/away/secret.md is not in topics/.' });
  assert.equal((await ask(env, ['remove-page', 'topics/link.md'], server)).code, 1);
  assert.equal((await ask(env, ['remove-page', 'topics/gone.md'], server)).code, 1);
  for (const kept of ['README.md', 'FORMAT.md', 'topics/notes.txt']) assert.ok(existsSync(join(dir, kept)), kept);
  assert.ok(existsSync(join(outside, 'secret.md')));
  assert.deepEqual(server.calls, []);
});

test('a topic on notes only is new on the first run that uses it, and not on the next', async () => {
  const remote = web();
  const server = fakeWeb({ remote, notes: [note('n1'), note('n2', 30)] });
  const env = computerHome('Laptop');
  const agent = id => async (_, { env: child }) => {
    await build(['tag', 'note', id, '--add', 'garden'], { env: child, fetcher: server.fetcher, zone: ZONE });
    await build(['done', 'note', id], { env: child });
    return { code: 0 };
  };
  await run({ env, fetcher: server.fetcher, now: () => NOW, zone: ZONE, agent: agent('n1') });
  await run({ env, fetcher: server.fetcher, now: () => NOW + 24 * HOUR, zone: ZONE, agent: agent('n2') });
  const done = git(['show', 'main:.relay/builds.log'], remote).split('\n').filter(line => line.includes(' done '));
  assert.deepEqual(done, ['2026-11-10 done facts=0 replaced=0 notes=1 chats=0 new=garden', '2026-11-11 done facts=0 replaced=0 notes=1 chats=0 new=']);
});

test('a run gives a web that still has the old default FORMAT.md the new default, and keeps one the person changed', async () => {
  const old = readFileSync(new URL('format-before.md', import.meta.url), 'utf8');
  for (const [format, after] of [[old, readFileSync(FORMAT, 'utf8')], ['# My own rules\n', '# My own rules\n'], [`${old}\nMy own line.\n`, `${old}\nMy own line.\n`]]) {
    const remote = web({ format });
    const server = fakeWeb({ remote });
    assert.equal((await run({ env: computerHome('Laptop'), fetcher: server.fetcher, now: () => NOW, zone: ZONE, agent: async () => ({ code: 0 }) })).code, 0);
    assert.equal(git(['show', 'main:FORMAT.md'], remote), after.trim());
  }
});
