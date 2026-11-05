#!/usr/bin/env node
// `/relay:connect-ai <address>`: adds your Relay server's AI connector to Claude Code, so it can read your notes.
// usage: node connect-ai.mjs https://<your-relay-server>/mcp
import { spawnSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const ADDRESS = /^https:\/\/[^/\s?#@]+\/mcp$/;

/** Runs `claude mcp add` for a connector address, and answers the lines to print and the exit code. */
export function connectAi(address, run = (command, args) => spawnSync(command, args, { stdio: 'inherit' })) {
  if (!ADDRESS.test(address ?? '')) {
    return { code: 2, lines: ['Give the connector address from the AI apps card on your Relay page: https://<your-relay-server>/mcp'] };
  }
  const done = run('claude', ['mcp', 'add', '--transport', 'http', '--scope', 'user', 'relay', address]);
  if (done.error || done.status !== 0) return { code: 1, lines: ['Claude Code could not add the connector. The message above says why.'] };
  return { code: 0, lines: ['Relay is added. Type /mcp, pick relay, and sign in with your Relay email.'] };
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const { code, lines } = connectAi(process.argv[2]);
  console.log(lines.join('\n'));
  process.exitCode = code;
}
