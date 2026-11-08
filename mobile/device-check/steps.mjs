#!/usr/bin/env node
// Writes Claude's step log (out/claude/steps.md) from claude-code-action's execution file, or, when Claude ran out of
// time, from Claude Code's session file; and, when Claude gave no final verdict, out/claude/end.txt with why.
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { isMain, parseCli, usageError } from '../../scripts/lib-cli.mjs';

const USAGE = `usage: node mobile/device-check/steps.mjs --file <execution file> --out <out/claude> --max-turns <n>
       [--sessions <folder of Claude Code's session folders, default ~/.claude/projects>]`;
const CUT = 200;
// Only for a log with no result message, which has no permission_denials to trust.
const REFUSED = /requested permissions to use/i;
const VERDICTS = ['works', 'broken', 'could-not-check'];

const cut = text => (text.length > CUT ? `${text.slice(0, CUT - 1)}…` : text);
const oneLine = text => String(text).replace(/\s*\n\s*/g, ' \\n ').replace(/`{3,}/g, "'''");

/** What a tool call worked on: its command, its file or its pattern. */
function target(input = {}) {
  const value = input.command ?? input.file_path ?? input.path ?? input.pattern;
  return oneLine(value ?? JSON.stringify(input));
}

/** The tool calls in order, each with how it ended, and the result message if Claude reached one. */
export function readSteps(messages) {
  const results = new Map();
  for (const message of messages) {
    if (message.type !== 'user' || !Array.isArray(message.message?.content)) continue;
    for (const part of message.message.content) if (part.type === 'tool_result') results.set(part.tool_use_id, part);
  }
  const result = messages.findLast(message => message.type === 'result') ?? null;
  const denied = new Set((result?.permission_denials ?? []).map(denial => denial.tool_use_id));
  const steps = messages
    .filter(message => message.type === 'assistant' && Array.isArray(message.message?.content))
    .flatMap(message => message.message.content.filter(part => part.type === 'tool_use'))
    .map(call => {
      const answer = results.get(call.id);
      const text = typeof answer?.content === 'string' ? answer.content : JSON.stringify(answer?.content ?? '');
      const refused = result ? denied.has(call.id) : answer?.is_error === true && REFUSED.test(text);
      const end = refused ? 'refused' : answer?.is_error ? 'error' : answer ? '' : 'no answer';
      return { tool: call.name, target: cut(target(call.input)), end };
    });
  return { steps, result };
}

/** How many of the report's scenarios Claude checked, from its `Verdict: not yet checked` lines. */
export function scenarioCount(report) {
  const total = (report.match(/^Scenario:/gm) ?? []).length;
  const open = (report.match(/^Verdict: not yet checked/gim) ?? []).length;
  return total ? `${total - open} of ${total} scenarios checked.` : 'No scenario was written in the report.';
}

// Why Claude gave no final verdict, or null. A stop mid-way is no verdict even when verdict.txt holds the brief's
// first `could-not-check`, as Claude writes that before it checks anything.
export function endReason({ found, result, refused, maxTurns, verdict }) {
  const refusals = refused ? ` ${refused} ${refused === 1 ? 'command was' : 'commands were'} refused.` : '';
  if (!found) {
    return `Claude ran out of time, or did not start: its step ended before Claude wrote a verdict.${refusals}`;
  }
  if (!result) return `Claude stopped with an error before it wrote a verdict.${refusals}`;
  if (result.subtype === 'error_max_turns') return `Claude used all ${maxTurns} turns before it wrote a verdict.${refusals}`;
  if (result.subtype !== 'success' || result.is_error) {
    return `Claude stopped with an error (${result.subtype}) before it wrote a verdict.${refusals}`;
  }
  if (!VERDICTS.includes(verdict)) return `Claude stopped with no verdict.${refusals}`;
  return null;
}

export function stepsMarkdown({ steps, result }) {
  const lines = steps.map((step, n) => `${n + 1}. ${step.tool}: ${step.target}${step.end ? ` (${step.end})` : ''}`);
  const summary = result
    ? `Result: ${result.subtype}, ${result.num_turns} turns, ${Math.round((result.duration_ms ?? 0) / 1000)} s.`
    : 'Result: none. Claude did not end on its own.';
  return ['# Claude\'s steps', '', summary, '', '```text', ...(lines.length ? lines : ['No tool calls.']), '```', ''].join('\n');
}

// The newest `<sessions>/<folder>/<session>.jsonl` file's messages: Claude Code writes it as it goes, so it outlives
// a stopped step.
export function readSession(sessions) {
  if (!existsSync(sessions)) return [];
  const files = readdirSync(sessions, { withFileTypes: true }).filter(dir => dir.isDirectory())
    .flatMap(dir => readdirSync(join(sessions, dir.name)).filter(name => name.endsWith('.jsonl'))
      .map(name => join(sessions, dir.name, name)));
  const newest = files.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs)[0];
  if (!newest) return [];
  // The last line can be cut off when the step was stopped mid-write.
  return readFileSync(newest, 'utf8').split('\n').flatMap(line => {
    try {
      return line.trim() ? [JSON.parse(line)] : [];
    } catch {
      return [];
    }
  });
}

export function main({ file, out, maxTurns, sessions = join(homedir(), '.claude', 'projects') }) {
  const found = Boolean(file) && existsSync(file);
  const messages = found ? JSON.parse(readFileSync(file, 'utf8')) : readSession(sessions);
  const log = readSteps(messages);
  const refused = log.steps.filter(step => step.end === 'refused').length;
  writeFileSync(join(out, 'steps.md'), stepsMarkdown(log));
  const verdictFile = join(out, 'verdict.txt');
  const verdict = existsSync(verdictFile) ? readFileSync(verdictFile, 'utf8').trim() : '';
  const reason = endReason({ found, result: log.result, refused, maxTurns, verdict });
  if (!reason) return { reason: null, steps: log.steps.length };
  const report = join(out, 'report.md');
  const count = existsSync(report) ? scenarioCount(readFileSync(report, 'utf8')) : 'Claude wrote no report.';
  writeFileSync(join(out, 'end.txt'), `${reason} ${count}\n`);
  return { reason: `${reason} ${count}`, steps: log.steps.length };
}

if (isMain(import.meta.url)) {
  const { values } = parseCli({
    usage: USAGE,
    options: {
      file: { type: 'string' }, out: { type: 'string' }, 'max-turns': { type: 'string' }, sessions: { type: 'string' },
    },
  });
  if (!values.out || !/^\d+$/.test(values['max-turns'] ?? '')) usageError(USAGE, 'give --out and --max-turns');
  const done = main({ file: values.file, out: values.out, maxTurns: Number(values['max-turns']),
    ...(values.sessions && { sessions: values.sessions }) });
  console.log(`steps=${done.steps}`);
  if (done.reason) console.log(`end=${done.reason}`);
}
