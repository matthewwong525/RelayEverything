import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { record } from '../bin/hook.mjs';
import { codexPrompt, helpers, USAGE } from '../bin/build.mjs';
import { ago, run, saving } from '../bin/saving.mjs';
import { forgetComputer, openState, readState } from '../lib/config.mjs';
import { sendSession } from '../lib/send.mjs';
import { fakeServer, project, repoWithWorktree, SESSION } from './fake.mjs';

const bin = name => fileURLToPath(new URL(`../bin/${name}`, import.meta.url));
const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('/relay-saving turns a project off and on, and says which it is', () => {
  const place = project();
  const say = (choice, env = place.env) => saving(place.store, place.root, choice, env);
  assert.deepEqual(say(undefined), [
    'Saving to Relay Everything is on for relay-ring.',
    'Each chat here goes to your Relay Everything server as you talk, from Claude Code or Codex. Type /relay-saving off to stop.',
    'No chat from this project has gone to Relay Everything yet.']);
  assert.deepEqual(say('off').slice(0, 2), [
    'Saving to Relay Everything is off for relay-ring.', 'Chats in this project stay on this computer. Type /relay-saving on to save them again.']);
  assert.equal(place.store.isOff(place.root), true);
  assert.equal(say('on')[0], 'Saving to Relay Everything is on for relay-ring.');
  assert.equal(place.store.isOff(place.root), false);
  assert.deepEqual(say('maybe'), ['Type /relay-saving on, /relay-saving off, or /relay-saving to see which it is.']);
  assert.match(say(undefined, { ...place.env, RELAY_SAVE: '0' }).at(-1), /RELAY_SAVE is 0/);
  forgetComputer(place.env);
  assert.equal(say(undefined).at(-1), 'This computer is not connected, so no chat is saved now. Type /relay-connect to connect it.');
  // As the skill runs it: in the project, with the Relay Everything folder from the env.
  const printed = execFileSync(process.execPath, [bin('saving.mjs'), 'off'], { cwd: place.root, env: { ...process.env, ...place.env }, encoding: 'utf8' });
  assert.match(printed, /^Saving to Relay Everything is off for relay-ring\.\n/);
  assert.equal(place.store.isOff(place.root), true);
});

test('/relay-saving only looks where it can not write, and says so when asked to change', () => {
  const place = project();
  place.store.setOff(place.root, true);
  // A look reads the state with no folder made or changed.
  assert.equal(saving(readState(place.env), place.root, undefined, place.env)[0], 'Saving to Relay Everything is off for relay-ring.');
  // A file where the folder should be: openState fails, as it does in a read-only sandbox.
  const env = { RELAY_EVERYTHING_HOME: join(place.transcript, 'relay-everything') };
  const look = run(undefined, { env, cwd: place.root });
  assert.equal(look.code, 0);
  assert.equal(look.lines[0], 'Saving to Relay Everything is on for relay-ring.');
  assert.equal(run('maybe', { env, cwd: place.root }).lines[0], 'Type /relay-saving on, /relay-saving off, or /relay-saving to see which it is.');
  assert.deepEqual(run('off', { env, cwd: place.root }), { code: 1,
    lines: [`The folder ${env.RELAY_EVERYTHING_HOME} could not be written, so saving did not change.`] });
  assert.equal(run('on', { env: place.env, cwd: place.root }).code, 0);
  assert.equal(place.store.isOff(place.root), false);
});

test('/relay-saving off in a repository holds in each worktree of it, made before or after, and names the repository', async () => {
  const place = project();
  const { main, copy } = repoWithWorktree();
  assert.equal(saving(place.store, main, 'off', place.env)[0], 'Saving to Relay Everything is off for WongOS.');
  assert.equal(saving(place.store, copy, undefined, place.env)[0], 'Saving to Relay Everything is off for WongOS.');
  // A chat in a new worktree records the repository, and nothing from it is sent.
  const input = { ...place.input, cwd: copy };
  record(place.store, input);
  assert.deepEqual([place.store.sessions()[SESSION].root, place.store.sessions()[SESSION].project], [main, 'WongOS']);
  const server = fakeServer();
  assert.equal(await sendSession(SESSION, { env: place.env, store: place.store, fetcher: server.fetch }), 'off');
  assert.equal(server.calls.length, 0);
  // On from the worktree turns it on for the repository, and a chat there is sent under its name.
  assert.equal(saving(place.store, copy, 'on', place.env)[0], 'Saving to Relay Everything is on for WongOS.');
  assert.equal(await sendSession(SESSION, { env: place.env, store: place.store, fetcher: server.fetch }), 'sent');
  assert.equal(server.calls[0].body.project, 'WongOS');
  // An entry made for the worktree alone, before worktrees counted as their repository, still holds until turned on.
  const older = openState(place.env);
  older.setOff(copy, true);
  assert.equal(saving(older, copy, undefined, place.env)[0], 'Saving to Relay Everything is off for WongOS.');
  assert.equal(await sendSession(SESSION, { env: place.env, store: older, fetcher: server.fetch }), 'off');
  saving(older, copy, 'on', place.env);
  assert.equal(older.isOff(copy), false);
});

test('/relay-saving says when the project last sent a chat: the newest send of its sessions, not another project\'s', async () => {
  const place = project();
  const server = fakeServer();
  record(place.store, place.input);
  const sentAt = Date.now();
  assert.equal(await sendSession(SESSION, { env: place.env, store: place.store, fetcher: server.fetch, now: () => sentAt }), 'sent');
  assert.equal(place.store.sessions()[SESSION].sentAt, sentAt);
  // A send with nothing new leaves the time as it was.
  assert.equal(await sendSession(SESSION, { env: place.env, store: place.store, fetcher: server.fetch, now: () => sentAt + 1 }), 'sent');
  assert.equal(place.store.sessions()[SESSION].sentAt, sentAt);
  place.store.update('older-session-01', { root: place.root, sentAt: sentAt - 3_600_000, seen: sentAt });
  place.store.update('elsewhere-sess-01', { root: place.home, sentAt: sentAt + 60_000, seen: sentAt });
  assert.equal(saving(place.store, place.root, undefined, place.env, sentAt + 5 * 60_000).at(-1), 'This project last sent a chat to Relay Everything 5 minutes ago.');
  assert.deepEqual([ago(0, 30_000), ago(0, 60_000), ago(0, 3 * 3_600_000), ago(0, 3 * 86_400_000)],
    ['less than a minute ago', '1 minute ago', '3 hours ago', '3 days ago']);
});

test('each skill is relay-<name> and runs its own script from the project\'s copy', () => {
  for (const [skill, script] of [['connect', 'bin/connect.mjs'], ['ask', 'bin/relay.mjs'], ['save', 'bin/save.mjs'], ['saving', 'bin/saving.mjs'],
    ['build', 'bin/build.mjs'], ['memory', 'bin/memory.mjs'], ['update', 'update.mjs']]) {
    const text = read(`skills/${skill}/SKILL.md`);
    assert.match(text, new RegExp(`^---\\nname: relay-${skill}\\ndescription: .*Relay Everything`), skill);
    assert.match(text, new RegExp(`/relay-${skill}\\b`), `${skill} names its command`);
    assert.ok(text.includes(`node "$(git rev-parse --show-toplevel)/.agents/relay/${script}"`), skill);
    assert.ok(text.includes("Each command runs Relay Everything's copy in this project, `.agents/relay/`."), skill);
    assert.ok(text.includes('**In Codex, run each command here outside the sandbox.** Ask for escalated permissions'), skill);
    // The plugin offers the same skills: with no copy in the project, each runs the plugin's own script, and only
    // `/relay:move`, on the person's ask, installs the copy.
    for (const gone of ['CLAUDE_PLUGIN_ROOT', '/relay:']) assert.ok(!text.replaceAll('`/relay:move`', '').includes(gone), `${skill} has no ${gone}`);
    assert.ok(text.includes('Never install the copy unless the person asks'), `${skill} installs nothing unasked`);
    if (skill !== 'update') {
      assert.ok(text.includes('When that folder is missing, this is the Relay Everything plugin: in each command, put the folder two levels above '
        + 'this file in place of `$(git rev-parse --show-toplevel)/.agents/relay`.'), `${skill} runs the plugin's script with no copy`);
    }
    if (skill !== 'memory') assert.ok(text.length < (skill === 'ask' ? 6200 : 4000), `${skill} stays short`);
  }
  // No skill sends the AI to the install page: the copy is installed only when the person asks.
  for (const entry of readdirSync(new URL('../skills/', import.meta.url))) {
    assert.ok(!read(`skills/${entry}/SKILL.md`).includes('relayeverything.com/install'), `${entry} does not install unasked`);
  }
  assert.match(read('skills/update/SKILL.md'), /there is no copy to update: tell the person that `\/relay:move` moves Relay Everything into this project, and stop\./);
  // The move skill is the plugin's own: it runs the plugin's install, and the copy leaves it out.
  const move = read('skills/move/SKILL.md');
  assert.match(move, /^---\nname: move\ndescription: .*Relay Everything/);
  for (const part of ['node "${CLAUDE_PLUGIN_ROOT}/install.mjs" --into "$(git rev-parse --show-toplevel)"', 'claude plugin uninstall relay@relay',
    'codex plugin remove relay@relay', 'Only on a yes']) assert.ok(move.includes(part), part);
  // The update applies only on a yes, and walks each clash with three choices.
  const update = read('skills/update/SKILL.md');
  for (const part of ['update.mjs" check', 'update.mjs" plan', 'update.mjs" show <path>', 'update.mjs" apply --choose <path>=mine',
    '*keep mine*', "*keep the release's*", '*keep both*', 'Never run `apply` without the person\'s yes']) assert.ok(update.includes(part), part);
  const ask = read('skills/ask/SKILL.md');
  assert.match(ask, /this computer's time zone/);
  // The skill names each command relay.mjs takes, and its usage line names each one the skill lists.
  const usage = /^const USAGE = ([\s\S]*?);$/m.exec(read('bin/relay.mjs'))[1];
  for (const command of ['me', 'notes', 'note', 'day', 'health', 'nights', 'workouts', 'places', 'points', 'calendar', 'chats', 'chat',
    'around', 'topic', 'add-note', 'facts', 'fact', 'add-facts', 'columns', 'change-columns', 'tag']) {
    assert.ok(ask.includes(`\`${command} `) || ask.includes(`\`${command}\``), `ask names ${command}`);
    assert.match(usage, new RegExp(`[ ']${command}[ ,.]`), `usage names ${command}`);
  }
  for (const part of ['Start from your topics', 'Follow the threads']) assert.ok(ask.includes(part), part);
  assert.match(ask, /^description: .*what was I doing when.*where was I.*what did I decide about/m);
  assert.ok(read('skills/save/SKILL.md').includes('--session "${CLAUDE_SESSION_ID}"'));
});

test('the plugin\'s hooks run in Claude Code and Codex: no async hook, a short end, and the plugin\'s folder in each command', () => {
  const { hooks } = JSON.parse(read('hooks/hooks.json'));
  assert.deepEqual(Object.keys(hooks), ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'Stop', 'SessionEnd']);
  const events = { SessionStart: 'session-start', UserPromptSubmit: 'prompt', PreToolUse: 'before-edit', Stop: 'stop', SessionEnd: 'session-end' };
  for (const [event, groups] of Object.entries(hooks)) {
    const [hook] = groups.flatMap(group => group.hooks);
    assert.equal(hook.async, undefined, `${event}: Codex does not run an async hook`);
    assert.equal(hook.command, `node "\${CLAUDE_PLUGIN_ROOT}/bin/hook.mjs" ${events[event]}`);
  }
  // Memory's end gets its own 5 seconds in Claude Code; Codex keeps an end to 3 seconds, after the send has started.
  assert.equal(hooks.SessionEnd[0].hooks[0].timeout, 8);
  // An edit in either app: Claude Code's edit tools, and Codex's apply_patch.
  assert.deepEqual(hooks.PreToolUse[0].matcher.split('|'), ['Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'apply_patch']);
  const manifest = JSON.parse(read('.claude-plugin/plugin.json'));
  assert.equal(manifest.version, '0.7.0');
  assert.equal(read('VERSION'), '0.8.0\n');
  assert.equal(manifest.userConfig, undefined);
  assert.match(manifest.description, /Claude Code/);
  assert.match(manifest.description, /Codex/);
});

test('/relay-build maps off, on, now and nothing to its commands', () => {
  const text = read('skills/build/SKILL.md');
  for (const command of ['status', 'off', 'on', 'now']) assert.ok(text.includes(`bin/build.mjs" ${command}\n`), command);
  assert.match(text, /^argument-hint: "\[off\|on\|now\]"$/m);
});

test('the build\'s prompts name only build.mjs commands that exist, stay short, and become the helpers and Codex\'s prompt', () => {
  const commands = new Set([...USAGE.matchAll(/(?:^Commands: |, )([a-z-]+)/g)].map(found => found[1]));
  for (const name of ['PROMPT.md', 'reader.md', 'gardener.md', 'CODEX.md']) {
    const text = read(`build/${name}`);
    assert.ok(text.length < 6000, `${name} stays under 6000 characters`);
    const named = [...text.matchAll(/\{\{build\}\} ([a-z-]+)/g)].map(found => found[1]);
    for (const command of named) assert.ok(commands.has(command), `${name} names ${command}`);
    // Claude Code's narrow grant refuses a heredoc or `<` that holds JSON, so the facts go as one argument.
    assert.doesNotMatch(text, /\{\{build\}\} [^`\n]*<</, `${name} sends no heredoc`);
    // relay.mjs shows only to say that FORMAT.md's commands go through build.mjs.
    assert.doesNotMatch(text.replaceAll('Where it names `relay.mjs`', ''), /relay\.mjs/, name);
  }
  const shape = helpers('node /plugin/bin/build.mjs');
  assert.deepEqual(Object.keys(shape), ['reader', 'gardener']);
  assert.deepEqual(shape.reader.tools, ['Read', 'Grep', 'Glob', 'Bash']);
  assert.ok(shape.gardener.tools.includes('Write'));
  assert.ok(shape.reader.prompt.includes('node /plugin/bin/build.mjs check-facts') && !shape.reader.prompt.includes('{{build}}'));
  const codex = codexPrompt('node /plugin/bin/build.mjs');
  for (const part of ['node /plugin/bin/build.mjs work', '# Read chats and notes into facts', '# Write and tidy the topic pages']) assert.ok(codex.includes(part), part);
});
