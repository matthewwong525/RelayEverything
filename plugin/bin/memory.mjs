#!/usr/bin/env node
// `/relay-memory`'s command: runs memory's own script in `memory/` with Relay Everything's profile, so it reads and
// writes the person's own space. usage: node memory.mjs <command>, as memory's skill lists them.
import { spawnSync } from 'node:child_process';
import { memoryEnv, MEMORY_SCRIPT } from '../lib/memory.mjs';

const result = spawnSync(process.execPath, [MEMORY_SCRIPT, ...process.argv.slice(2)], { stdio: 'inherit', env: memoryEnv(process.env) });
process.exitCode = result.status ?? 1;
