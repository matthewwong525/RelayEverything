import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { CHAT_KEY, dayIn, NOT_CONNECTED, parseArgs, relay, shiftTime } from '../bin/relay.mjs';
import { copyOf, writeComputer } from '../lib/config.mjs';
import { reason } from '../lib/server.mjs';
import { API, computer, copy, page, project, relayHome, SECRET, SERVER } from './fake.mjs';

const RELAY = fileURLToPath(new URL('../bin/relay.mjs', import.meta.url));

/** A web API that answers each call with `{ path, query }`, or with the status and the refusal it is told to, in the
 *  web API's own shape. */
function fakeApi(status = 200, why = 'A made-up refusal.') {
  const calls = [];
  const fetcher = async (url, init) => {
    const { pathname, searchParams } = new URL(url);
    calls.push({ method: init.method, path: pathname, query: Object.fromEntries(searchParams), auth: init.headers.Authorization,
      body: init.body ? JSON.parse(init.body) : undefined });
    const json = status < 300 ? { path: pathname } : { error: 'forbidden', error_description: why };
    return new Response(JSON.stringify(json), { status, headers: { 'content-type': 'application/json' } });
  };
  return { calls, fetcher };
}

const ask = (args, more = {}) => relay(args, { env: relayHome(), zone: 'Europe/London', ...more });

test('each command calls its own route with its query, the key and the time zone', async () => {
  const cases = [
    [['me'], '/v1/me', {}],
    [['notes', '--q', 'battery size'], '/v1/notes', { q: 'battery size', timezone: 'Europe/London' }],
    [['notes', '--from', '2026-11-03', '--to', '2026-11-04', '--cursor', 'abc', '--limit', '5'], '/v1/notes',
      { from: '2026-11-03', to: '2026-11-04', cursor: 'abc', limit: '5', timezone: 'Europe/London' }],
    [['note', 'note one'], '/v1/notes/note%20one', { timezone: 'Europe/London' }],
    [['day', '2026-11-03', '--timezone', 'Asia/Tokyo'], '/v1/days/2026-11-03', { timezone: 'Asia/Tokyo' }],
    [['health', 'steps', '--from', '2026-11-01', '--to', '2026-11-08', '--per', 'hour'], '/v1/health',
      { type: 'steps', from: '2026-11-01', to: '2026-11-08', bucket: 'hour', timezone: 'Europe/London' }],
    [['nights', '--from', '2026-11-01', '--to', '2026-11-08', '--stages'], '/v1/nights',
      { from: '2026-11-01', to: '2026-11-08', stages: 'true', timezone: 'Europe/London' }],
    [['workouts', '--from=2026-11-01', '--to=2026-11-08'], '/v1/workouts', { from: '2026-11-01', to: '2026-11-08', timezone: 'Europe/London' }],
    [['places', '--from', '2026-11-01', '--to', '2026-11-02'], '/v1/places', { from: '2026-11-01', to: '2026-11-02', timezone: 'Europe/London' }],
    [['points', '42'], '/v1/points', { id: '42', timezone: 'Europe/London' }],
    [['points', '--from', '2026-11-04T08:00', '--to', '2026-11-04T09:00'], '/v1/points',
      { from: '2026-11-04T08:00', to: '2026-11-04T09:00', timezone: 'Europe/London' }],
    [['calendar', '--from', '2026-11-01', '--to', '2026-11-02', '--query', 'dentist'], '/v1/calendar',
      { from: '2026-11-01', to: '2026-11-02', q: 'dentist', timezone: 'Europe/London' }],
    [['chats', '--q', 'stiffener'], '/v1/chats', { q: 'stiffener', timezone: 'Europe/London' }],
    [['chat', 'chat-1', '--cursor', '200'], '/v1/chats/chat-1', { cursor: '200', timezone: 'Europe/London' }],
    [['notes', '--tag', 'ring/charging'], '/v1/notes', { tag: 'ring/charging', timezone: 'Europe/London' }],
    [['facts', '--tag', 'battery', '--kind', 'decision', '--all'], '/v1/memory',
      { tag: 'battery', kind: 'decision', all: 'true', timezone: 'Europe/London' }],
    [['facts', '--source', 'relay:chat/7f3a'], '/v1/memory', { source: 'relay:chat/7f3a', timezone: 'Europe/London' }],
    [['fact', 'fc5kk'], '/v1/memory/fc5kk', { timezone: 'Europe/London' }],
    [['columns', '--changes'], '/v1/memory/columns', { changes: 'true' }],
  ];
  for (const [args, path, query] of cases) {
    const api = fakeApi();
    const done = await ask(args, { fetcher: api.fetcher });
    assert.deepEqual(done, { code: 0, text: JSON.stringify({ path }) }, args.join(' '));
    assert.deepEqual(api.calls, [{ method: 'GET', path, query, auth: `Bearer ${SECRET}`, body: undefined }], args.join(' '));
  }
});

test('add-note posts the words from stdin once, with a new clientId, and sends it again with the same id after a lost answer', async () => {
  const api = fakeApi(201);
  const done = await ask(['add-note', '--at', '2026-11-04T09:00'], { input: '  Buy 0.2 mm steel.\n', fetcher: api.fetcher });
  assert.equal(done.code, 0);
  const [call] = api.calls;
  assert.deepEqual([call.method, call.path], ['POST', '/v1/notes']);
  assert.deepEqual({ ...call.body, clientId: 'x' }, { clientId: 'x', text: 'Buy 0.2 mm steel.', createdAt: '2026-11-04T09:00', timezone: 'Europe/London' });
  assert.match(call.body.clientId, /^[A-Za-z0-9-]{8,64}$/);
  let tries = 0;
  const ids = [];
  const flaky = async (url, init) => {
    ids.push(JSON.parse(init.body).clientId);
    if (tries++ === 0) throw new TypeError('fetch failed');
    return api.fetcher(url, init);
  };
  assert.equal((await ask(['add-note'], { input: 'Again', fetcher: flaky })).code, 0);
  assert.equal(ids.length, 2);
  assert.equal(ids[0], ids[1]);
  assert.deepEqual(await ask(['add-note'], { input: ' ', fetcher: api.fetcher }), { code: 2, text: 'Give the note on stdin.' });
});

test('add-facts posts the JSON list from stdin, gives each fact a clientId it lacks, and sends the same ids after a lost answer', async () => {
  const api = fakeApi(201);
  const fact = { tags: ['battery'], sources: ['relay:chat/7f3a#120'], fields: { kind: 'decision', text: 'The battery is 50 mAh.' } };
  assert.equal((await ask(['add-facts'], { input: JSON.stringify([fact, { ...fact, clientId: 'mine-0001' }]), fetcher: api.fetcher })).code, 0);
  const [call] = api.calls;
  assert.deepEqual([call.method, call.path, call.query], ['POST', '/v1/memory', {}]);
  assert.match(call.body.facts[0].clientId, /^[A-Za-z0-9-]{8,64}$/);
  assert.deepEqual(call.body.facts.map(({ clientId, ...rest }) => rest), [fact, fact]);
  assert.equal(call.body.facts[1].clientId, 'mine-0001');
  const bodies = [];
  let tries = 0;
  const flaky = async (url, init) => {
    bodies.push(init.body);
    if (tries++ === 0) throw new TypeError('fetch failed');
    return api.fetcher(url, init);
  };
  assert.equal((await ask(['add-facts'], { input: JSON.stringify({ facts: [fact] }), fetcher: flaky })).code, 0);
  assert.equal(bodies.length, 2);
  assert.equal(bodies[0], bodies[1]);
  for (const input of ['', 'not json', '{}', '[1]']) {
    assert.deepEqual(await ask(['add-facts'], { input, fetcher: api.fetcher }), { code: 2, text: 'Give the facts as a JSON list on stdin.' });
  }
});

test('change-columns posts the change from stdin once, and tag adds and removes a fact\'s or a note\'s topics', async () => {
  const api = fakeApi();
  const change = { add: [{ name: 'mah', type: 'number', note: 'The battery size.' }], remove: ['due'] };
  assert.equal((await ask(['change-columns'], { input: JSON.stringify(change), fetcher: api.fetcher })).code, 0);
  assert.equal((await ask(['tag', 'fact', 'fc5kk', '--add', 'ring/charging, battery', '--remove', 'ring'], { fetcher: api.fetcher })).code, 0);
  assert.equal((await ask(['tag', 'note', 'note one', '--add', 'ring'], { fetcher: api.fetcher })).code, 0);
  assert.deepEqual(api.calls.map(({ method, path, query, body }) => [method, path, query, body]), [
    ['POST', '/v1/memory/columns', {}, change],
    ['POST', '/v1/memory/fc5kk/tags', {}, { add: ['ring/charging', 'battery'], remove: ['ring'] }],
    ['POST', '/v1/notes/note%20one/tags', {}, { add: ['ring'], remove: [] }],
  ]);
  const down = async () => { throw new TypeError('fetch failed'); };
  assert.equal((await ask(['change-columns'], { input: '{}', fetcher: async (...call) => { api.calls.push(call); return down(); } })).code, 1);
  assert.equal(api.calls.length, 4);
  assert.equal((await ask(['change-columns'], { input: 'nope', fetcher: api.fetcher })).text, 'Give the change as a JSON object on stdin.');
  for (const args of [['tag'], ['tag', 'fc5kk'], ['tag', 'page', 'x'], ['tag', 'fact']]) assert.equal((await ask(args, { fetcher: api.fetcher })).code, 2, args.join(' '));
  assert.equal(api.calls.length, 4);
});

test('db sends one command with its values, a file\'s commands as one batch, and lists the tables with a GET', async () => {
  const api = fakeApi();
  const file = join(mkdtempSync(join(tmpdir(), 'relay-db-')), 'plan.sql');
  writeFileSync(file, 'CREATE TABLE plans (name TEXT);\nINSERT INTO plans VALUES (\'a;b\');\n\nSELECT * FROM plans;\n');
  assert.equal((await ask(['db', 'SELECT * FROM plans WHERE name = ?', '--params', '["ring"]'], { fetcher: api.fetcher })).code, 0);
  assert.equal((await ask(['db', '--file', file], { fetcher: api.fetcher })).code, 0);
  assert.equal((await ask(['db', 'tables'], { fetcher: api.fetcher })).code, 0);
  assert.deepEqual(api.calls.map(({ method, path, query, body }) => [method, path, query, body]), [
    ['POST', '/v1/db', {}, { sql: 'SELECT * FROM plans WHERE name = ?', params: ['ring'] }],
    ['POST', '/v1/db', {}, { batch: [{ sql: 'CREATE TABLE plans (name TEXT)' }, { sql: "INSERT INTO plans VALUES ('a;b')" }, { sql: 'SELECT * FROM plans' }] }],
    ['GET', '/v1/db/tables', {}, undefined],
  ]);
  assert.equal((await ask(['db'], { fetcher: api.fetcher })).code, 2);
  assert.equal((await ask(['db', 'SELECT ?', '--params', 'ring'], { fetcher: api.fetcher })).code, 2);
  assert.equal((await ask(['db', '--file', `${file}.gone`], { fetcher: api.fetcher })).code, 2);
  assert.equal(api.calls.length, 3);
});

test('an old chat key is told to connect again, a turned-off key shows the server\'s reason, and other refusals say why', async () => {
  // The server's own words, from apiKeyCaller in app/worker/apps/relay/caller.ts, and an older server's command.
  const caller = readFileSync(fileURLToPath(new URL('../../app/worker/apps/relay/caller.ts', import.meta.url)), 'utf8');
  const [, server] = /refused\(403, "(This computer's key only saves chats\.[^"]*)"\)/.exec(caller) ?? [];
  assert.ok(server, 'caller.ts refuses a chat key');
  for (const words of [server, "This computer's key only saves chats. Type /relay:connect to connect it again."]) {
    assert.deepEqual(await ask(['notes', '--q', 'x'], { fetcher: fakeApi(403, words).fetcher }), { code: 1, text: CHAT_KEY }, words);
  }
  assert.equal(CHAT_KEY, "This computer's key only saves chats. Type /relay-connect to connect it again.");
  assert.deepEqual(await ask(['me'], { fetcher: fakeApi(403, 'This device key is turned off.').fetcher }), { code: 1,
    text: "Relay Everything refused this computer's key: This device key is turned off. Type /relay-connect to connect again." });
  assert.match((await ask(['me'], { fetcher: fakeApi(401, 'This key is not one Relay Everything makes.').fetcher })).text,
    /^Relay Everything refused this computer's key: This key is not one Relay Everything makes\. Type \/relay-connect/);
  assert.equal((await ask(['notes'], { fetcher: fakeApi(400).fetcher })).text, 'Relay Everything refused the request: A made-up refusal.');
  const bare = async () => new Response('Bad gateway', { status: 502 });
  assert.equal((await ask(['notes'], { fetcher: bare })).text, 'Relay Everything refused the request: It answered 502.');
  const down = async () => { throw new TypeError('fetch failed'); };
  assert.match((await ask(['me'], { fetcher: down })).text, /could not be reached\. Try again in a minute\.$/);
  // In a sandbox, the name lookup fails, and the line names the sandbox.
  const sandbox = async () => { throw Object.assign(new TypeError('fetch failed'), { cause: { code: 'EAI_AGAIN' } }); };
  assert.match((await ask(['me'], { fetcher: sandbox })).text, /could not be reached\. Try again in a minute\. If this runs in a sandbox/);
});

test('reason reads the web API\'s refusal and the app routes\' refusal', () => {
  assert.equal(reason({ error: 'forbidden', error_description: 'This device key is turned off.' }), 'This device key is turned off.');
  assert.equal(reason({ error: { code: 'forbidden', message: 'A chat key can only send chats.' } }), 'A chat key can only send chats.');
  for (const json of [null, {}, { error: 'forbidden' }, { error_description: '' }, { error: { message: 7 } }]) assert.equal(reason(json), null);
});

test('says what to do with no key, no command, or no value', async () => {
  const api = fakeApi();
  assert.deepEqual(await relay(['me'], { env: relayHome({ connected: false }), fetcher: api.fetcher }), { code: 1, text: NOT_CONNECTED });
  assert.match((await ask(['photos'])).text, /^Commands: me, notes/);
  assert.match((await ask([])).text, /^Commands:/);
  for (const name of ['points <id>', 'around <note id> or --at <time>', 'topic <name>']) assert.ok((await ask([])).text.includes(name), name);
  assert.equal((await ask(['topic'])).code, 2);
  assert.equal((await ask(['around'])).code, 2);
  assert.equal((await ask(['note'])).code, 2);
  assert.equal((await ask(['health'])).code, 2);
  assert.equal(api.calls.length, 0);
  assert.deepEqual(parseArgs(['notes', '--q', '--from', 'x']), { command: 'notes', value: undefined, second: undefined, fields: { q: 'true', from: 'x' } });
});

test('runs as the skill runs it, against a local server, and reads the note from stdin', async () => {
  const calls = [];
  const server = createServer((request, response) => {
    let body = '';
    request.on('data', part => { body += part; });
    request.on('end', () => {
      calls.push({ url: request.url, auth: request.headers.authorization, body });
      response.writeHead(request.method === 'POST' ? 201 : 200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ added: true }));
    });
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const env = relayHome({ connected: false });
  writeComputer(env, { ...computer(), api: `http://127.0.0.1:${server.address().port}/v1` });
  try {
    const { stdout: printed } = await promisify(execFile)(process.execPath, [RELAY, 'notes', '--q', 'steel'], { env: { ...process.env, ...env, TZ: 'Asia/Tokyo' } });
    assert.equal(printed, '{"added":true}\n');
    const usage = await promisify(execFile)(process.execPath, [RELAY], { env: { ...process.env, ...env } }).catch(error => error);
    assert.equal(usage.code, 2);
    assert.match(usage.stdout, /^Commands: .*points <id>.*around <note id>.*topic <name>/);
    const child = spawn(process.execPath, [RELAY, 'add-note'], { env: { ...process.env, ...env }, stdio: ['pipe', 'pipe', 'inherit'] });
    child.stdin.end('A note from stdin');
    assert.equal((await once(child, 'exit'))[0], 0);
    assert.deepEqual(calls.map(call => [call.url.split('?')[0], call.auth]), [['/v1/notes', `Bearer ${SECRET}`], ['/v1/notes', `Bearer ${SECRET}`]]);
    assert.match(calls[0].url, /timezone=Asia%2FTokyo/);
    assert.equal(JSON.parse(calls[1].body).text, 'A note from stdin');
  } finally {
    server.close();
  }
  assert.ok(API.endsWith('/v1'));
});

/** A web API that answers each route from `routes`, by its path after /v1, with `{ status, json }`; 404 for others. */
function routedApi(routes) {
  const calls = [];
  const fetcher = async (url, init) => {
    const { pathname, searchParams } = new URL(url);
    const query = Object.fromEntries(searchParams);
    calls.push({ method: init.method, path: pathname, query });
    const route = pathname.replace(/^\/v1/, '');
    const key = Object.keys(routes).find(name => name === `${route} ${query.type ?? ''}`.trim() || name === route);
    const { status = 200, json } = key ? routes[key](query) : { status: 404, json: { error: 'not_found', error_description: 'No such thing.' } };
    if (status === 'down') throw new TypeError('fetch failed');
    return new Response(JSON.stringify(json), { status, headers: { 'content-type': 'application/json' } });
  };
  return { calls, fetcher };
}

const AROUND = {
  '/notes/n1': () => ({ json: { id: 'n1', text: 'The battery stays 40 mAh.', recordedAt: '2026-11-04T14:20:00-05:00' } }),
  '/days/2026-11-04': () => ({ json: { day: '2026-11-04', steps: 6100 } }),
  '/notes': query => ({ json: { notes: [{ id: 'n0', from: query.from }], nextCursor: null } }),
  '/places': () => ({ json: { visits: [{ id: 7, place: 'Workshop' }], trips: [], next: null } }),
  '/calendar': () => ({ json: { events: [{ title: 'Ring sync' }], nextCursor: null } }),
  '/health steps': () => ({ json: { type: 'steps', bucket: 'hour', values: [{ value: 900 }] } }),
  '/health heart_rate': () => ({ json: { type: 'heart_rate', bucket: 'hour', values: [{ value: 71 }] } }),
};

test('around a note reads the note, then its day, notes, places, calendar and hourly health from 2 hours before to 2 after', async () => {
  const api = routedApi(AROUND);
  const done = await ask(['around', 'n1', '--timezone', 'America/Toronto'], { fetcher: api.fetcher });
  assert.equal(done.code, 0);
  const answer = JSON.parse(done.text);
  assert.deepEqual({ ...answer, note: answer.note.id }, {
    at: '2026-11-04T14:20:00-05:00', from: '2026-11-04T12:20:00-05:00', to: '2026-11-04T16:20:00-05:00', timezone: 'America/Toronto',
    hours: 2, note: 'n1', day: { day: '2026-11-04', steps: 6100 },
    notes: { notes: [{ id: 'n0', from: '2026-11-04T12:20:00-05:00' }], nextCursor: null },
    places: { visits: [{ id: 7, place: 'Workshop' }], trips: [], next: null },
    calendar: { events: [{ title: 'Ring sync' }], nextCursor: null },
    health: { steps: { type: 'steps', bucket: 'hour', values: [{ value: 900 }] },
      heart_rate: { type: 'heart_rate', bucket: 'hour', values: [{ value: 71 }] } } });
  assert.deepEqual(api.calls[0], { method: 'GET', path: '/v1/notes/n1', query: { timezone: 'America/Toronto' } });
  const span = { from: '2026-11-04T12:20:00-05:00', to: '2026-11-04T16:20:00-05:00', timezone: 'America/Toronto' };
  assert.deepEqual(api.calls.slice(1).map(({ path, query }) => [path, query]), [
    ['/v1/days/2026-11-04', { timezone: 'America/Toronto' }], ['/v1/notes', span], ['/v1/places', span], ['/v1/calendar', span],
    ['/v1/health', { type: 'steps', bucket: 'hour', ...span }], ['/v1/health', { type: 'heart_rate', bucket: 'hour', ...span }]]);
});

test('around a time: one with no offset moves as clock time in the zone, one with an offset keeps it, and --hours sets the window', async () => {
  const api = routedApi(AROUND);
  const plain = JSON.parse((await ask(['around', '--at', '2026-11-04T23:30', '--hours', '1'], { fetcher: api.fetcher })).text);
  assert.deepEqual([plain.from, plain.to, plain.timezone, plain.note], ['2026-11-04T22:30:00', '2026-11-05T00:30:00', 'Europe/London', undefined]);
  assert.equal(api.calls.find(call => call.path.startsWith('/v1/days/')).path, '/v1/days/2026-11-04');
  const offset = JSON.parse((await ask(['around', '--at', '2026-11-04T23:30:00Z', '--hours', '12', '--timezone', 'Asia/Tokyo'],
    { fetcher: api.fetcher })).text);
  assert.deepEqual([offset.from, offset.to], ['2026-11-04T11:30:00Z', '2026-11-05T11:30:00Z']);
  // In Tokyo, 23:30 UTC is the next morning.
  assert.equal(api.calls.filter(call => call.path.startsWith('/v1/days/')).at(-1).path, '/v1/days/2026-11-05');
  assert.equal(shiftTime('2026-11-04T00:30+0530', -1), '2026-11-03T23:30:00+05:30');
  assert.equal(dayIn('2026-11-04T23:30:00-05:00', 'Europe/London'), '2026-11-05');
});

test('around refuses a window over 12 hours, and a time it can not read, with no call', async () => {
  const api = routedApi(AROUND);
  for (const hours of ['20', '0', 'many']) {
    assert.deepEqual(await ask(['around', 'n1', '--hours', hours], { fetcher: api.fetcher }),
      { code: 2, text: 'Give --hours from 1 to 12: the window is at most 12 hours each way.' });
  }
  assert.equal((await ask(['around', '--at', 'yesterday'], { fetcher: api.fetcher })).code, 2);
  assert.equal(api.calls.length, 0);
});

test('around shows the parts it read when one fails, and stops at a missing note or a refused key', async () => {
  const failing = routedApi({ ...AROUND, '/calendar': () => ({ status: 503, json: { error: 'try_again', error_description: 'Busy.' } }),
    '/health heart_rate': () => ({ status: 'down' }) });
  const answer = JSON.parse((await ask(['around', 'n1'], { fetcher: failing.fetcher })).text);
  assert.equal(answer.calendar, undefined);
  assert.deepEqual(answer.places.visits, [{ id: 7, place: 'Workshop' }]);
  assert.equal(answer.health.heart_rate, undefined);
  assert.deepEqual(Object.keys(answer.errors), ['calendar', 'health.heart_rate']);
  assert.equal(answer.errors.calendar, 'Relay Everything refused the request: Busy.');
  assert.match(answer.errors['health.heart_rate'], /could not be reached/);
  assert.deepEqual(await ask(['around', 'gone'], { fetcher: failing.fetcher }), { code: 1, text: 'Relay Everything refused the request: No such thing.' });
  const refused = routedApi({ '/notes/n1': () => ({ status: 403, json: { error: 'forbidden', error_description: CHAT_KEY } }) });
  assert.deepEqual(await ask(['around', 'n1'], { fetcher: refused.fetcher }), { code: 1, text: CHAT_KEY });
  const down = async () => { throw new TypeError('fetch failed'); };
  assert.match((await ask(['around', '--at', '2026-11-04T14:00'], { fetcher: down })).text, /could not be reached/);
});

test('around keeps the note it read when every later read gets no answer', async () => {
  const lost = () => ({ status: 'down' });
  const api = routedApi({ '/notes/n1': AROUND['/notes/n1'], '/days/2026-11-04': lost, '/notes': lost, '/places': lost, '/calendar': lost,
    '/health steps': lost, '/health heart_rate': lost });
  const done = await ask(['around', 'n1', '--timezone', 'America/Toronto'], { fetcher: api.fetcher });
  assert.equal(done.code, 0);
  const answer = JSON.parse(done.text);
  assert.equal(answer.note.id, 'n1');
  assert.deepEqual(Object.keys(answer.errors), ['day', 'notes', 'places', 'calendar', 'health.steps', 'health.heart_rate']);
  assert.ok(Object.values(answer.errors).every(line => /could not be reached/.test(line)));
});

const FACTS = [
  { id: 'fa1', tags: ['battery'], sources: ['relay:chat/c1#12', 'relay:note/n1'], fields: { kind: 'decision', text: '40 mAh.' } },
  { id: 'fa2', tags: ['battery'], sources: ['relay:chat/c2', 'relay:chat/c1#40'], fields: { kind: 'open', text: 'Cable.' } },
  { id: 'fa3', tags: ['battery'], sources: ['relay:chat/c3', 'relay:chat/c4'], fields: { kind: 'fact', text: 'Dock.' } },
];
const TOPIC = {
  '/memory': () => ({ json: { facts: FACTS, columns: [], nextCursor: null } }),
  '/notes': () => ({ json: { notes: [{ id: 'n1', tags: ['battery'] }], nextCursor: null } }),
  '/chats/c1': () => ({ json: { id: 'c1', title: 'Battery size', project: 'relay-ring', app: 'claude-code', startedAt: 'a', lastAt: 'b',
    // Newest first, as the server sends a chat's saves.
    saves: [{ title: 'Battery size', text: 'Chose 40 mAh.' }, { title: 'Old', text: 'Old summary' }], messages: [{ text: 'long' }] } }),
  '/chats/c2': () => ({ json: { id: 'c2', title: 'Cable', project: 'relay-ring', app: 'codex', startedAt: 'c', lastAt: 'd', saves: [], messages: [] } }),
  '/chats/c3': () => ({ status: 503, json: { error: 'try_again', error_description: 'Busy.' } }),
};

test('topic pulls the page, its links both ways, its facts and notes, and up to 3 chats its facts name, in one answer', async () => {
  const env = relayHome();
  copy({
    'topics/battery.md': page('Battery', 'Stays 40 mAh', 'Part of the [ring](ring/README.md).'),
    'topics/ring/README.md': page('Ring', 'The ring'),
    'topics/ring/charging.md': page('Charging', 'The dock', 'Charges the [battery](../battery.md).'),
  }, copyOf(env));
  const api = routedApi(TOPIC);
  const done = await relay(['topic', 'battery'], { env, zone: 'Europe/London', fetcher: api.fetcher });
  assert.equal(done.code, 0);
  const answer = JSON.parse(done.text);
  assert.equal(answer.topic, 'battery');
  assert.equal(answer.summary, 'Stays 40 mAh');
  assert.match(answer.page, /^---\ntitle: Battery\n[\s\S]*Part of the \[ring\]/);
  assert.deepEqual(answer.linked, { out: ['ring'], in: ['ring/charging'] });
  assert.deepEqual(answer.facts, FACTS);
  assert.deepEqual(answer.notes, [{ id: 'n1', tags: ['battery'] }]);
  assert.deepEqual(answer.chats, [
    { id: 'c1', title: 'Battery size', project: 'relay-ring', app: 'claude-code', startedAt: 'a', lastAt: 'b', summary: 'Chose 40 mAh.' },
    { id: 'c2', title: 'Cable', project: 'relay-ring', app: 'codex', startedAt: 'c', lastAt: 'd', summary: null }]);
  assert.deepEqual(answer.errors, { 'chat c3': 'Relay Everything refused the request: Busy.' });
  assert.deepEqual(api.calls.slice(0, 2).map(({ path, query }) => [path, query]), [
    ['/v1/memory', { tag: 'battery', limit: '10', timezone: 'Europe/London' }], ['/v1/notes', { tag: 'battery', limit: '5', timezone: 'Europe/London' }]]);
  // One step out, no further: c4 is a fourth chat, and no linked topic is read.
  assert.deepEqual(api.calls.slice(2).map(call => call.path).sort(), ['/v1/chats/c1', '/v1/chats/c2', '/v1/chats/c3']);
});

test('topic answers with page null when only facts carry it, says which part failed, and stops at a refused key', async () => {
  const api = routedApi({ ...TOPIC, '/notes': () => ({ status: 503, json: { error: 'try_again', error_description: 'Busy.' } }),
    '/memory': () => ({ json: { facts: [FACTS[0]], columns: [], nextCursor: null } }) });
  const answer = JSON.parse((await ask(['topic', '#Battery'], { fetcher: api.fetcher })).text);
  assert.deepEqual([answer.topic, answer.page, answer.summary, answer.linked], ['battery', null, null, { out: [], in: [] }]);
  assert.equal(answer.facts.length, 1);
  assert.deepEqual(answer.notes, []);
  assert.deepEqual(answer.chats.map(chat => chat.id), ['c1']);
  assert.deepEqual(answer.errors, { notes: 'Relay Everything refused the request: Busy.' });
  const refused = routedApi({ '/memory': () => ({ status: 403, json: { error: 'forbidden', error_description: 'This device key is turned off.' } }),
    '/notes': TOPIC['/notes'] });
  assert.match((await ask(['topic', 'battery'], { fetcher: refused.fetcher })).text, /^Relay Everything refused this computer's key: This device key is turned off\./);
  assert.equal((await ask(['topic', 'Not a topic!'], { fetcher: api.fetcher })).code, 2);
  // The only chat read gets no answer: the facts and notes already read still show.
  const lost = routedApi({ ...TOPIC, '/memory': () => ({ json: { facts: [FACTS[0]], columns: [], nextCursor: null } }),
    '/chats/c1': () => ({ status: 'down' }) });
  const kept = await ask(['topic', 'battery'], { fetcher: lost.fetcher });
  assert.equal(kept.code, 0);
  const shown = JSON.parse(kept.text);
  assert.deepEqual([shown.facts.length, shown.notes.length, shown.chats], [1, 1, []]);
  assert.deepEqual(Object.keys(shown.errors), ['chat c1']);
  assert.match(shown.errors['chat c1'], /could not be reached/);
  assert.deepEqual(await relay(['topic', 'battery'], { env: relayHome({ connected: false }), fetcher: api.fetcher }), { code: 1, text: NOT_CONNECTED });
});

test('with memory on, topic gives memory\'s pull and then the topic\'s notes and chats; a failed pull answers as before', async () => {
  const place = project();
  writeComputer(place.env, computer(SERVER, true));
  const pulls = [];
  const pulled = (code, text) => (name, options) => { pulls.push([name, options.cwd]); return { code, text }; };
  const api = routedApi({ ...TOPIC, '/notes': () => ({ json: { notes: [{ id: 'n1', title: 'Battery note', recordedAt: '2026-11-04T14:20:00-05:00' }] } }) });
  const ask = (pull, env = place.env) => relay(['topic', '#Battery'], { env, zone: 'Europe/London', fetcher: api.fetcher, cwd: place.root, pull });
  const done = await ask(pulled(0, '# battery\nThe pull.\n\n'));
  assert.equal(done.code, 0);
  assert.equal(done.text, ['# battery', 'The pull.', 'Relay Everything notes on battery:', '- Battery note (n1, 2026-11-04)',
    'Relay Everything chats behind battery\'s facts:', '- Battery size (c1): Chose 40 mAh.', '- Cable (c2)'].join('\n'));
  assert.deepEqual(pulls, [['battery', place.root]]);
  // A pull that fails or says nothing gives the JSON answer.
  for (const pull of [pulled(1, 'Memory could not be reached.'), pulled(0, '  \n')]) assert.equal(JSON.parse((await ask(pull)).text).topic, 'battery');
  // With memory off, or in a project with saving off, there is no pull.
  pulls.length = 0;
  writeComputer(place.env, computer(SERVER, false));
  assert.equal(JSON.parse((await ask(pulled(0, 'Not this.'))).text).topic, 'battery');
  writeComputer(place.env, computer(SERVER, true));
  place.store.setOff(place.root, true);
  assert.equal(JSON.parse((await ask(pulled(0, 'Not this.'))).text).topic, 'battery');
  assert.deepEqual(pulls, []);
});
