// The command line of the daily build's agent run, in Claude Code or Codex, from the memory store's headless shape:
// a narrow grant of tools, the copy of the web as its folder, and no hooks, saving or second build in the child.
import { basename } from 'node:path';

/** A build stops after this long; the next day goes on from what it marked read. */
export const STOP_AFTER = 30 * 60_000;

/** The app the starting chat came from: Codex by its rollout or its thread id, else Claude Code. */
export function appOf(env, transcript) {
  // The transcript decides first: a person may set CODEX_HOME in a shell that also runs Claude Code.
  const file = basename(String(transcript ?? ''));
  if (file) return file.startsWith('rollout-') ? 'codex' : 'claude';
  return env.CODEX_THREAD_ID ? 'codex' : 'claude';
}

/** The child's variables: its own chat is not saved and starts no build. */
export const childEnv = env => ({ ...env, RELAY_SAVE: '0', RELAY_BUILD_RUN: '1' });

/** A path as one shell word, quoted only when it needs it, so the prompt's command and the grant match. */
export const shellWord = path => (/^[\w@%+=:,./-]+$/.test(path) ? path : `"${path.replace(/(["\\$`])/g, '\\$1')}"`);

/**
 * `[command, args]` for one build: `command` is the build's own `node <build.mjs>`, the one Bash command it may run;
 * `agents` the helpers' JSON for Claude Code; `writable` the folders Codex may write.
 */
export function buildCommand({ app, prompt, model, command, agents, copy, writable = [copy] }) {
  if (app === 'codex') {
    return ['codex', ['exec', '--ephemeral', '--skip-git-repo-check', ...(model ? ['-m', model] : []), '--sandbox', 'workspace-write',
      '-c', 'sandbox_workspace_write.network_access=true',
      '-c', `sandbox_workspace_write.writable_roots=[${writable.map(root => JSON.stringify(root)).join(',')}]`,
      '-c', 'approval_policy="never"', prompt]];
  }
  // --allowedTools takes many values, so a single-value option follows it.
  return ['claude', ['-p', prompt, ...(model ? ['--model', model] : []), '--no-session-persistence', '--permission-mode', 'dontAsk',
    '--allowedTools', 'Read', 'Write', 'Edit', 'Glob', 'Grep', 'Task', 'Agent', `Bash(${command}:*)`, '--add-dir', copy,
    '--agents', JSON.stringify(agents), '--settings', JSON.stringify({ disableAllHooks: true })]];
}
