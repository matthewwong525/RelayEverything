import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { connect, createServer as createNetServer } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { execFile, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { isLocal, languageLine, networkLine, startForwarder } from './forwarder.mjs';
import { parseFirst, parseUpstream, resolveFirst, resolveUpstream } from './server.mjs';

const LOGIN = 'tester';
const PASSWORD = 's3cret-pass';
const AUTH = `Basic ${Buffer.from(`${LOGIN}:${PASSWORD}`).toString('base64')}`;
// A public name the forwarder sends upstream; the fake gateway, not DNS, answers for it.
const SITE_HOST = 'site.example.test';

const listen = server => new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
const shut = server => new Promise(resolve => { server.closeAllConnections?.(); server.close(() => resolve()); });

/** A fake site: plain HTTP that answers `site:<method> <path> <body>`, and a raw echo for tunnels. */
async function fakeSite() {
  const hits = [];
  const http = createServer((request, response) => {
    hits.push(request.url);
    let body = '';
    request.on('data', chunk => { body += chunk; });
    request.on('end', () => response.end(`site:${request.method} ${request.url} ${body}`));
  });
  const echo = createNetServer(socket => socket.on('data', chunk => socket.write(`echo:${chunk}`)));
  return { http, echo, hits, httpPort: await listen(http), echoPort: await listen(echo) };
}

/** A fake gateway: it records each request's auth, refuses with `refuse` (e.g. 407), and else forwards to the site. */
async function fakeGateway(site, { refuse = null } = {}) {
  const seen = [];
  const gateway = createServer((request, response) => {
    seen.push({ kind: 'http', url: request.url, auth: request.headers['proxy-authorization'] });
    if (refuse) return response.writeHead(refuse).end();
    let body = '';
    request.on('data', chunk => { body += chunk; });
    request.on('end', () => response.end(`gateway:${request.method} ${new URL(request.url).pathname} ${body}`));
  });
  gateway.on('connect', (request, socket, head) => {
    seen.push({ kind: 'connect', url: request.url, auth: request.headers['proxy-authorization'] });
    if (refuse) return socket.end(`HTTP/1.1 ${refuse} Refused\r\nContent-Length: 0\r\n\r\n`);
    const out = connect({ host: '127.0.0.1', port: site.echoPort }, () => {
      socket.write('HTTP/1.1 200 Connection established\r\n\r\n');
      if (head.length) out.write(head);
      out.pipe(socket);
      socket.pipe(out);
    });
    out.on('error', () => socket.destroy());
    socket.on('error', () => out.destroy());
  });
  return { gateway, seen, port: await listen(gateway) };
}

/** A tunnel through the forwarder to `target`: the CONNECT reply, then what `ping` echoes back. */
function tunnel(port, target, ping = 'ping') {
  return new Promise((resolve, reject) => {
    const socket = connect({ host: '127.0.0.1', port }, () => socket.write(`CONNECT ${target} HTTP/1.1\r\nHost: ${target}\r\n\r\n`));
    let text = '';
    let sent = false;
    socket.on('data', chunk => {
      text += chunk;
      if (!sent && text.includes('\r\n\r\n')) {
        sent = true;
        if (!/^HTTP\/1\.1 200/.test(text)) { socket.destroy(); return resolve({ status: text.split('\r\n')[0], echo: null }); }
        socket.write(ping);
      }
      if (sent && text.includes(`echo:${ping}`)) { socket.destroy(); resolve({ status: text.split('\r\n')[0], echo: `echo:${ping}` }); }
    });
    socket.on('error', reject);
    socket.on('close', () => resolve({ status: text.split('\r\n')[0], echo: null }));
  });
}

/** A plain HTTP request through the forwarder, as a browser sends it to a proxy. */
async function viaProxy(port, url, { method = 'GET', body } = {}) {
  return new Promise((resolve, reject) => {
    const socket = connect({ host: '127.0.0.1', port }, () => {
      const length = body ? `Content-Length: ${Buffer.byteLength(body)}\r\n` : '';
      socket.write(`${method} ${url} HTTP/1.1\r\nHost: ${new URL(url).host}\r\nConnection: close\r\n${length}\r\n${body ?? ''}`);
    });
    let text = '';
    socket.on('data', chunk => { text += chunk; });
    socket.on('error', reject);
    socket.on('close', () => resolve({ status: Number(text.split(' ')[1]), body: text.split('\r\n\r\n').slice(1).join('\r\n\r\n') }));
  });
}

function setup() {
  const dir = mkdtempSync(join(tmpdir(), 'forwarder-test-'));
  return { dir, file: join(dir, 'network.json'), done: () => rmSync(dir, { recursive: true, force: true }) };
}
/** The network state without its pid, which must be this process's: the forwarder runs in the test. */
const read = file => {
  const { pid, ...state } = JSON.parse(readFileSync(file, 'utf8'));
  assert.equal(pid, process.pid);
  return state;
};
const wait = ms => new Promise(done => setTimeout(done, ms));

test('a tunnel and a plain request go through the upstream with its login', async () => {
  const site = await fakeSite();
  const gw = await fakeGateway(site);
  const { file, done } = setup();
  const proxy = await startForwarder({ upstream: { host: '127.0.0.1', port: gw.port, username: LOGIN, password: PASSWORD }, networkFile: file });
  try {
    const opened = await tunnel(proxy.port, `${SITE_HOST}:443`);
    assert.match(opened.status, /^HTTP\/1\.1 200/);
    assert.equal(opened.echo, 'echo:ping');
    const page = await viaProxy(proxy.port, `http://${SITE_HOST}/hello?x=1`, { method: 'POST', body: 'form=1' });
    assert.equal(page.status, 200);
    assert.equal(page.body, 'gateway:POST /hello form=1');
    assert.deepEqual(gw.seen.map(({ kind, url, auth }) => [kind, url, auth]), [
      ['connect', `${SITE_HOST}:443`, AUTH],
      ['http', `http://${SITE_HOST}/hello?x=1`, AUTH],
    ]);
    assert.deepEqual(read(file), { network: 'upstream' });
    assert.equal(statSync(file).mode & 0o777, 0o600);
  } finally {
    await proxy.close();
    await Promise.all([shut(gw.gateway), shut(site.http), shut(site.echo)]);
    done();
  }
});

// The fallback tests reach the fake site at 127.0.0.1, so `local` marks no address local: each goes upstream first.
const remote = () => false;

test('a 407 from the upstream sends the same request directly and records why, with the language kept, never the site or the login', async () => {
  const site = await fakeSite();
  const gw = await fakeGateway(site, { refuse: 407 });
  const { file, done } = setup();
  const proxy = await startForwarder({
    upstream: { host: '127.0.0.1', port: gw.port, username: LOGIN, password: PASSWORD }, networkFile: file, extra: { language: 'english' }, local: remote,
  });
  try {
    assert.deepEqual(read(file), { network: 'upstream', language: 'english' });
    const page = await viaProxy(proxy.port, `http://127.0.0.1:${site.httpPort}/x`, { method: 'POST', body: 'a=1' });
    assert.equal(gw.seen.length, 1);
    assert.equal(page.status, 200);
    assert.equal(page.body, 'site:POST /x a=1');
    // The later write keeps the language server.mjs passed at the start.
    assert.deepEqual(read(file), { network: 'direct', reason: 'unreachable', language: 'english' });
    const text = JSON.stringify(read(file));
    for (const secret of [LOGIN, PASSWORD, '127.0.0.1', String(site.httpPort), String(gw.port)]) assert.ok(!text.includes(secret), `network.json names ${secret}`);
  } finally {
    await proxy.close();
    await Promise.all([shut(gw.gateway), shut(site.http), shut(site.echo)]);
    done();
  }
});

test('a refused or closed upstream tunnel falls back to the site directly, and a working one is used again', async () => {
  const site = await fakeSite();
  const { file, done } = setup();
  const upstream = port => ({ host: '127.0.0.1', port, username: LOGIN, password: PASSWORD });
  const closing = createNetServer(socket => socket.destroy());
  const refusing = await fakeGateway(site, { refuse: 407 });
  try {
    for (const port of [await listen(closing), refusing.port]) {
      const proxy = await startForwarder({ upstream: upstream(port), networkFile: file, connectMs: 2000, local: remote });
      try {
        assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
        assert.deepEqual(read(file), { network: 'direct', reason: 'unreachable' });
      } finally {
        await proxy.close();
      }
    }
    assert.equal(refusing.seen.length, 1);
    // One forwarder whose upstream fails, then answers: later connections use it again.
    let refuse = true;
    const flaky = createServer();
    flaky.on('connect', (request, socket) => {
      if (refuse) return socket.end('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n');
      const out = connect({ host: '127.0.0.1', port: site.echoPort }, () => { socket.write('HTTP/1.1 200 OK\r\n\r\n'); out.pipe(socket); socket.pipe(out); });
    });
    const proxy = await startForwarder({ upstream: upstream(await listen(flaky)), networkFile: file, local: remote });
    try {
      assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
      assert.deepEqual(read(file), { network: 'direct', reason: 'unreachable' });
      refuse = false;
      assert.equal((await tunnel(proxy.port, `${SITE_HOST}:443`)).echo, 'echo:ping');
      assert.deepEqual(read(file), { network: 'upstream' });
    } finally {
      await proxy.close();
      await shut(flaky);
    }
  } finally {
    await Promise.all([shut(closing), shut(refusing.gateway), shut(site.http), shut(site.echo)]);
    done();
  }
});

/** A first proxy at `port` with no login like a home proxy, and the paid upstream behind it. */
const routes = (firstPort, upstreamPort) => ({
  first: { host: '127.0.0.1', port: firstPort },
  upstream: { host: '127.0.0.1', port: upstreamPort, username: LOGIN, password: PASSWORD },
});

test('Pi on: the first proxy carries tunnels and plain requests with no login, and the upstream gets nothing', async () => {
  const site = await fakeSite();
  const pi = await fakeGateway(site);
  const backup = await fakeGateway(site);
  const { file, done } = setup();
  const proxy = await startForwarder({ ...routes(pi.port, backup.port), networkFile: file });
  try {
    assert.equal((await tunnel(proxy.port, `${SITE_HOST}:443`)).echo, 'echo:ping');
    assert.equal((await viaProxy(proxy.port, `http://${SITE_HOST}/home`)).body, 'gateway:GET /home ');
    assert.deepEqual(pi.seen.map(({ kind, auth }) => [kind, auth]), [['connect', undefined], ['http', undefined]]);
    assert.equal(backup.seen.length, 0);
    assert.deepEqual(read(file), { network: 'upstream' });
  } finally {
    await proxy.close();
    await Promise.all([shut(pi.gateway), shut(backup.gateway), shut(site.http), shut(site.echo)]);
    done();
  }
});

test('Pi off (502): the same tunnel goes through the upstream, the Pi waits 60 seconds, then is tried again', async () => {
  const site = await fakeSite();
  let down = true;
  const tries = [];
  const pi = createServer();
  pi.on('connect', (request, socket) => {
    tries.push(request.url);
    if (down) return socket.end('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n');
    const out = connect({ host: '127.0.0.1', port: site.echoPort }, () => { socket.write('HTTP/1.1 200 OK\r\n\r\n'); out.pipe(socket); socket.pipe(out); });
  });
  const backup = await fakeGateway(site);
  const { file, done } = setup();
  const proxy = await startForwarder({ ...routes(await listen(pi), backup.port), networkFile: file, downMs: 400 });
  try {
    assert.equal((await tunnel(proxy.port, `${SITE_HOST}:443`)).echo, 'echo:ping');
    assert.deepEqual(read(file), { network: 'upstream', route: 'backup' });
    assert.deepEqual(backup.seen.map(({ kind, auth }) => [kind, auth]), [['connect', AUTH]]);
    // Within the skip, connections start at the upstream: the Pi sees no second try, plain requests included.
    assert.equal((await tunnel(proxy.port, `${SITE_HOST}:443`)).echo, 'echo:ping');
    assert.equal((await viaProxy(proxy.port, `http://${SITE_HOST}/skip`)).body, 'gateway:GET /skip ');
    assert.equal(tries.length, 1);
    assert.equal(backup.seen.length, 3);
    // After the skip the Pi is tried again; it is back, so it carries the tunnel.
    down = false;
    await wait(500);
    assert.equal((await tunnel(proxy.port, `${SITE_HOST}:443`)).echo, 'echo:ping');
    assert.equal(tries.length, 2);
    assert.equal(backup.seen.length, 3);
    assert.deepEqual(read(file), { network: 'upstream' });
  } finally {
    await proxy.close();
    await Promise.all([shut(pi), shut(backup.gateway), shut(site.http), shut(site.echo)]);
    done();
  }
});

test('Pi off (timeout): a first proxy that never answers moves the tunnel to the upstream', async () => {
  const site = await fakeSite();
  const silent = createNetServer(socket => socket.on('data', () => {}));
  const backup = await fakeGateway(site);
  const { file, done } = setup();
  const proxy = await startForwarder({ ...routes(await listen(silent), backup.port), networkFile: file, connectMs: 300 });
  try {
    assert.equal((await tunnel(proxy.port, `${SITE_HOST}:443`)).echo, 'echo:ping');
    assert.deepEqual(read(file), { network: 'upstream', route: 'backup' });
    assert.equal(backup.seen.length, 1);
  } finally {
    await proxy.close();
    await Promise.all([shut(silent), shut(backup.gateway), shut(site.http), shut(site.echo)]);
    done();
  }
});

test('a site the Pi can not reach starts the skip only when the upstream then opens the same tunnel', async () => {
  const site = await fakeSite();
  // The home proxy answers 500 when the site fails with the Pi on.
  const pi = await fakeGateway(site, { refuse: 500 });
  let refuse = true;
  const tries = [];
  const backup = createServer();
  backup.on('connect', (request, socket) => {
    tries.push(request.url);
    if (refuse) return socket.end('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n');
    const out = connect({ host: '127.0.0.1', port: site.echoPort }, () => { socket.write('HTTP/1.1 200 OK\r\n\r\n'); out.pipe(socket); socket.pipe(out); });
  });
  const { file, done } = setup();
  const proxy = await startForwarder({ ...routes(pi.port, await listen(backup)), networkFile: file, local: remote });
  try {
    // The upstream fails too: the site is down, not the Pi, so the next connection tries the Pi first again.
    assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
    assert.deepEqual(read(file), { network: 'direct', reason: 'unreachable' });
    assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
    assert.equal(pi.seen.length, 2);
    assert.equal(tries.length, 2);
    // The upstream opens it: the Pi is the problem, so the next connection starts at the upstream.
    refuse = false;
    assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
    assert.deepEqual(read(file), { network: 'upstream', route: 'backup' });
    assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
    assert.equal(pi.seen.length, 3);
    assert.equal(tries.length, 4);
  } finally {
    await proxy.close();
    await Promise.all([shut(pi.gateway), shut(backup), shut(site.http), shut(site.echo)]);
    done();
  }
});

test('both routes down: the tunnel goes direct and the state says the upstream is unreachable', async () => {
  const site = await fakeSite();
  const pi = await fakeGateway(site, { refuse: 502 });
  const backup = await fakeGateway(site, { refuse: 407 });
  const { file, done } = setup();
  const proxy = await startForwarder({ ...routes(pi.port, backup.port), networkFile: file, local: remote });
  try {
    assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
    assert.deepEqual(read(file), { network: 'direct', reason: 'unreachable' });
    assert.equal(pi.seen.length, 1);
    assert.equal(backup.seen.length, 1);
  } finally {
    await proxy.close();
    await Promise.all([shut(pi.gateway), shut(backup.gateway), shut(site.http), shut(site.echo)]);
    done();
  }
});

test('a plain request to a down first proxy gets its error page once, but one it never reached goes to the upstream', async () => {
  const site = await fakeSite();
  // The home proxy always takes the request; with the Pi down it answers 502. The request may have left.
  const pi = await fakeGateway(site, { refuse: 502 });
  const backup = await fakeGateway(site);
  const { file, done } = setup();
  const closed = createNetServer();
  const closedPort = await listen(closed);
  await shut(closed);
  try {
    const proxy = await startForwarder({ ...routes(pi.port, backup.port), networkFile: file });
    try {
      const page = await viaProxy(proxy.port, `http://${SITE_HOST}/pay`, { method: 'POST', body: 'once=1' });
      assert.equal(page.status, 502);
      assert.equal(pi.seen.length, 1);
      assert.equal(backup.seen.length, 0, 'the request went to the upstream as well');
    } finally {
      await proxy.close();
    }
    // A first proxy that refuses the connection never had the request: the upstream sends it, and the Pi waits.
    const refused = await startForwarder({ ...routes(closedPort, backup.port), networkFile: file });
    try {
      assert.equal((await viaProxy(refused.port, `http://${SITE_HOST}/a`, { method: 'POST', body: 'b=1' })).body, 'gateway:POST /a b=1');
      assert.deepEqual(read(file), { network: 'upstream', route: 'backup' });
      assert.deepEqual(backup.seen.map(({ kind, auth }) => [kind, auth]), [['http', AUTH]]);
    } finally {
      await refused.close();
    }
  } finally {
    await Promise.all([shut(pi.gateway), shut(backup.gateway), shut(site.http), shut(site.echo)]);
    done();
  }
});

test('a first proxy alone, when down, gives a direct connection and is tried again next time', async () => {
  const site = await fakeSite();
  const pi = await fakeGateway(site, { refuse: 502 });
  const { file, done } = setup();
  const proxy = await startForwarder({ first: { host: '127.0.0.1', port: pi.port }, networkFile: file, local: remote });
  try {
    assert.deepEqual(read(file), { network: 'upstream' });
    assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
    assert.deepEqual(read(file), { network: 'direct', reason: 'unreachable' });
    // No upstream opened the tunnel, so no skip starts: the next one tries the Pi again.
    assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
    assert.equal(pi.seen.length, 2);
  } finally {
    await proxy.close();
    await Promise.all([shut(pi.gateway), shut(site.http), shut(site.echo)]);
    done();
  }
});

test('with no upstream, every connection is direct and the state says so', async () => {
  const site = await fakeSite();
  const { file, done } = setup();
  const proxy = await startForwarder({ networkFile: file });
  try {
    assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
    assert.equal((await viaProxy(proxy.port, `http://127.0.0.1:${site.httpPort}/a`)).body, 'site:GET /a ');
    assert.deepEqual(read(file), { network: 'direct', reason: 'no-upstream' });
  } finally {
    await proxy.close();
    await Promise.all([shut(site.http), shut(site.echo)]);
    done();
  }
});

test('local addresses never go upstream', async () => {
  const site = await fakeSite();
  const gw = await fakeGateway(site);
  const { file, done } = setup();
  const proxy = await startForwarder({ upstream: { host: '127.0.0.1', port: gw.port, username: LOGIN, password: PASSWORD }, networkFile: file });
  try {
    assert.equal((await tunnel(proxy.port, `127.0.0.1:${site.echoPort}`)).echo, 'echo:ping');
    assert.equal((await viaProxy(proxy.port, `http://localhost:${site.httpPort}/b`)).body, 'site:GET /b ');
    assert.equal(gw.seen.length, 0);
  } finally {
    await proxy.close();
    await Promise.all([shut(gw.gateway), shut(site.http), shut(site.echo)]);
    done();
  }
  for (const host of ['localhost', 'app.localhost', '127.0.0.1', '10.1.2.3', '192.168.0.4', '172.20.0.1', '169.254.1.1', '100.100.1.1', '::1', 'fd00::1', 'fe80::1', '::ffff:127.0.0.1']) assert.ok(isLocal(host), host);
  for (const host of ['example.com', '203.0.113.8', '172.32.0.1', '2606:4700::1111']) assert.ok(!isLocal(host), host);
});

test('the status line names each network, and a state from another process or none reads as no upstream', () => {
  assert.equal(networkLine({ network: 'upstream', pid: 7 }, 7), 'upstream');
  assert.equal(networkLine({ network: 'upstream', route: 'backup', pid: 7 }, 7), 'upstream (backup)');
  assert.equal(networkLine({ network: 'direct', reason: 'no-upstream', pid: 7 }, 7), 'direct (no upstream proxy)');
  assert.equal(networkLine({ network: 'direct', reason: 'unreachable', pid: 7 }, 7), 'direct (upstream unreachable)');
  assert.equal(networkLine({ network: 'upstream', pid: 6 }, 7), 'direct (no upstream proxy)');
  assert.equal(networkLine({ network: 'upstream' }, 7), 'direct (no upstream proxy)');
  assert.equal(networkLine(null, 7), 'direct (no upstream proxy)');
  assert.equal(networkLine({ network: 'upstream', pid: 7 }, null), 'unknown (browser stopped)');
});

test('a plain request is sent directly after an upstream connect error, but never again once the gateway took it', async () => {
  const site = await fakeSite();
  const { file, done } = setup();
  const upstream = port => ({ host: '127.0.0.1', port, username: LOGIN, password: PASSWORD });
  const closed = createNetServer();
  const closedPort = await listen(closed);
  await shut(closed);
  // A gateway that reads the request, then drops it or never answers: the site may already have it.
  const received = [];
  const dropping = createNetServer(socket => socket.once('data', chunk => { received.push(String(chunk)); socket.destroy(); }));
  const silent = createNetServer(socket => socket.once('data', chunk => received.push(String(chunk))));
  try {
    const refused = await startForwarder({ upstream: upstream(closedPort), networkFile: file, local: remote });
    try {
      const page = await viaProxy(refused.port, `http://127.0.0.1:${site.httpPort}/c`, { method: 'POST', body: 'b=1' });
      assert.equal(page.body, 'site:POST /c b=1');
      assert.deepEqual(read(file), { network: 'direct', reason: 'unreachable' });
    } finally {
      await refused.close();
    }
    site.hits.length = 0;
    for (const gateway of [dropping, silent]) {
      const proxy = await startForwarder({ upstream: upstream(await listen(gateway)), networkFile: file, connectMs: 500, local: remote });
      try {
        const page = await viaProxy(proxy.port, `http://127.0.0.1:${site.httpPort}/pay`, { method: 'POST', body: 'once=1' });
        assert.equal(page.status, 502);
        assert.deepEqual(read(file), { network: 'upstream' });
      } finally {
        await proxy.close();
      }
    }
    assert.equal(received.length, 2);
    for (const text of received) assert.match(text, /^POST http:\/\/127\.0\.0\.1:\d+\/pay /);
    assert.deepEqual(site.hits, [], 'the request reached the site directly as well');
  } finally {
    await Promise.all([shut(dropping), shut(silent), shut(site.http), shut(site.echo)]);
    done();
  }
});

test('a tunnel cancelled while the upstream is still dialing writes no unreachable state', async () => {
  const { file, done } = setup();
  let dialed;
  const dialing = new Promise(resolve => { dialed = resolve; });
  const silent = createNetServer(socket => socket.once('data', () => dialed()));
  const proxy = await startForwarder({ upstream: { host: '127.0.0.1', port: await listen(silent), username: LOGIN, password: PASSWORD }, networkFile: file, connectMs: 5000 });
  try {
    const client = connect({ host: '127.0.0.1', port: proxy.port }, () => client.write(`CONNECT ${SITE_HOST}:443 HTTP/1.1\r\nHost: ${SITE_HOST}:443\r\n\r\n`));
    client.on('error', () => {});
    await dialing;
    // Closing destroys the browser's socket mid-dial, as a browser hang-up does: no fallback and no state follow.
    await proxy.close();
    await wait(200);
    assert.ok(!existsSync(file), 'the cancelled dial wrote a network state');
  } finally {
    await shut(silent);
    done();
  }
});

test('closing the forwarder deletes its network state, but not a state another start wrote', async () => {
  const { file, done } = setup();
  try {
    const proxy = await startForwarder({ networkFile: file });
    assert.deepEqual(read(file), { network: 'direct', reason: 'no-upstream' });
    await proxy.close();
    assert.ok(!existsSync(file));
    const other = await startForwarder({ networkFile: file });
    writeFileSync(file, JSON.stringify({ network: 'upstream', pid: process.pid + 1 }));
    await other.close();
    assert.ok(existsSync(file));
  } finally {
    done();
  }
});

test('the proxy line parses with or without http://, and a wrong shape gives no upstream', () => {
  const want = { host: 'gw.example.test', port: 10000, username: 'abc', password: 'p@ss:w' };
  assert.deepEqual(parseUpstream('abc:p@ss:w@gw.example.test:10000'), want);
  assert.deepEqual(parseUpstream(' http://abc:p@ss:w@gw.example.test:10000/ '), want);
  assert.deepEqual(parseUpstream('HTTP://u:p@[2001:db8::1]:8080'), { host: '2001:db8::1', port: 8080, username: 'u', password: 'p' });
  for (const bad of ['', undefined, 'gw.example.test:10000', 'u@gw.example.test:1', ':p@gw.example.test:1', 'u:@gw.example.test:1',
    'u:p@gw.example.test', 'u:p@gw.example.test:0', 'u:p@gw.example.test:70000', 'socks5://u:p@gw.example.test:1', 'https://u:p@gw.example.test:1']) {
    assert.equal(parseUpstream(bad), null, String(bad));
  }
});

test('a repo line is saved for the computer with mode 600, and a start without one reads that file', () => {
  const { dir, done } = setup();
  const file = join(dir, 'home', '.wong-stack', 'camoufox', 'upstream-proxy');
  // Never the real old file: this test's home is not a temp one.
  const oldFile = join(dir, 'home', '.wong-stack', 'camofox', 'upstream-proxy');
  const envFile = join(dir, '.env');
  const line = `${LOGIN}:${PASSWORD}@gw.example.test:10000`;
  const upstream = { host: 'gw.example.test', port: 10000, username: LOGIN, password: PASSWORD };
  try {
    assert.equal(resolveUpstream({ env: {}, envFile, file, oldFile }), null);
    assert.ok(!existsSync(file), 'nothing saved without a line');
    writeFileSync(envFile, `BROWSE_UPSTREAM_PROXY="${line}"\n`);
    assert.deepEqual(resolveUpstream({ env: {}, envFile, file, oldFile }), upstream);
    assert.equal(readFileSync(file, 'utf8'), `${line}\n`);
    assert.equal(statSync(file).mode & 0o777, 0o600);
    // A rotated key in the environment wins over the .env file and replaces the saved line.
    const rotated = `${LOGIN}:new-pass@gw.example.test:10001`;
    assert.equal(resolveUpstream({ env: { BROWSE_UPSTREAM_PROXY: rotated }, envFile, file, oldFile }).password, 'new-pass');
    assert.equal(readFileSync(file, 'utf8'), `${rotated}\n`);
    assert.equal(statSync(file).mode & 0o777, 0o600);
    // Another repo, with no key of its own, uses the computer file.
    assert.deepEqual(resolveUpstream({ env: {}, envFile: join(dir, 'other.env'), file, oldFile }), { ...upstream, port: 10001, password: 'new-pass' });
    // A repo line of the wrong shape gives no upstream and leaves the saved line alone.
    assert.equal(resolveUpstream({ env: { BROWSE_UPSTREAM_PROXY: 'not a line' }, envFile, file, oldFile }), null);
    assert.equal(readFileSync(file, 'utf8'), `${rotated}\n`);
    // With no new file, the old camofox line is copied over once; a blank new file, as network off leaves, stops that.
    rmSync(file);
    mkdirSync(dirname(oldFile), { recursive: true });
    writeFileSync(oldFile, `${line}\n`);
    assert.deepEqual(resolveUpstream({ env: {}, envFile: join(dir, 'other.env'), file, oldFile }), upstream);
    assert.equal(readFileSync(file, 'utf8'), `${line}\n`);
    writeFileSync(file, '');
    assert.equal(resolveUpstream({ env: {}, envFile: join(dir, 'other.env'), file, oldFile }), null);
  } finally {
    done();
  }
});

test('the first proxy line parses with or without a login, and a wrong shape gives none', () => {
  assert.deepEqual(parseFirst('http://127.0.0.1:1055'), { host: '127.0.0.1', port: 1055 });
  assert.deepEqual(parseFirst(' 127.0.0.1:1055/ '), { host: '127.0.0.1', port: 1055 });
  assert.deepEqual(parseFirst('[::1]:1055'), { host: '::1', port: 1055 });
  assert.deepEqual(parseFirst('u:p@w@pi.example.test:3128'), { host: 'pi.example.test', port: 3128, username: 'u', password: 'p@w' });
  for (const bad of ['', undefined, '127.0.0.1', '127.0.0.1:0', 'u@127.0.0.1:1055', 'socks5://127.0.0.1:1055', 'https://127.0.0.1:1055', 'a b:1055']) {
    assert.equal(parseFirst(bad), null, String(bad));
  }
  // The upstream line still needs its login.
  assert.equal(parseUpstream('http://127.0.0.1:1055'), null);
});

test('the first proxy line is saved for the computer like the upstream line, under its own key and file', () => {
  const { dir, done } = setup();
  const file = join(dir, 'home', '.wong-stack', 'camoufox', 'first-proxy');
  const oldFile = join(dir, 'home', '.wong-stack', 'camofox', 'first-proxy');
  const envFile = join(dir, '.env');
  try {
    assert.equal(resolveFirst({ env: {}, envFile, file, oldFile }), null);
    // The upstream key does not count as a first proxy line.
    assert.equal(resolveFirst({ env: { BROWSE_UPSTREAM_PROXY: `${LOGIN}:${PASSWORD}@gw.example.test:1` }, envFile, file, oldFile }), null);
    writeFileSync(envFile, 'BROWSE_FIRST_PROXY=http://127.0.0.1:1055\n');
    assert.deepEqual(resolveFirst({ env: {}, envFile, file, oldFile }), { host: '127.0.0.1', port: 1055 });
    assert.equal(readFileSync(file, 'utf8'), 'http://127.0.0.1:1055\n');
    assert.equal(statSync(file).mode & 0o777, 0o600);
    assert.deepEqual(resolveFirst({ env: {}, envFile: join(dir, 'other.env'), file, oldFile }), { host: '127.0.0.1', port: 1055 });
    assert.equal(resolveFirst({ env: { BROWSE_FIRST_PROXY: 'not a line' }, envFile, file, oldFile }), null);
    assert.equal(readFileSync(file, 'utf8'), 'http://127.0.0.1:1055\n');
    // While the new file is missing, the old camofox file's line is copied over.
    rmSync(file);
    mkdirSync(dirname(oldFile), { recursive: true });
    writeFileSync(oldFile, 'http://127.0.0.1:1056\n');
    assert.deepEqual(resolveFirst({ env: {}, envFile: join(dir, 'other.env'), file, oldFile }), { host: '127.0.0.1', port: 1056 });
    assert.equal(readFileSync(file, 'utf8'), 'http://127.0.0.1:1056\n');
  } finally {
    done();
  }
});

/** Runs browse.mjs in a temporary home with no proxy key anywhere it looks first. */
function browse(home, ...words) {
  const script = fileURLToPath(new URL('./browse.mjs', import.meta.url));
  const env = { ...process.env, HOME: home };
  delete env.BROWSE_UPSTREAM_PROXY;
  delete env.BROWSE_FIRST_PROXY;
  return spawnSync(process.execPath, [script, ...words], { env, encoding: 'utf8' });
}

/** The `BROWSE_NETWORK=` and `BROWSE_LANGUAGE=` lines `status` prints; spawned async, so this process can answer as
 * the fake server. */
function networkStatus(home) {
  const script = fileURLToPath(new URL('./browse.mjs', import.meta.url));
  const env = { ...process.env, HOME: home };
  delete env.BROWSE_UPSTREAM_PROXY;
  delete env.BROWSE_FIRST_PROXY;
  return new Promise(resolve => {
    execFile(process.execPath, [script, 'status'], { env, encoding: 'utf8' }, (_, stdout) => {
      resolve(stdout.split('\n').filter(text => /^BROWSE_(NETWORK|LANGUAGE)=/.test(text)));
    });
  });
}

test('browse.mjs status prints the network and language lines only from the running server\'s network.json, and stop deletes it', async () => {
  const { dir, done } = setup();
  const camoufox = join(dir, '.wong-stack', 'camoufox');
  const file = join(camoufox, 'network.json');
  // A fake running server: this test process's pid, and a port that answers /health.
  const health = createServer((_, response) => response.end('ok'));
  try {
    mkdirSync(camoufox, { recursive: true });
    writeFileSync(file, JSON.stringify({ network: 'upstream', language: 'english', pid: process.pid }));
    assert.deepEqual(await networkStatus(dir), ['BROWSE_NETWORK=unknown (browser stopped)']);
    writeFileSync(join(camoufox, 'server.json'), JSON.stringify({ pid: process.pid, port: await listen(health), proxy: 'local' }));
    const before = 'unknown (started before this fix)';
    for (const [state, line, language] of [
      [{ network: 'upstream', language: 'english', pid: process.pid }, 'upstream', 'english'],
      [{ network: 'upstream', route: 'backup', language: 'english', pid: process.pid }, 'upstream (backup)', 'english'],
      [{ network: 'direct', reason: 'unreachable', language: 'random', pid: process.pid }, 'direct (upstream unreachable)', 'random (browser tool changed)'],
      [{ network: 'upstream', pid: process.pid }, 'upstream', before],
      [{ network: 'upstream', language: 'english', pid: process.pid + 1 }, 'direct (no upstream proxy)', before],
      [{ network: 'upstream' }, 'direct (no upstream proxy)', before],
    ]) {
      writeFileSync(file, JSON.stringify(state));
      assert.deepEqual(await networkStatus(dir), [`BROWSE_NETWORK=${line}`, `BROWSE_LANGUAGE=${language}`]);
    }
    rmSync(file);
    assert.deepEqual(await networkStatus(dir), ['BROWSE_NETWORK=direct (no upstream proxy)', `BROWSE_LANGUAGE=${before}`]);
    // Stop with no server.json, so it signals no process; it still deletes the network state.
    rmSync(join(camoufox, 'server.json'));
    writeFileSync(file, JSON.stringify({ network: 'upstream', pid: 1 }));
    assert.equal(browse(dir, 'stop').status, 0);
    assert.ok(!existsSync(file));
  } finally {
    await shut(health);
    done();
  }
});

test('browse.mjs network off blanks both computer files and says to blank the keys and restart', () => {
  const { dir, done } = setup();
  const file = join(dir, '.wong-stack', 'camoufox', 'upstream-proxy');
  const firstFile = join(dir, '.wong-stack', 'camoufox', 'first-proxy');
  try {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, `${LOGIN}:${PASSWORD}@gw.example.test:10000\n`, { mode: 0o600 });
    writeFileSync(firstFile, 'http://127.0.0.1:1055\n', { mode: 0o600 });
    const off = browse(dir, 'network', 'off');
    assert.equal(off.status, 0);
    assert.match(off.stdout, /^BROWSE_FIRST=deleted$/m);
    assert.match(off.stdout, /^BROWSE_UPSTREAM=deleted$/m);
    assert.match(off.stdout, /Blank BROWSE_FIRST_PROXY and BROWSE_UPSTREAM_PROXY .*stop and start the browser/);
    assert.ok(!off.stdout.includes(PASSWORD));
    assert.equal(readFileSync(file, 'utf8'), '');
    assert.equal(readFileSync(firstFile, 'utf8'), '');
    const again = browse(dir, 'network', 'off').stdout;
    assert.match(again, /^BROWSE_FIRST=none$/m);
    assert.match(again, /^BROWSE_UPSTREAM=none$/m);
    assert.equal(browse(dir, 'network', 'on').status, 2);
  } finally {
    done();
  }
});

test('the status line names the language while the browser runs, and nothing when it is stopped', () => {
  assert.equal(languageLine({ network: 'upstream', language: 'english', pid: 7 }, 7), 'english');
  assert.equal(languageLine({ network: 'upstream', language: 'random', pid: 7 }, 7), 'random (browser tool changed)');
  assert.equal(languageLine({ network: 'upstream', pid: 7 }, 7), 'unknown (started before this fix)');
  assert.equal(languageLine({ network: 'upstream', language: 'english', pid: 6 }, 7), 'unknown (started before this fix)');
  assert.equal(languageLine(null, 7), 'unknown (started before this fix)');
  assert.equal(languageLine({ network: 'upstream', language: 'english', pid: 7 }, null), null);
});
