// Run with: node --test mobile/device-check/*.test.mjs
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { endReason, main, readSession, readSteps, scenarioCount, stepsMarkdown } from './steps.mjs';

const SAMPLE = new URL('./steps.sample.json', import.meta.url).pathname;
const sample = JSON.parse(readFileSync(SAMPLE, 'utf8'));
const REPORT = `Scenario: Search
Verdict: works

Scenario: Settings
Verdict: not yet checked

Scenario: New note
Verdict: Not yet checked
`;

test('each tool call is one line with what it worked on, and a refused one says so', () => {
  const { steps, result } = readSteps(sample);
  assert.deepEqual(steps.map(step => [step.tool, step.end]),
    [['Read', ''], ['Bash', 'refused'], ['Write', ''], ['Bash', 'error'], ['Bash', 'no answer']]);
  assert.equal(steps[1].target, 'cat ~/.config/secret');
  assert.equal(steps[2].target, 'out/claude/flows/search.yaml', 'a file write shows its path, never its text');
  assert.equal(result.subtype, 'error_max_turns');
});

test('the log has the result line and no tool output', () => {
  const text = stepsMarkdown(readSteps(sample));
  assert.match(text, /^Result: error_max_turns, 81 turns, 754 s\.$/m);
  assert.match(text, /^2\. Bash: cat ~\/\.config\/secret \(refused\)$/m);
  assert.ok(!text.includes('File created successfully') && !text.includes('tapOn'));
});

test('a long or many-line command is cut to one line of 200 characters', () => {
  const long = [{ type: 'assistant', message: { content: [{ type: 'tool_use', id: 'x', name: 'Bash', input: { command: `echo a\n${'b'.repeat(300)}` } }] } }];
  const [step] = readSteps(long).steps;
  assert.equal(step.target.length, 200);
  assert.ok(step.target.startsWith('echo a \\n b'));
});

test('a refused call is found from its answer when no result came back', () => {
  const { steps, result } = readSteps(sample.slice(0, -1));
  assert.equal(result, null);
  assert.equal(steps[1].end, 'refused');
});

test('a failed command that names a permission is an error, not refused', () => {
  const ls = { type: 'assistant', message: { content: [{ type: 'tool_use', id: 'l1', name: 'Bash', input: { command: 'ls /private' } }] } };
  const denied = { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'l1', is_error: true,
    content: 'ls: /private: Permission denied' }] } };
  assert.equal(readSteps([...sample, ls, denied]).steps.at(-1).end, 'error', 'a result message lists every refusal');
  assert.equal(readSteps([ls, denied]).steps[0].end, 'error', 'with no result, only the refusal text counts');
});

test('the reason names out of turns, out of time, an error, refused commands, or no verdict', () => {
  const turns = { subtype: 'error_max_turns', is_error: true };
  const done = { subtype: 'success', is_error: false };
  assert.equal(endReason({ found: true, result: turns, refused: 3, maxTurns: 80 }),
    'Claude used all 80 turns before it wrote a verdict. 3 commands were refused.');
  assert.match(endReason({ found: false, result: null, refused: 0 }), /ran out of time/);
  assert.match(endReason({ found: true, result: null, refused: 1 }), /error.*1 command was refused\.$/);
  assert.match(endReason({ found: true, result: { subtype: 'error_during_execution', is_error: true }, refused: 0 }), /error_during_execution/);
  assert.equal(endReason({ found: true, result: done, refused: 4, verdict: '' }), 'Claude stopped with no verdict. 4 commands were refused.');
  assert.equal(endReason({ found: true, result: done, refused: 0, verdict: 'could-not-check' }), null);
  assert.equal(endReason({ found: true, result: done, refused: 2, verdict: 'works' }), null);
});

test('a stop mid-way is no verdict even when verdict.txt holds the first could-not-check', () => {
  assert.match(endReason({ found: true, result: { subtype: 'error_max_turns' }, refused: 0, maxTurns: 80, verdict: 'could-not-check' }), /80 turns/);
});

test('the report gives how many scenarios Claude checked', () => {
  assert.equal(scenarioCount(REPORT), '1 of 3 scenarios checked.');
  assert.equal(scenarioCount(''), 'No scenario was written in the report.');
});

// A Claude Code session file: one message per line, with more fields than the execution file, and a last line cut off.
function sessionFolder() {
  const sessions = mkdtempSync(join(tmpdir(), 'sessions-'));
  mkdirSync(join(sessions, '-Users-runner-work'));
  const lines = sample.filter(message => message.type === 'assistant' || message.type === 'user')
    .map(message => JSON.stringify({ ...message, sessionId: 's1', cwd: '/Users/runner/work', timestamp: '2026-11-08T10:00:00Z' }));
  writeFileSync(join(sessions, '-Users-runner-work', 'new.jsonl'), `${lines.join('\n')}\n{"type":"assistant","mess`);
  const old = join(sessions, '-Users-runner-work', 'old.jsonl');
  writeFileSync(old, `${JSON.stringify(sample[1])}\n`);
  utimesSync(old, new Date('2026-01-01'), new Date('2026-01-01'));
  return sessions;
}

test('with no execution file, the steps come from the newest session file', () => {
  const sessions = sessionFolder();
  assert.equal(readSession(sessions).length, 9, 'the cut-off last line is left out');
  assert.deepEqual(readSession(join(sessions, 'none')), []);
  const out = mkdtempSync(join(tmpdir(), 'steps-'));
  const done = main({ file: join(out, 'none.json'), out, maxTurns: 80, sessions });
  assert.equal(done.steps, 5);
  assert.match(done.reason, /^Claude ran out of time.* 1 command was refused\. Claude wrote no report\.$/);
  const text = readFileSync(join(out, 'steps.md'), 'utf8');
  assert.match(text, /^Result: none\. Claude did not end on its own\.$/m);
  assert.match(text, /^2\. Bash: cat ~\/\.config\/secret \(refused\)$/m);
});

test('main writes steps.md always, and end.txt only when Claude gave no final verdict', () => {
  const out = mkdtempSync(join(tmpdir(), 'steps-'));
  writeFileSync(join(out, 'report.md'), REPORT);
  writeFileSync(join(out, 'verdict.txt'), 'could-not-check\n');
  const stopped = main({ file: SAMPLE, out, maxTurns: 80 });
  assert.equal(stopped.steps, 5);
  assert.match(readFileSync(join(out, 'steps.md'), 'utf8'), /^# Claude's steps/);
  assert.equal(readFileSync(join(out, 'end.txt'), 'utf8'),
    'Claude used all 80 turns before it wrote a verdict. 1 command was refused. 1 of 3 scenarios checked.\n');

  const fine = mkdtempSync(join(tmpdir(), 'steps-'));
  writeFileSync(join(fine, 'verdict.txt'), 'works\n');
  const file = join(fine, 'run.json');
  writeFileSync(file, JSON.stringify([...sample.slice(0, -1), { type: 'result', subtype: 'success', is_error: false, num_turns: 9, duration_ms: 1000 }]));
  assert.equal(main({ file, out: fine, maxTurns: 80 }).reason, null);

  const gone = mkdtempSync(join(tmpdir(), 'steps-'));
  assert.match(main({ file: join(gone, 'none.json'), out: gone, maxTurns: 80, sessions: join(gone, 'none') }).reason,
    /ran out of time.*Claude wrote no report\.$/);
  assert.match(readFileSync(join(gone, 'steps.md'), 'utf8'), /No tool calls\./);
});
