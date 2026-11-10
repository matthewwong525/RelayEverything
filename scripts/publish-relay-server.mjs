#!/usr/bin/env node
// Updates Relay Everything's server from the published commit: the staging spaces Worker, connector and shared
// server, then the live shared server. AGENTS.md runs it after each publish; wiki/relay-spaces.md.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { isMain, parseCli } from './lib-cli.mjs';
import { parseConfig, redirectedConfig, workerName } from './lib-wrangler-config.mjs';
import { primaryRoot } from '../.claude/skills/memory/scripts/lib/primary-root.mjs';
import { parseEnv } from '../.claude/skills/memory/scripts/lib/store.mjs';

const USAGE = `usage: node scripts/publish-relay-server.mjs [--ref <commit>] [--staging-only] [--dry-run]

Exports the repository at --ref (default origin/main), installs app/, builds the Relay Everything page with Flutter,
then deploys in order the staging spaces Worker, the staging AI connector and the staging shared server, then the
live shared server. It stops at the
first failure, so a staging failure leaves live as it was. --staging-only skips live. --dry-run builds each
part and deploys nothing. Prints one result= line.`;

const SERVER = 'wrangler.relay.jsonc';
const LIVE_SERVER = 'relay-everything-server';

/** The steps in order: a `-c` deploy names its Worker from its config, a server build from its redirect. */
export function plan({ stagingOnly }) {
  const staging = [
    { name: 'staging-spaces', config: 'wrangler.spaces.jsonc', worker: 'relay-everything-spaces-staging' },
    { name: 'staging-connector', config: 'wrangler.relay-mcp.jsonc', worker: 'relay-everything-mcp-staging' },
    { name: 'staging-server', build: 'staging', worker: 'relay-everything-server-staging' },
  ];
  return stagingOnly ? staging : [...staging, { name: 'live-server', build: 'live', worker: LIVE_SERVER }];
}

const defaultRun = (cmd, args, opts) => execFileSync(cmd, args, { stdio: ['ignore', 2, 2], ...opts });
const defaultExport = (root, sha, work) =>
  execFileSync('tar', ['-x', '-C', work], { input: execFileSync('git', ['-C', root, 'archive', sha], { maxBuffer: 1 << 30 }) });

/** Cloudflare's key from the primary worktree's .env, as publish-relay-site.mjs reads it, else the shell's. */
function cloudflareEnv(root) {
  const file = join(primaryRoot(root).primary, '.env');
  const values = existsSync(file) ? parseEnv(readFileSync(file, 'utf8')) : {};
  const keys = ['CLOUDFLARE_API_TOKEN', 'CLOUDFLARE_ACCOUNT_ID'].filter(key => values[key]);
  return Object.fromEntries(keys.map(key => [key, values[key]]));
}

// A build that missed its environment redirects wrangler to the wrong Worker; check before each deploy.
function expectWorker(name, expected) {
  if (name !== expected) throw new Error(`deploys ${name}, not ${expected}`);
}

function runStep(step, { app, env, dryRun, run }) {
  const deploy = ['wrangler', 'deploy', ...(dryRun ? ['--dry-run'] : [])];
  if (step.config) {
    expectWorker(workerName(parseConfig(join(app, step.config)), 'staging'), step.worker);
    run('npx', [...deploy, '-c', step.config, '--env', 'staging'], { cwd: app, env });
    return;
  }
  const { CLOUDFLARE_ENV: _, ...base } = env;
  const buildEnv = { ...base, RELAY_CONFIG: SERVER, ...(step.build === 'staging' ? { CLOUDFLARE_ENV: 'staging' } : {}) };
  run('npm', ['run', 'build:relay-only'], { cwd: app, env: buildEnv });
  const redirect = redirectedConfig(join(app, SERVER));
  expectWorker(redirect ? workerName(parseConfig(redirect)) : 'no build redirect', step.worker);
  run('npx', deploy, { cwd: app, env: base });
}

/** Runs every step and returns the one result line. `run` and `exportTree` stand in for a test. */
export function publish({ root, ref, stagingOnly = false, dryRun = false, run = defaultRun, exportTree = defaultExport,
  env = { ...process.env, ...cloudflareEnv(root) } }) {
  let sha;
  try {
    sha = execFileSync('git', ['-C', root, 'rev-parse', '--verify', `${ref}^{commit}`], { encoding: 'utf8', stdio: 'pipe' }).trim();
  } catch {
    return `result=failed step=ref ref=${ref}`;
  }
  const tag = `ref=${sha.slice(0, 7)}`;
  const steps = plan({ stagingOnly });
  const work = mkdtempSync(join(tmpdir(), 'relay-server-'));
  const app = join(work, 'app');
  let current = 'export';
  try {
    exportTree(root, sha, work);
    current = 'install';
    run('npm', ['ci', '--no-audit', '--no-fund'], { cwd: app, env });
    // The page both servers serve: the phone app built for the web, into app/public/apps/relay/.
    current = 'web';
    run('node', ['../scripts/build-relay-web.mjs'], { cwd: app, env });
    for (const step of steps) {
      current = step.name;
      runStep(step, { app, env, dryRun, run });
    }
    return `result=${dryRun ? 'dry-run' : 'deployed'} ${tag} workers=${steps.map(step => step.worker).join(',')}`;
  } catch (error) {
    process.stderr.write(`publish-relay-server: ${current}: ${error.message}\n`);
    return `result=failed step=${current} ${tag}`;
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

if (isMain(import.meta.url)) {
  const { values } = parseCli({
    usage: USAGE,
    options: { ref: { type: 'string', default: 'origin/main' }, 'staging-only': { type: 'boolean' }, 'dry-run': { type: 'boolean' } },
  });
  const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
  const line = publish({ root, ref: values.ref, stagingOnly: !!values['staging-only'], dryRun: !!values['dry-run'] });
  console.log(line);
  if (!/^result=(deployed|dry-run)/.test(line)) process.exit(1);
}
