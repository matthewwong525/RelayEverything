// Reads a Claude Code transcript (JSONL) into Relay Everything's chat messages: what you typed, the AI's text, and one line per
// step. Tool output, thinking, helper chats and lines this reader does not know are never sent.
import { existsSync, readFileSync, statSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative } from 'node:path';

export const MESSAGE_CHARACTERS = 200_000;
export const TITLE_CHARACTERS = 80;
const STEP_CHARACTERS = 200;
const NOT_TYPED = /^(?:<task-notification>|<local-command-std(?:out|err)>|<local-command-caveat>|<bash-std(?:out|err)>|<system-reminder>|\[Request interrupted by user)/;
// A `!command` you ran in Claude Code: kept as a step, like the AI's own commands; its output lines are NOT_TYPED.
const BASH_INPUT = /^<bash-input>([\s\S]*?)<\/bash-input>/;

export const firstLine = value => String(value ?? '').trim().split('\n')[0].slice(0, STEP_CHARACTERS);

export function shortPath(path, cwd) {
  const text = String(path ?? '');
  if (!isAbsolute(text) || !cwd) return text;
  const inside = relative(cwd, text);
  return inside && !inside.startsWith('..') && !isAbsolute(inside) ? inside : text;
}

function host(url) {
  try {
    return new URL(url).host;
  } catch {
    return 'a page';
  }
}

const STEPS = {
  Bash: input => `Ran: ${firstLine(input.command)}`,
  Read: (input, cwd) => `Read ${shortPath(input.file_path, cwd)}`,
  Edit: (input, cwd) => `Edited ${shortPath(input.file_path, cwd)}`,
  MultiEdit: (input, cwd) => `Edited ${shortPath(input.file_path, cwd)}`,
  NotebookEdit: (input, cwd) => `Edited ${shortPath(input.notebook_path, cwd)}`,
  Write: (input, cwd) => `Wrote ${shortPath(input.file_path, cwd)}`,
  Grep: input => `Searched: ${firstLine(input.pattern)}`,
  Glob: input => `Searched: ${firstLine(input.pattern)}`,
  WebFetch: input => `Fetched ${host(input.url)}`,
  Agent: input => `Asked a helper: ${firstLine(input.description)}`,
  Task: input => `Asked a helper: ${firstLine(input.description)}`,
};

/** One step line for a tool call: its name and its file, command or page, never its output. */
export const stepLine = (block, cwd) => (STEPS[block.name]?.(block.input ?? {}, cwd) ?? `Used ${firstLine(block.name) || 'a tool'}`);

/** A slash command as you typed it, or the text with nothing Claude Code added; '' when you typed none of it. */
function typed(text) {
  const command = /<command-name>([^<]*)<\/command-name>/.exec(text);
  if (command) return [command[1].trim(), /<command-args>([\s\S]*?)<\/command-args>/.exec(text)?.[1].trim()].filter(Boolean).join(' ');
  return NOT_TYPED.test(text.trimStart()) ? '' : text.trim();
}

/** Ends a long message with how much it left out, keeping it within the server's limit. */
export function cut(text) {
  if (text.length <= MESSAGE_CHARACTERS) return text;
  const keep = MESSAGE_CHARACTERS - 40;
  return `${text.slice(0, keep)}\n[cut: ${text.length - keep} more characters]`;
}

function youText(content) {
  if (typeof content === 'string') return typed(content);
  if (!Array.isArray(content)) return '';
  return content.map(block => block?.type === 'text' ? typed(String(block.text ?? '')) : block?.type === 'image' ? '[image]' : '')
    .filter(Boolean).join('\n');
}

/** The first text of a user line's content. */
const leadText = content => (typeof content === 'string' ? content
  : Array.isArray(content) && content[0]?.type === 'text' ? String(content[0].text ?? '') : '');

/** The messages of one transcript line, as `[role, text]` pairs. */
function said(line, cwd) {
  if (line.type === 'user') {
    const ran = BASH_INPUT.exec(leadText(line.message?.content).trimStart());
    if (ran) return [['step', `Ran: ${firstLine(ran[1])}`]];
    const text = youText(line.message?.content);
    return text ? [['you', text]] : [];
  }
  const content = Array.isArray(line.message?.content) ? line.message.content : [];
  return content.flatMap(block => block?.type === 'text' && String(block.text ?? '').trim() ? [['ai', String(block.text).trim()]]
    : block?.type === 'tool_use' ? [['step', stepLine(block, cwd)]] : []);
}

const spoken = line => (line.type === 'user' || line.type === 'assistant')
  && !line.isSidechain && !line.isMeta && !line.isCompactSummary && !line.isVisibleInTranscriptOnly && !line.origin;

/** A chat from transcript text: its title, start and messages, with `seq` counted from 0 so a reread numbers alike. */
export function readChat(text, { cwd, hide = value => value }) {
  const lines = text.split('\n').flatMap(raw => {
    try {
      const line = JSON.parse(raw);
      return line && typeof line === 'object' ? [line] : [];
    } catch {
      return [];
    }
  });
  const messages = [];
  let at = null;
  let named = null;
  for (const line of lines) {
    const stamp = Date.parse(line.timestamp ?? '');
    if (Number.isFinite(stamp)) at = stamp;
    if (line.type === 'custom-title' && line.customTitle) named = String(line.customTitle);
    else if (line.type === 'summary' && line.summary && named === null) named = String(line.summary);
    if (!spoken(line) || at === null) continue;
    for (const [role, words] of said(line, cwd)) messages.push({ seq: messages.length, role, text: cut(hide(words)), at });
  }
  const first = messages.find(message => message.role === 'you');
  const title = hide(named ?? first?.text ?? '').replace(/\s+/g, ' ').trim().slice(0, TITLE_CHARACTERS);
  return { title, startedAt: messages[0]?.at ?? null, messages, hasYou: !!first };
}

/** The git top folder of `cwd`, else `cwd`: the key for saving off, and the project's name. */
export function projectRoot(cwd) {
  for (let at = cwd; ; at = dirname(at)) {
    if (existsSync(join(at, '.git'))) return at;
    if (dirname(at) === at) return cwd;
  }
}

export const projectName = root => basename(root).slice(0, 200) || 'a project';

/** The transcript's text, or null when it is gone. */
export function transcriptText(path) {
  try {
    return statSync(path).isFile() ? readFileSync(path, 'utf8') : null;
  } catch {
    return null;
  }
}
