import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { cut, gitTop, MESSAGE_CHARACTERS, projectName, projectRoot, readChat, stepLine, transcriptText } from '../lib/transcript.mjs';
import { repoWithWorktree } from './fake.mjs';

const fixture = readFileSync(new URL('fixtures/chat.jsonl', import.meta.url), 'utf8');
const CWD = '/home/sam/relay-ring';
const at = second => Date.parse('2026-11-04T14:00:00.000Z') + second * 1000;
const line = (type, content, more = {}) => JSON.stringify({ type, timestamp: '2026-11-04T14:00:00.000Z', message: { role: type, content }, ...more });

test('keeps what you typed, the AI text and one line per step, word for word, numbered from 0', () => {
  const chat = readChat(fixture, { cwd: CWD });
  assert.deepEqual(chat.messages, [
    { seq: 0, role: 'you', text: 'How thick should the stiffener be?', at: at(0) },
    { seq: 1, role: 'ai', text: 'Let me look at the board.', at: at(6) },
    { seq: 2, role: 'step', text: 'Read pcb/relay.kicad_pcb', at: at(7) },
    { seq: 3, role: 'step', text: 'Ran: npm test', at: at(9) },
    { seq: 4, role: 'you', text: '/plan the stiffener', at: at(13) },
    { seq: 5, role: 'you', text: 'Here is the board\n[image]', at: at(14) },
    { seq: 6, role: 'ai', text: '0.2 mm steel is enough for a ring this size.\n\nGlue it under the battery.', at: at(20) },
    { seq: 7, role: 'step', text: 'Asked a helper: Check the board', at: at(23) },
    { seq: 8, role: 'step', text: 'Used mcp__relay__search', at: at(24) },
    { seq: 9, role: 'step', text: 'Fetched docs.example.com', at: at(25) },
    { seq: 10, role: 'step', text: 'Ran: git status', at: at(27) },
  ]);
  assert.equal(chat.startedAt, at(0));
  assert.equal(chat.hasYou, true);
  // Tool output, a !command's output, and thinking never appear.
  assert.doesNotMatch(JSON.stringify(chat), /42 tests|kicad_pcb \(|12 mm wide|helper's own|Caveat|task-id|interrupted|On branch|nothing to commit|made-up stderr|bash-/);
});

test('numbers the same file the same way every time, and a longer file only adds', () => {
  const lines = fixture.split('\n');
  const shorter = readChat(lines.slice(0, 8).join('\n'), { cwd: CWD }).messages;
  assert.deepEqual(readChat(fixture, { cwd: CWD }).messages.slice(0, shorter.length), shorter);
  assert.deepEqual(readChat(fixture, { cwd: CWD }), readChat(fixture, { cwd: CWD }));
});

test('titles a chat by its own title, else its summary, else the first thing you typed, in 80 characters', () => {
  assert.equal(readChat(fixture, { cwd: CWD }).title, 'Stiffener plan');
  const typed = line('user', `Why  does\nthe ${'very '.repeat(30)}long board fail?`);
  assert.equal(readChat(typed, {}).title, `Why does the ${'very '.repeat(30)}`.slice(0, 80));
  const summary = JSON.stringify({ type: 'summary', summary: 'Board check' });
  assert.equal(readChat(`${summary}\n${typed}`, {}).title, 'Board check');
  const titled = JSON.stringify({ type: 'custom-title', customTitle: 'Mine' });
  assert.equal(readChat(`${titled}\n${summary}\n${typed}`, {}).title, 'Mine');
});

test('a chat with nothing you typed says so', () => {
  const chat = readChat([line('user', '<local-command-stdout>ok</local-command-stdout>'), line('assistant', [{ type: 'text', text: 'Hi' }])].join('\n'), {});
  assert.deepEqual([chat.hasYou, chat.messages.map(message => message.role)], [false, ['ai']]);
});

test('a !command you ran is one step line, and its output is never sent, in either content shape', () => {
  const chat = readChat([
    line('user', [{ type: 'text', text: '<bash-input>npm test\nnpm run lint</bash-input>' }]),
    line('user', [{ type: 'text', text: '<bash-stdout>All 42 tests pass.</bash-stdout><bash-stderr></bash-stderr>' }]),
    line('user', '<bash-stderr>made-up error</bash-stderr>'),
  ].join('\n'), {});
  assert.deepEqual(chat.messages.map(message => [message.role, message.text]), [['step', 'Ran: npm test']]);
  assert.equal(chat.hasYou, false);
});

test('cuts a long message and says how much it left out, within the server limit', () => {
  const long = 'x'.repeat(MESSAGE_CHARACTERS + 500);
  const text = readChat(line('user', long), {}).messages[0].text;
  assert.ok(text.length <= MESSAGE_CHARACTERS);
  assert.match(text, /\n\[cut: 540 more characters\]$/);
  assert.equal(cut('short'), 'short');
});

test('hides before it cuts, so a key at the edge never goes out in part', () => {
  const hide = text => text.replaceAll('SECRET', '[hidden]');
  const chat = readChat(line('user', 'my SECRET'), { hide });
  assert.equal(chat.messages[0].text, 'my [hidden]');
  assert.equal(chat.title, 'my [hidden]');
});

test('names each step by its tool, with paths inside the project made short', () => {
  const step = (name, input) => stepLine({ name, input }, CWD);
  assert.deepEqual([
    step('Edit', { file_path: `${CWD}/app/a.ts` }), step('MultiEdit', { file_path: `${CWD}/b.ts` }),
    step('Write', { file_path: '/etc/hosts' }), step('NotebookEdit', { notebook_path: `${CWD}/n.ipynb` }),
    step('Grep', { pattern: 'TODO' }), step('Glob', { pattern: '**/*.ts' }), step('Task', { description: 'Look' }),
    step('WebFetch', { url: 'not a url' }), step('Bash', { command: 'x'.repeat(300) }), stepLine({}, CWD),
    stepLine({ name: 'Read', input: { file_path: 'relative.txt' } }),
  ], ['Edited app/a.ts', 'Edited b.ts', 'Wrote /etc/hosts', 'Edited n.ipynb', 'Searched: TODO', 'Searched: **/*.ts',
    'Asked a helper: Look', 'Fetched a page', `Ran: ${'x'.repeat(200)}`, 'Used a tool', 'Read relative.txt']);
});

test('names the project by its git top folder, else the folder it ran in', () => {
  const top = mkdtempSync(join(tmpdir(), 'relay-project-'));
  mkdirSync(join(top, '.git'));
  mkdirSync(join(top, 'app', 'src'), { recursive: true });
  assert.equal(projectRoot(join(top, 'app', 'src')), top);
  const loose = mkdtempSync(join(tmpdir(), 'relay-loose-'));
  assert.equal(projectRoot(loose), loose);
  assert.equal(projectName('/'), 'a project');
  assert.equal(transcriptText(join(loose, 'none.jsonl')), null);
  assert.equal(transcriptText(loose), null);
});

test('a git worktree counts as its main repository, and a broken link as the worktree itself', () => {
  const { home, main, copy } = repoWithWorktree();
  mkdirSync(join(copy, 'app'));
  assert.equal(projectRoot(main), main);
  assert.equal(projectRoot(join(copy, 'app')), main);
  assert.equal(gitTop(join(copy, 'app')), copy);
  assert.equal(projectName(projectRoot(copy)), 'WongOS');
  // A link to a gitdir that is gone, a .git file with no gitdir line, and a submodule's gitdir with no commondir.
  const broken = join(home, 'broken');
  mkdirSync(broken);
  writeFileSync(join(broken, '.git'), `gitdir: ${join(home, 'gone', '.git', 'worktrees', 'broken')}\n`);
  assert.equal(projectRoot(broken), broken);
  const blank = join(home, 'blank');
  mkdirSync(blank);
  writeFileSync(join(blank, '.git'), 'not a link\n');
  assert.equal(projectRoot(blank), blank);
  const sub = join(home, 'sub');
  mkdirSync(join(home, 'modules', 'sub'), { recursive: true });
  mkdirSync(sub);
  writeFileSync(join(sub, '.git'), 'gitdir: ../modules/sub\n');
  assert.equal(projectRoot(sub), sub);
});
