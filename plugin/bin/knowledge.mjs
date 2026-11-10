#!/usr/bin/env node
// This computer's copy of the person's knowledge web, in `knowledge/` in the Relay Everything folder: `sync` fetches
// the newest pages and sends this computer's changes; `status` says how the copy stands, with no network call.
// usage: node knowledge.mjs sync [--now] | status
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ensureHome, home, readComputer } from '../lib/config.mjs';
import { withSandbox } from '../lib/sandbox.mjs';
import { api, reason } from '../lib/server.mjs';
import { NOT_CONNECTED } from './relay.mjs';

/** A sync at most this often, unless the copy has changes of its own or the person asks: each sync costs operations. */
export const EVERY = 15 * 60_000;
export const NO_GIT = 'Git is not on this computer. Install git to keep a copy of your knowledge web.';
export const NOT_SET_UP = 'The knowledge web is not set up on your Relay Everything server, so this computer keeps no copy.';
const USAGE = 'Commands: sync [--now], status.';
// Commits made here name the computer; the address is not a real one, so no email goes to the server.
const AUTHOR = name => ['-c', `user.name=${name || 'Relay Everything'}`, '-c', 'user.email=knowledge@localhost'];

export const copyOf = env => join(home(env), 'knowledge');
const stateFile = env => join(home(env), 'knowledge.json');

function lastSync(env) {
  try {
    return JSON.parse(readFileSync(stateFile(env), 'utf8')).syncedAt ?? null;
  } catch {
    return null;
  }
}

/** Runs git in `cwd`; the pass goes only in this process's environment, never in an argument, a file or the remote. */
function git(args, { cwd, pass } = {}) {
  const env = { ...process.env, GIT_TERMINAL_PROMPT: '0', ...pass && {
    GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.extraHeader', GIT_CONFIG_VALUE_0: `Authorization: Bearer ${pass}` } };
  return execFileSync('git', args, { cwd, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

/** Whether git runs, on the PATH the caller gives. */
const hasGit = env => {
  try {
    execFileSync('git', ['--version'], { env: { ...process.env, PATH: env.PATH ?? process.env.PATH }, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
};

/** The copy's own changes: files not yet kept, and kept changes not yet sent. */
function ownChanges(dir) {
  if (git(['status', '--porcelain'], { cwd: dir })) return true;
  try {
    return git(['rev-list', '--count', '@{upstream}..HEAD'], { cwd: dir }) !== '0';
  } catch {
    return false;
  }
}

/** Joins the web's newest pages into the copy. A page both sides changed keeps both versions: text by joining
 *  the lines, any other file as this copy's, with the web's beside it as `<name>.other`. */
function joinWeb(dir, branch, author) {
  mkdirSync(join(dir, '.git', 'info'), { recursive: true });
  writeFileSync(join(dir, '.git', 'info', 'attributes'), '* merge=union\n');
  try {
    git([...author, 'merge', '--no-edit', `origin/${branch}`], { cwd: dir });
    return;
  } catch {
    // A file the line join could not take, such as a picture: keep both below.
  }
  for (const file of git(['diff', '--name-only', '--diff-filter=U'], { cwd: dir }).split('\n').filter(Boolean)) {
    try {
      git(['checkout', '--ours', '--', file], { cwd: dir });
      writeFileSync(join(dir, `${file}.other`), execFileSync('git', ['show', `:3:${file}`], { cwd: dir, stdio: ['ignore', 'pipe', 'ignore'] }));
    } catch {
      // One side deleted the file: the side that kept it stays.
    }
  }
  git(['add', '-A'], { cwd: dir });
  git([...author, 'commit', '--no-edit'], { cwd: dir });
}

/** Asks the server for a one-hour pass: `{ remote, token }`, or `{ line }` when it can not give one. */
async function askPass(computer, fetcher) {
  let answer;
  try {
    answer = await api(computer, '/knowledge/access', { body: {}, fetcher });
  } catch (error) {
    return { line: withSandbox(`Relay Everything at ${computer.api} could not be reached. Try again in a minute.`, error) };
  }
  const { status, json } = answer;
  if (status === 200 && typeof json?.remote === 'string' && typeof json?.token === 'string') return json;
  if (status === 501) return { line: NOT_SET_UP };
  const why = reason(json) ?? `It answered ${status}.`;
  if (status === 401 || status === 403) return { line: `Relay Everything refused this computer's key: ${why} Type /relay:connect to connect again.` };
  return { line: `Relay Everything refused the request: ${why}` };
}

/** Fetches, joins and sends, at most once every 15 minutes unless the copy changed or `now` is set. */
export async function sync({ env = process.env, fetcher = fetch, now = false, clock = Date.now } = {}) {
  if (!hasGit(env)) return { code: 1, lines: [NO_GIT] };
  const computer = readComputer(env);
  if (!computer) return { code: 1, lines: [NOT_CONNECTED] };
  const dir = copyOf(env);
  const made = existsSync(join(dir, '.git'));
  const synced = lastSync(env);
  if (made && !now && synced !== null && clock() - synced < EVERY && !ownChanges(dir)) {
    return { code: 0, lines: [`Your knowledge web in ${dir} is new enough: it synced ${Math.round((clock() - synced) / 60_000)} minutes ago.`] };
  }
  const pass = await askPass(computer, fetcher);
  if (pass.line) return { code: 1, lines: [pass.line] };
  const author = AUTHOR(computer.name);
  try {
    if (!made) {
      ensureHome(env);
      git(['clone', '--quiet', pass.remote, dir], { pass: pass.token });
    } else {
      git(['remote', 'set-url', 'origin', pass.remote], { cwd: dir });
      git(['add', '-A'], { cwd: dir });
      if (git(['status', '--porcelain'], { cwd: dir })) git([...author, 'commit', '--quiet', '-m', `Changes from ${computer.name || 'this computer'}`], { cwd: dir });
      const branch = git(['symbolic-ref', '--short', 'HEAD'], { cwd: dir });
      for (let tries = 1; ; tries++) {
        git(['fetch', '--quiet', 'origin'], { cwd: dir, pass: pass.token });
        joinWeb(dir, branch, author);
        if (git(['rev-list', '--count', `origin/${branch}..HEAD`], { cwd: dir }) === '0') break;
        try {
          git(['push', '--quiet', 'origin', `HEAD:${branch}`], { cwd: dir, pass: pass.token });
          break;
        } catch (error) {
          // Another computer sent between the fetch and the push: fetch and join once more.
          if (tries === 2) throw error;
        }
      }
    }
  } catch (error) {
    const said = String(error?.stderr ?? error?.message ?? '').split(pass.token).join('<pass>').trim().split('\n').at(-1);
    return { code: 1, lines: [`The knowledge web could not sync: ${said}`] };
  }
  mkdirSync(home(env), { recursive: true });
  writeFileSync(stateFile(env), JSON.stringify({ syncedAt: clock() }), { mode: 0o600 });
  return { code: 0, lines: [`Your knowledge web is synced in ${dir}.`] };
}

/** Where the copy is, when it last synced, and whether it has changes to send. */
export function status({ env = process.env, clock = Date.now } = {}) {
  const dir = copyOf(env);
  if (!existsSync(join(dir, '.git'))) return { code: 0, lines: ['This computer has no copy of your knowledge web yet. Run sync to get one.'] };
  const synced = lastSync(env);
  return { code: 0, lines: [
    `Your knowledge web is in ${dir}.`,
    synced === null ? 'It has not synced yet.' : `It last synced ${Math.round((clock() - synced) / 60_000)} minutes ago.`,
    hasGit(env) && ownChanges(dir) ? 'It has changes that the next sync sends.' : 'It has no changes to send.'] };
}

export async function knowledge(args, options = {}) {
  if (args[0] === 'sync') return sync({ ...options, now: args.includes('--now') });
  if (args[0] === 'status') return status(options);
  return { code: 2, lines: [USAGE] };
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const { code, lines } = await knowledge(process.argv.slice(2));
  console.log(lines.join('\n'));
  process.exitCode = code;
}
