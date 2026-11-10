// Reads a Codex rollout (JSONL, under ~/.codex/sessions) into the same chat messages as a Claude Code transcript: what
// you typed, the AI's text, and one line per step. Reasoning, tool output, the context Codex adds to your messages,
// helper agents' messages and lines this reader does not know are never sent.
import { cut, firstLine, shortPath, TITLE_CHARACTERS } from './transcript.mjs';

// Text Codex adds as if you typed it: the folder and shell, AGENTS.md, a skill's text, and the like.
const ADDED = /^(?:<environment_context>|<user_instructions>|# AGENTS\.md instructions|<INSTRUCTIONS>|<skill>|<turn_aborted>|<no retained transcript delta entries>|<\/?image\b[^>]*>\s*$)/;
// Any other block wrapped in one tag whose name has `_` or `-`, as Codex names them; a tag you type, such as <div>, has neither.
const WRAPPED = /^<([a-z][a-z0-9]*[_-][a-z0-9_-]*)>[\s\S]*<\/\1>\s*$/;
const SHELL = new Set(['shell', 'exec_command', 'shell_command', 'container.exec', 'local_shell']);
const PATCH_FILE = /\*\*\* (Add|Update|Delete) File: ([^\n"\\]+)/g;

/** True when the text is a Codex rollout: its first line is the session's `session_meta`. */
export function isCodexRollout(text) {
  const first = String(text ?? '').split('\n', 1)[0];
  try {
    return JSON.parse(first)?.type === 'session_meta';
  } catch {
    return false;
  }
}

const added = text => ADDED.test(text.trimStart()) || WRAPPED.test(text.trim());

/** What you typed in one message, with an image as `[image]`; '' when Codex added all of it. */
function youText(content) {
  if (!Array.isArray(content)) return '';
  return content.map(block => block?.type === 'input_text' ? (added(String(block.text ?? '')) ? '' : String(block.text ?? '').trim())
    : block?.type === 'input_image' ? '[image]' : '').filter(Boolean).join('\n');
}

const aiText = content => (Array.isArray(content) ? content : [])
  .map(block => block?.type === 'output_text' ? String(block.text ?? '').trim() : '').filter(Boolean).join('\n\n');

/** A shell command as one line: an array is joined, and `bash -lc '…'` shows only what it runs. */
function commandLine(command) {
  const words = Array.isArray(command) ? command.map(String) : [String(command ?? '')];
  const inner = words.length >= 3 && /(?:^|\/)(?:ba|z)?sh$/.test(words[0]) && /^-l?c$/.test(words[1]) ? words[2] : words.join(' ');
  return `Ran: ${firstLine(inner)}`;
}

/** One step line per file a patch adds, changes or deletes. */
function patchSteps(text, cwd) {
  const verb = { Add: 'Wrote', Update: 'Edited', Delete: 'Deleted' };
  return [...String(text ?? '').matchAll(PATCH_FILE)].map(([, kind, path]) => `${verb[kind]} ${shortPath(path.trim(), cwd)}`);
}

function parsed(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/** A JavaScript string literal from Codex's code mode, as its text. */
function literal(text) {
  if (text.startsWith('"')) return parsed(text) ?? text.slice(1, -1);
  return text.slice(1, -1).replace(/\\(.)/g, '$1');
}

/**
 * Codex's code mode runs a short script that calls tools, such as `tools.exec_command({cmd:"npm test"})`: one step per
 * tool it calls, in order.
 */
function codeSteps(code, cwd) {
  const steps = [];
  // [before, name, its arguments up to the next call, name, …]
  const parts = String(code ?? '').split(/tools\.([A-Za-z_]\w*)\(/);
  for (let at = 1; at < parts.length; at += 2) {
    const [name, args] = [parts[at], parts[at + 1]];
    if (name === 'exec_command') {
      const cmd = /^\s*\{[^]*?\bcmd"?\s*:\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`[^`]*`)/.exec(args);
      steps.push(cmd ? commandLine(literal(cmd[1])) : 'Ran a command');
    } else if (name === 'apply_patch') {
      const files = patchSteps(args, cwd);
      steps.push(...(files.length ? files : ['Edited files']));
    } else if (name !== 'write_stdin' && name !== 'wait') steps.push(`Used ${firstLine(name)}`);
  }
  return steps.length ? steps : ['Ran code'];
}

/** The step lines of one tool call: its command, files or name, never its output. */
export function stepLines(item, cwd) {
  if (item.type === 'local_shell_call') return [commandLine(item.action?.command)];
  if (item.type === 'custom_tool_call') {
    if (item.name === 'exec') return codeSteps(item.input, cwd);
    if (item.name === 'apply_patch') {
      const files = patchSteps(item.input, cwd);
      return files.length ? files : ['Edited files'];
    }
    return [`Used ${firstLine(item.name) || 'a tool'}`];
  }
  const args = typeof item.arguments === 'string' ? parsed(item.arguments) ?? {} : item.arguments ?? {};
  if (SHELL.has(item.name)) return [commandLine(args.cmd ?? args.command)];
  if (item.name === 'apply_patch') return patchSteps(args.input ?? args.patch, cwd);
  return [`Used ${firstLine(item.name) || 'a tool'}`];
}

/** The messages of one rollout item, as `[role, text]` pairs. */
function said(item, cwd) {
  if (item.type === 'message' && item.role === 'user') {
    const text = youText(item.content);
    return text ? [['you', text]] : [];
  }
  if (item.type === 'message' && item.role === 'assistant') {
    const text = aiText(item.content);
    return text ? [['ai', text]] : [];
  }
  if (['function_call', 'custom_tool_call', 'local_shell_call'].includes(item.type)) {
    return stepLines(item, cwd).map(line => ['step', line]);
  }
  // Reasoning, every tool's output, helper agents' messages and developer text are never sent.
  return [];
}

/**
 * A chat from a rollout's text, in the same shape as `readChat`. A helper agent's rollout gives no messages: its
 * parent chat holds what matters.
 */
export function readCodexChat(text, { cwd, hide = value => value }) {
  const lines = text.split('\n').flatMap(raw => {
    const line = parsed(raw);
    return line && typeof line === 'object' ? [line] : [];
  });
  const meta = lines.find(line => line.type === 'session_meta')?.payload ?? {};
  const helper = Boolean(meta.parent_thread_id || meta.source?.subagent || meta.thread_source === 'subagent');
  const messages = [];
  for (const line of helper ? [] : lines) {
    const at = Date.parse(line.timestamp ?? '');
    if (line.type !== 'response_item' || !line.payload || !Number.isFinite(at)) continue;
    for (const [role, words] of said(line.payload, cwd)) messages.push({ seq: messages.length, role, text: cut(hide(words)), at });
  }
  const first = messages.find(message => message.role === 'you');
  const title = hide(first?.text ?? '').replace(/\s+/g, ' ').trim().slice(0, TITLE_CHARACTERS);
  return { title, startedAt: messages[0]?.at ?? null, messages, hasYou: !!first };
}
