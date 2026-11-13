// Memory's copy in `memory/`: whether it runs in a folder, the variables its scripts get, and their runs from a hook,
// each in its own time limit. Its own commands go through `bin/memory.mjs`, which sets Relay Everything's profile.
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { readComputer, readState } from './config.mjs';
import { appOf } from './headless.mjs';
import { api, chatIds } from './server.mjs';
import { gitTop, projectRoot, savingOff } from './transcript.mjs';

const PLUGIN = fileURLToPath(new URL('..', import.meta.url));
export const PROFILE = join(PLUGIN, 'memory-profile.mjs');
export const COPY = join(PLUGIN, 'memory');
export const MEMORY_SCRIPT = join(COPY, 'scripts', 'memory.mjs');
export const WRAPPER = join(PLUGIN, 'bin', 'memory.mjs');
export const PLUGIN_SKILL = join(PLUGIN, 'skills', 'memory', 'SKILL.md');
/** Loaded before the copy's chat start: it turns off only memory's daily tidy. */
export const DAILY_OFF = join(PLUGIN, 'lib', 'daily-off.mjs');
export const OWN_MEMORY = 'this project has its own memory';
/** What a topic's lookup reads: its newest notes, and the chats its facts came from. */
export const LOOKUP = { notes: 5, facts: 10, chats: 3, tags: 3, wait: 5_000 };

/** Each hook's memory script, the time it gets, inside the hook's own limit in hooks.json, and a module loaded first. */
export const MEMORY_RUNS = {
  'session-start': { script: 'session-start.mjs', wait: 5_000, agent: true, preload: DAILY_OFF },
  prompt: { script: 'topic-match.mjs', wait: 3_000 },
  'before-edit': { script: 'before-edit.mjs', wait: 3_000 },
  'session-end': { script: 'session-end.mjs', wait: 5_000, agent: true },
};

const real = path => {
  try {
    return realpathSync(path);
  } catch {
    return resolve(path);
  }
};

/** Whether the project at `cwd` has WongStack's memory, or a memory profile was set before the plugin ran. */
export function ownMemory(cwd, env = process.env) {
  if (env.WONG_MEMORY_PROFILE && real(env.WONG_MEMORY_PROFILE) !== real(PROFILE)) return true;
  return [...new Set([gitTop(cwd), projectRoot(cwd)])].filter(top => existsSync(join(top, '.git')))
    .some(top => existsSync(join(top, '.claude', 'skills', 'memory')) || existsSync(join(top, '.agents', 'memory', 'profile.mjs')));
}

const savingIsOff = (env, cwd) => {
  try {
    return savingOff(readState(env), projectRoot(cwd), gitTop(cwd));
  } catch {
    return false;
  }
};

/** Why memory does not run in `cwd` now, in words, or null when it runs. */
export function whyOff(env, cwd, computer = readComputer(env)) {
  if (ownMemory(cwd, env)) return OWN_MEMORY;
  if (!computer) return 'this computer is not connected to Relay Everything; type /relay-connect';
  if (!computer.memory) return 'memory is off on this computer; type /relay-memory on';
  if (env.RELAY_SAVE === '0') return 'RELAY_SAVE is 0 where this app started';
  if (!existsSync(join(gitTop(cwd), '.git'))) return 'this folder is not in a git project';
  if (savingIsOff(env, cwd)) return 'saving to Relay Everything is off in this project; type /relay-saving on';
  return null;
}

/** `repo` when the project has its own memory, `on` when the copy runs, else `off`. */
export function memoryState(env, cwd, computer = readComputer(env)) {
  const why = whyOff(env, cwd, computer);
  return why === OWN_MEMORY ? 'repo' : why ? 'off' : 'on';
}

/** The copy's variables: Relay Everything's profile, and its background runs on, so a chat's capture runs on its own. */
export function memoryEnv(env) {
  const { WONG_MEMORY_NO_HEADLESS: _, ...rest } = env;
  return { ...rest, WONG_MEMORY_PROFILE: PROFILE };
}

/** The copy's words with the plugin's own command and skill, which set the profile, in place of the copy's paths. */
export function plugged(text) {
  return String(text).replaceAll(`node ${MEMORY_SCRIPT}`, `node "${WRAPPER}"`).replaceAll(join(COPY, 'SKILL.md'), PLUGIN_SKILL);
}

/** The text a hook adds: the session start's plain lines, or another script's JSON, each with the plugin's paths. */
function shaped(event, out) {
  const text = out.trim();
  if (!text) return '';
  if (event === 'session-start') return JSON.stringify({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: plugged(text) } });
  try {
    const { hookSpecificOutput: { hookEventName, additionalContext } } = JSON.parse(text);
    return additionalContext ? JSON.stringify({ hookSpecificOutput: { hookEventName, additionalContext: plugged(additionalContext) } }) : '';
  } catch {
    return '';
  }
}

/**
 * Runs the copy's script for one hook event with the hook's input, and answers what the hook prints. It stops the
 * script at its time limit; a stop or a failure prints nothing. The chat start runs with memory's daily tidy off.
 */
export function runMemory(event, input, env, { wait = MEMORY_RUNS[event].wait, copy = COPY } = {}) {
  const { script, agent, preload } = MEMORY_RUNS[event];
  const args = [...(preload ? ['--import', pathToFileURL(preload).href] : []), join(copy, 'scripts', script),
    ...(agent ? ['--agent', appOf(env, input?.transcript_path)] : [])];
  return new Promise(done => {
    let out = '';
    let child;
    try {
      child = spawn(process.execPath, args, { cwd: input.cwd, env: memoryEnv(env), stdio: ['pipe', 'pipe', 'ignore'] });
    } catch {
      done('');
      return;
    }
    const timer = setTimeout(() => child.kill('SIGKILL'), wait);
    child.stdout.on('data', part => { out += part; });
    child.on('error', () => {});
    child.on('close', code => {
      clearTimeout(timer);
      done(code === 0 ? shaped(event, out) : '');
    });
    child.stdin.on('error', () => {});
    child.stdin.end(JSON.stringify(input ?? {}));
  });
}

/** Memory's `pull` of a topic, from the folder `cwd`: `{ code, text }`. */
export function pullTopic(name, { env = process.env, cwd = process.cwd(), wait = 30_000 } = {}) {
  const result = spawnSync(process.execPath, [MEMORY_SCRIPT, 'pull', name], { cwd, env: memoryEnv(env), encoding: 'utf8', timeout: wait });
  return { code: result.status ?? 1, text: plugged(result.stdout ?? '') };
}

const cut = (text, most) => {
  const flat = String(text ?? '').replace(/\s+/g, ' ').trim();
  return flat.length > most ? `${flat.slice(0, most - 1).trimEnd()}…` : flat;
};

async function listOf(computer, path, query, key, { fetcher, wait }) {
  const { status, json } = await api(computer, path, { query, fetcher, wait });
  return status === 200 && Array.isArray(json?.[key]) ? json[key] : [];
}

/** One topic's lines: its newest notes, then the titles and summaries of the chats its facts came from. */
async function topicLookup(computer, tag, options) {
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const [notes, facts] = await Promise.all([
    listOf(computer, '/notes', { tag, limit: String(LOOKUP.notes), timezone }, 'notes', options),
    listOf(computer, '/memory', { tag, limit: String(LOOKUP.facts), timezone }, 'facts', options),
  ]);
  const chats = (await Promise.all(chatIds(facts).slice(0, LOOKUP.chats).map(async id => {
    const { status, json } = await api(computer, `/chats/${encodeURIComponent(id)}`, { query: { timezone }, ...options });
    return status === 200 && json ? { id, title: json.title, summary: json.saves?.[0]?.text } : null;
  }))).filter(Boolean);
  return [
    ...notes.length ? [`Relay Everything notes on ${tag}:`, ...notes.map(note =>
      `- ${cut(note.title || note.text, 100)} (${note.id}${note.recordedAt ? `, ${String(note.recordedAt).slice(0, 10)}` : ''})`)] : [],
    ...chats.length ? [`Relay Everything chats behind ${tag}'s facts:`, ...chats.map(chat =>
      `- ${cut(chat.title || 'A chat', 100)} (${chat.id})${chat.summary ? `: ${cut(chat.summary, 200)}` : ''}`)] : [],
  ];
}

/** The notes and chats on up to three topics, as lines, from the person's Relay Everything; a failure adds none. */
export async function notesAndChats(tags, { env = process.env, fetcher = fetch, wait = LOOKUP.wait } = {}) {
  const computer = readComputer(env);
  if (!computer) return [];
  try {
    return (await Promise.all([...new Set(tags)].slice(0, LOOKUP.tags).map(tag => topicLookup(computer, tag, { fetcher, wait })))).flat();
  } catch {
    return [];
  }
}
