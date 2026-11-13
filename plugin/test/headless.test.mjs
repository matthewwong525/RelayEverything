import assert from 'node:assert/strict';
import { test } from 'node:test';
import { appOf, buildCommand, childEnv, shellWord, STOP_AFTER } from '../lib/headless.mjs';

const COPY = '/home/ana/.config/relay-everything/knowledge';
const COMMAND = 'node /plugin/bin/build.mjs';
const AGENTS = { reader: { description: 'Reads.', prompt: 'Read.', tools: ['Read', 'Bash'] } };

test('Claude Code runs the build with its helpers, a narrow grant, the copy as its folder, and no hooks', () => {
  const [command, args] = buildCommand({ app: 'claude', prompt: 'Build.', model: 'haiku', command: COMMAND, agents: AGENTS, copy: COPY });
  assert.equal(command, 'claude');
  assert.deepEqual(args, ['-p', 'Build.', '--model', 'haiku', '--no-session-persistence', '--permission-mode', 'dontAsk',
    '--allowedTools', 'Read', 'Write', 'Edit', 'Glob', 'Grep', 'Task', 'Agent', 'Bash(node /plugin/bin/build.mjs:*)', '--add-dir', COPY,
    '--agents', JSON.stringify(AGENTS), '--settings', '{"disableAllHooks":true}']);
  assert.ok(!buildCommand({ app: 'claude', prompt: 'Build.', command: COMMAND, agents: AGENTS, copy: COPY })[1].includes('--model'));
  assert.equal(STOP_AFTER, 30 * 60_000);
});

test('Codex runs the build in its sandbox, with the network on and only the copy and the run folder to write', () => {
  const [command, args] = buildCommand({ app: 'codex', prompt: 'Build.', model: 'gpt-5-mini', command: COMMAND, copy: COPY,
    writable: [COPY, '/home/ana/.config/relay-everything/build'] });
  assert.equal(command, 'codex');
  assert.deepEqual(args, ['exec', '--ephemeral', '--skip-git-repo-check', '-m', 'gpt-5-mini', '--sandbox', 'workspace-write',
    '-c', 'sandbox_workspace_write.network_access=true',
    '-c', `sandbox_workspace_write.writable_roots=["${COPY}","/home/ana/.config/relay-everything/build"]`,
    '-c', 'approval_policy="never"', 'Build.']);
});

test('the app is the one the chat started in, and the child saves no chat and starts no build', () => {
  assert.equal(appOf({}, '/home/ana/.claude/projects/x/5d1c.jsonl'), 'claude');
  assert.equal(appOf({}, '/home/ana/.codex/sessions/2026/11/10/rollout-2026-11-10T09-00-00-5d1c.jsonl'), 'codex');
  assert.equal(appOf({ CODEX_THREAD_ID: '5d1c' }), 'codex');
  // CODEX_HOME set in the shell does not make a Claude Code chat a Codex one.
  assert.equal(appOf({ CODEX_HOME: '/home/ana/.codex' }, '/home/ana/.claude/projects/x/5d1c.jsonl'), 'claude');
  assert.equal(appOf({ CODEX_HOME: '/home/ana/.codex' }), 'claude');
  // A plugin's folder no longer says which app: the copy runs from the project in both.
  assert.equal(appOf({ PLUGIN_ROOT: '/plugin' }), 'claude');
  assert.equal(appOf({}), 'claude');
  assert.deepEqual(childEnv({ HOME: '/home/ana', RELAY_SAVE: '1' }), { HOME: '/home/ana', RELAY_SAVE: '0', RELAY_BUILD_RUN: '1' });
});

test('a path goes in the command as one shell word, quoted only when it needs it', () => {
  assert.equal(shellWord('/plugin/bin/build.mjs'), '/plugin/bin/build.mjs');
  assert.equal(shellWord('/Users/Ana Lee/plugin/build.mjs'), '"/Users/Ana Lee/plugin/build.mjs"');
});
