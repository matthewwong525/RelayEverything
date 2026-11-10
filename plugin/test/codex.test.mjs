import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { isCodexRollout, readCodexChat, stepLines } from '../lib/codex.mjs';
import { readAnyChat } from '../lib/send.mjs';

// A made-up rollout in the shape Codex 0.159 writes: every text, path and id in it is invented.
const fixture = readFileSync(new URL('fixtures/codex-rollout.jsonl', import.meta.url), 'utf8');
const claude = readFileSync(new URL('fixtures/chat.jsonl', import.meta.url), 'utf8');
const CWD = '/home/sam/relay-ring';
const at = second => Date.parse('2026-11-04T14:00:00.000Z') + second * 1000;

test('tells a Codex rollout from a Claude Code transcript by its first line', () => {
  assert.equal(isCodexRollout(fixture), true);
  assert.equal(isCodexRollout(claude), false);
  assert.equal(isCodexRollout(''), false);
  assert.equal(isCodexRollout('{'), false);
  assert.equal(readAnyChat(fixture, { cwd: CWD }).app, 'codex');
  assert.equal(readAnyChat(claude, { cwd: CWD }).app, 'claude-code');
});

test('keeps what you typed, the AI text and one line per step, word for word, numbered from 0', () => {
  const chat = readCodexChat(fixture, { cwd: CWD });
  assert.deepEqual(chat.messages, [
    { seq: 0, role: 'you', text: 'How thick should the stiffener be?', at: at(1) },
    { seq: 1, role: 'ai', text: 'Let me look at the board.', at: at(4) },
    { seq: 2, role: 'step', text: 'Ran: sed -n 1,40p pcb/relay.kicad_pcb', at: at(5) },
    { seq: 3, role: 'step', text: 'Ran: npm test', at: at(5) },
    { seq: 4, role: 'step', text: 'Ran: git status', at: at(8) },
    { seq: 5, role: 'step', text: 'Ran: ls pcb', at: at(9) },
    { seq: 6, role: 'step', text: 'Edited pcb/notes.md', at: at(10) },
    { seq: 7, role: 'step', text: 'Wrote docs/stiffener.md', at: at(10) },
    { seq: 8, role: 'step', text: 'Used spawn_agent', at: at(11) },
    { seq: 9, role: 'ai', text: '0.2 mm steel is enough for a ring this size.\n\nGlue it under the battery.', at: at(14) },
    { seq: 10, role: 'you', text: 'Here is the board\n[image]', at: at(21) },
    { seq: 11, role: 'ai', text: 'The board looks fine.', at: at(24) },
  ]);
  assert.equal(chat.title, 'How thick should the stiffener be?');
  assert.equal(chat.startedAt, at(1));
  assert.equal(chat.hasYou, true);
  // Reasoning, tool output, added context, a skill's text, developer text and a helper's message never appear.
  assert.doesNotMatch(JSON.stringify(chat), /12 mm wide|42 tests|nothing to commit|environment_context|project rules|skill text|developer text|helper's own|base instructions|bWFkZS11cA/);
});

test('numbers the same file the same way every time, and a longer file only adds', () => {
  const lines = fixture.split('\n');
  const shorter = readCodexChat(lines.slice(0, 12).join('\n'), { cwd: CWD }).messages;
  assert.ok(shorter.length > 2);
  assert.deepEqual(readCodexChat(fixture, { cwd: CWD }).messages.slice(0, shorter.length), shorter);
});

test('hides before it cuts, and a helper agent\'s own rollout gives no messages', () => {
  const chat = readCodexChat(fixture, { cwd: CWD, hide: text => text.replaceAll('stiffener', '[hidden]') });
  assert.equal(chat.messages[0].text, 'How thick should the [hidden] be?');
  assert.equal(chat.title, 'How thick should the [hidden] be?');
  const [meta, ...rest] = fixture.split('\n');
  const parsed = JSON.parse(meta);
  const helper = JSON.stringify({ ...parsed, payload: { ...parsed.payload, source: { subagent: { thread_spawn: { parent_thread_id: 'made-up' } } } } });
  assert.deepEqual(readCodexChat([helper, ...rest].join('\n'), { cwd: CWD }), { title: '', startedAt: null, messages: [], hasYou: false });
});

test('a chat with only added context has nothing you typed', () => {
  const lines = fixture.split('\n').slice(0, 6).join('\n');
  assert.equal(readCodexChat(lines, { cwd: CWD }).hasYou, false);
});

test('a typed tag stays: only Codex\'s own wrapped blocks are dropped', () => {
  const line = text => JSON.stringify({ timestamp: '2026-11-04T14:00:00.000Z', type: 'response_item',
    payload: { type: 'message', role: 'user', content: [{ type: 'input_text', text }] } });
  const chat = readCodexChat([line('<div>Keep me</div>'), line('<made_up_context>drop</made_up_context>'), line('<turn_aborted>x</turn_aborted>')].join('\n'), {});
  assert.deepEqual(chat.messages.map(message => message.text), ['<div>Keep me</div>']);
});

test('names each kind of tool call by its command, files or name, never its output', () => {
  const step = item => stepLines(item, CWD);
  assert.deepEqual(step({ type: 'function_call', name: 'shell', arguments: JSON.stringify({ command: ['bash', '-lc', 'npm run lint'] }) }), ['Ran: npm run lint']);
  assert.deepEqual(step({ type: 'function_call', name: 'shell', arguments: JSON.stringify({ command: ['ls', '-la'] }) }), ['Ran: ls -la']);
  assert.deepEqual(step({ type: 'function_call', name: 'exec_command', arguments: '{' }), ['Ran: ']);
  assert.deepEqual(step({ type: 'custom_tool_call', name: 'exec', input: 'tools.view_image({path:"a.png"}); tools.write_stdin({});' }), ['Used view_image']);
  assert.deepEqual(step({ type: 'custom_tool_call', name: 'exec', input: 'const x = 1;' }), ['Ran code']);
  assert.deepEqual(step({ type: 'custom_tool_call', name: 'exec', input: `tools.exec_command({cmd:'echo "a}b"'})` }), ['Ran: echo "a}b"']);
  assert.deepEqual(step({ type: 'custom_tool_call', name: 'exec', input: 'tools.apply_patch("*** Begin Patch\\n*** Delete File: old.txt\\n*** End Patch")' }), ['Deleted old.txt']);
  assert.deepEqual(step({ type: 'custom_tool_call', name: 'web_search' }), ['Used web_search']);
  assert.deepEqual(step({ type: 'local_shell_call', action: { command: ['git', 'log', '-1'] } }), ['Ran: git log -1']);
});
