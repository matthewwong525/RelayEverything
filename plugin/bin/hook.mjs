#!/usr/bin/env node
// Claude Code's and Codex's hooks call this: `hook.mjs session-start|stop|session-end|prompt` with the hook's JSON on
// stdin. Each records the session, starts a send that runs on its own, and ends at once, so neither app waits: Codex
// does not run a hook marked async. The send is `hook.mjs send <session> <wait ms>`, or `hook.mjs pending` at a start.
// A start on a connected computer also adds the person's topics from the copy of their knowledge web, and starts
// `hook.mjs sync` to bring the copy up to date on its own; the first start of the day starts the daily build instead,
// which syncs first. `prompt` adds the topics a message names. Otherwise it prints nothing but one notice, once, when
// this computer is not connected, because a hook's output joins the chat.
import { spawn } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { copyOf, openState, readComputer } from '../lib/config.mjs';
import { appOf } from '../lib/headless.mjs';
import { sendPending, sendSession } from '../lib/send.mjs';
import { SESSION } from '../lib/state.mjs';
import { matchTopics, projectTopic, readTopic, topicPages, topLevel } from '../lib/topics.mjs';
import { gitTop, projectName, projectRoot } from '../lib/transcript.mjs';
import { buildDue, markTried, startRun } from './build.mjs';
import { sync } from './knowledge.mjs';
import { computerZone } from './relay.mjs';

const self = fileURLToPath(import.meta.url);
// The send a session's end starts runs on its own, outside the hook's time limit, so it can wait for a Stop send.
export const END_WAIT = 60_000;
export const NOT_CONNECTED = 'Relay Everything: this computer is not connected, so chats are not saved. '
  + 'Type /relay:connect to connect it. This shows once.';
/** The most topic lines a start adds, and the longest line. */
export const MOST_TOPICS = 40;
export const LINE_CHARACTERS = 80;
const RELAY = fileURLToPath(new URL('./relay.mjs', import.meta.url));

/** Text the app adds to the AI's context for this event, in the shape Claude Code and Codex both read. */
const context = (hookEventName, lines) => (lines.length
  ? JSON.stringify({ hookSpecificOutput: { hookEventName, additionalContext: lines.join('\n') } }) : '');

/** One topic as a line: its name and its summary, cut to LINE_CHARACTERS. */
const topicLine = (name, summary, width = name.length) =>
  (summary ? `${name.padEnd(width)}  ${summary}` : name).replace(/\s+$/, '').slice(0, LINE_CHARACTERS);

/**
 * The lines a chat starts with: the top-level topics, at most MOST_TOPICS, the newest `updated` kept past that; the
 * project's own topic, when the list does not show it; and how to pull one. No topics: no lines.
 */
export function topicList(dir, project) {
  let topics = topLevel(dir);
  if (topics.length > MOST_TOPICS) {
    const kept = new Set([...topics].sort((a, b) => String(b.updated ?? '').localeCompare(String(a.updated ?? '')))
      .slice(0, MOST_TOPICS).map(topic => topic.name));
    topics = topics.filter(topic => kept.has(topic.name));
  }
  // The project's topic gets its own line only when the list does not already show it.
  const found = projectTopic(dir, project);
  const own = found && !topics.some(topic => topic.name === found.name) ? found : null;
  if (!topics.length && !own) return [];
  const width = Math.min(Math.max(0, ...topics.map(topic => topic.name.length)), 24);
  return ['Relay Everything topics, from your knowledge web:', ...topics.map(topic => topicLine(topic.name, topic.summary, width)),
    ...own ? [topicLine(`This project's topic: ${own.name}`, own.summary)] : [],
    `Pull a topic with its links, facts, notes and chats: node "${RELAY}" topic <name>`];
}

/** The lines a message adds: each topic it names, a clear one with its summary, a weak one by name only. */
export function topicMatches(dir, message) {
  const pages = topicPages(dir);
  return matchTopics([...pages.keys()], message).map(({ name, clear }) => {
    if (!clear) return `Relay Everything topic ${name} may be what this message names.`;
    const summary = readTopic(dir, name, pages)?.summary;
    return `Relay Everything topic ${name}: ${summary ?? 'it has no summary yet.'}`.slice(0, LINE_CHARACTERS * 2);
  });
}

/** Notes where a session's transcript is, and its project. */
export function record(store, input, now = Date.now()) {
  const id = String(input.session_id ?? '');
  if (!SESSION.test(id) || typeof input.transcript_path !== 'string' || typeof input.cwd !== 'string') return null;
  const root = projectRoot(input.cwd);
  store.update(id, { transcript: input.transcript_path, cwd: input.cwd, root, top: gitTop(input.cwd), project: projectName(root), seen: now });
  return id;
}

/**
 * Runs one hook event, and answers what to print. `start` runs a send on its own, as `hook.mjs <args>`. A session
 * ended by /clear is marked cleared, so the save skill, which may keep its old id, finds the chat that follows.
 */
export async function run(event, input, { env, fetcher = fetch, start = startSend, wait = END_WAIT, now = Date.now(), zone = computerZone() }) {
  // Topics only read this computer's copy, so a project with saving off, or RELAY_SAVE=0, still gets them.
  if (event === 'prompt') return readComputer(env) ? context('UserPromptSubmit', topicMatches(copyOf(env), input?.prompt)) : '';
  if (event === 'sync') {
    await sync({ env, fetcher });
    return '';
  }
  const topics = () => (typeof input?.cwd === 'string' ? context('SessionStart', topicList(copyOf(env), projectName(projectRoot(input.cwd)))) : '');
  if (env.RELAY_SAVE === '0') return event === 'session-start' && readComputer(env) ? topics() : '';
  const store = openState(env);
  if (event === 'send') {
    await sendSession(input, { env, store, fetcher, wait });
    return '';
  }
  if (event === 'pending') {
    await sendPending({ env, store, fetcher });
    return '';
  }
  const id = record(store, input);
  if (event === 'session-start') {
    // A cleared chat that you resume is this chat again.
    if (id && store.sessions()[id]?.cleared) store.update(id, { cleared: false });
    if (Object.values(store.sessions()).some(session => session.pending)) await start(['pending'], env);
    if (readComputer(env)) {
      // The build syncs first, so a second sync at once would race it for the copy.
      if (!env.RELAY_BUILD_RUN && buildDue(env, now, zone)) {
        markTried(env, now, zone);
        await start(['build', appOf(env, input?.transcript_path)], env);
      } else await start(['sync'], env);
      return topics();
    }
    if (store.marked('not-connected')) return '';
    store.mark('not-connected');
    return JSON.stringify({ systemMessage: NOT_CONNECTED });
  }
  if (event === 'stop' && id) await start(['send', id, '0'], env);
  else if (event === 'session-end' && id) {
    if (input.reason === 'clear') store.update(id, { cleared: true });
    await start(['send', id, String(END_WAIT)], env);
  }
  return '';
}

function startSend(args, env) {
  if (args[0] === 'build') return startRun(env, args[1]);
  spawn(process.execPath, [self, ...args], { detached: true, stdio: 'ignore', env }).unref();
}

async function stdin() {
  let text = '';
  for await (const part of process.stdin) text += part;
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const [event, session, wait] = process.argv.slice(2);
  try {
    const own = event === 'send' || event === 'pending' || event === 'sync';
    const said = await run(event, own ? session : await stdin(), { env: process.env, wait: Number(wait ?? END_WAIT) || 0 });
    if (said) console.log(said);
  } catch {
    // A hook never stops the app: the next start sends what this one could not.
  }
}
