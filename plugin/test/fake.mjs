// Test helpers: a fake Relay Everything server that keeps chats as the real routes do, a made-up project and
// transcript, and a Relay Everything folder of its own, so no test reads or writes this computer's real one.
import { execFileSync } from 'node:child_process';
import { appendFileSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { run } from '../bin/hook.mjs';
import { openState, stateDir, writeComputer } from '../lib/config.mjs';

export const SESSION = '5d1c2b7a-0e4f-4a6b-9c3d-8e7f6a5b4c3d';
export const SECRET = `rek_${'made-up'.padEnd(43, 'x')}`;
export const SERVER = 'https://relay.example.com';
export const API = 'https://connector.example.com/v1';
export const computer = (server = SERVER, memory = false) => ({ server, key: SECRET, api: API, name: 'Laptop', memory });

const answer = (status, json) => new Response(JSON.stringify(json), { status, headers: { 'content-type': 'application/json' } });

/** A server that holds each session's messages in order, refuses gaps and caps, and can be taken down. */
export function fakeServer() {
  const server = { chats: new Map(), apps: new Map(), saves: [], calls: [], down: false };
  server.fetch = async (url, init) => {
    const body = JSON.parse(init.body);
    const route = url.split('/apps/relay/api/')[1];
    server.calls.push({ url, route, body, bytes: Buffer.byteLength(init.body), auth: init.headers.Authorization });
    if (server.down) throw new TypeError('fetch failed');
    if (route === 'chat-saves') {
      if (!server.chats.has(body.sessionId)) return answer(404, { error: { code: 'not_found' } });
      server.saves.push(body);
      return answer(200, { ok: true });
    }
    if (body.messages.length > 500 || Buffer.byteLength(init.body) > 4 * 1024 * 1024) return answer(413, { error: { code: 'too_large' } });
    const held = server.chats.get(body.sessionId) ?? [];
    if ((body.messages[0]?.seq ?? 0) > held.length) return answer(400, { error: { code: 'invalid_input' }, stored: held.length });
    for (const message of body.messages) if (message.seq === held.length) held.push(message);
    // The app is kept from the first send.
    if (held.length && !server.apps.has(body.sessionId)) server.apps.set(body.sessionId, body.app ?? 'claude-code');
    if (held.length) server.chats.set(body.sessionId, held);
    return answer(200, { stored: held.length });
  };
  return server;
}

/** A transcript line: `you` typed it, or the AI said it. */
export const said = (role, text, second = 0) => JSON.stringify({
  type: role === 'you' ? 'user' : 'assistant',
  timestamp: new Date(Date.parse('2026-11-04T14:00:00.000Z') + second * 1000).toISOString(),
  message: { role: role === 'you' ? 'user' : 'assistant', content: role === 'you' ? text : [{ type: 'text', text }] },
});

/** A folder for the Relay Everything files, connected unless `connected` is false; answers the env a hook gets. */
export function relayHome({ connected = true } = {}) {
  const env = { RELAY_EVERYTHING_HOME: join(mkdtempSync(join(tmpdir(), 'relay-home-')), 'relay-everything') };
  if (connected) writeComputer(env, computer());
  return env;
}

/** A git project, its transcript, a connected Relay Everything folder, and the env a hook gets. */
export function project(lines = [said('you', 'Hello'), said('ai', 'Hi')], { connected = true, name = `${SESSION}.jsonl` } = {}) {
  const home = mkdtempSync(join(tmpdir(), 'relay-plugin-'));
  const root = join(home, 'relay-ring');
  mkdirSync(join(root, '.git'), { recursive: true });
  const transcript = join(home, name);
  writeFileSync(transcript, `${lines.join('\n')}\n`);
  const env = { RELAY_EVERYTHING_HOME: join(home, 'relay-everything') };
  if (connected) writeComputer(env, computer());
  return {
    home, root, transcript, env, data: stateDir(env), store: openState(env),
    input: { session_id: SESSION, transcript_path: transcript, cwd: root, hook_event_name: 'Stop' },
    add: (...more) => appendFileSync(transcript, `${more.join('\n')}\n`),
  };
}

/** A hook's `start` that runs the send at once, in this process, so a test can wait for it. It starts no sync of the
 *  knowledge web and no build, which need git and their own server. */
export const inline = fetcher => (args, env) => (['sync', 'build'].includes(args[0]) ? undefined
  : run(args[0], args[1], { env, fetcher, wait: Number(args[2] ?? 0) }));

/** A page with its frontmatter. */
export const page = (title, summary, body = '', updated = '2026-11-10') =>
  `---\ntitle: ${title}\n${summary === undefined ? '' : `summary: ${summary}\n`}updated: ${updated}\n---\n# ${title}\n\n${body}\n`;

/** A made-up copy of a knowledge web, in `dir` or a new folder: the paths and texts it is given. */
export function copy(files, dir = mkdtempSync(join(tmpdir(), 'relay-copy-'))) {
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return dir;
}

/** A real git repository named WongOS with one commit, and a worktree of it named rural-horse elsewhere. */
export function repoWithWorktree() {
  const home = mkdtempSync(join(tmpdir(), 'relay-worktree-'));
  const main = join(home, 'WongOS');
  const copy = join(home, 'workspaces', 'rural-horse');
  const git = (args, cwd) => execFileSync('git', ['-c', 'user.name=Test', '-c', 'user.email=test@localhost', '-c', 'commit.gpgsign=false', ...args], { cwd, stdio: 'ignore' });
  mkdirSync(main);
  git(['init', '--quiet', '-b', 'main'], main);
  git(['commit', '--quiet', '--allow-empty', '-m', 'Start'], main);
  git(['worktree', 'add', '--quiet', '-b', 'rural-horse', copy], main);
  return { home, main, copy };
}

/** A bare repo standing in for the person's web in Artifacts, holding the two start pages. */
export function web({ format = '# The rules\n' } = {}) {
  const git = (args, cwd) => execFileSync('git', ['-c', 'user.name=Test', '-c', 'user.email=test@localhost', ...args], { cwd, stdio: 'ignore' });
  const root = mkdtempSync(join(tmpdir(), 'relay-web-'));
  const start = join(root, 'start');
  mkdirSync(start);
  git(['init', '--quiet', '-b', 'main'], start);
  writeFileSync(join(start, 'README.md'), '# Topics\n');
  writeFileSync(join(start, 'FORMAT.md'), format);
  git(['add', '-A'], start);
  git(['commit', '--quiet', '-m', 'Start'], start);
  const bare = join(root, 'p-ana.git');
  git(['clone', '--quiet', '--bare', start, bare], root);
  return bare;
}
