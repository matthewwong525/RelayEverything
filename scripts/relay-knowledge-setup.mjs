#!/usr/bin/env node
// The knowledge web's start: the Artifacts namespace the server binds as KNOWLEDGE, and its `start` repo holding
// schema/knowledge/. Each person's web is a copy of `start`. Safe to run again. wiki/stack/relay-knowledge-web.md
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { isMain, parseCli } from './lib-cli.mjs';
import { parseConfig, repoRoot } from './lib-wrangler-config.mjs';
import { cloudflareEnv } from './publish-relay-server.mjs';
import { cloudflare } from './relay-mcp-setup.mjs';

const USAGE = `usage: node scripts/relay-knowledge-setup.mjs [--staging] [--dry-run]
  --staging   the previews' namespace, not the live one
  --dry-run   print the steps; change nothing`;

export const START = 'start';
export const PAGES = ['README.md', 'FORMAT.md'];
const BRANCH = 'main';
/** The push's pass lasts ten minutes: long enough for two small pages. */
const PASS_SECONDS = 600;

/** The namespace the server binds, from its committed config, so the script and the server can't differ. */
export function namespaceOf(config, staging) {
  const entry = ((staging ? config.env?.staging : config)?.artifacts ?? []).find(item => item.binding === 'KNOWLEDGE');
  if (!entry?.namespace) throw new Error(`app/wrangler.relay.jsonc binds no KNOWLEDGE namespace${staging ? ' for staging' : ''}.`);
  return entry.namespace;
}

/** The steps a run takes, in order: what --dry-run prints. */
export const plan = namespace => [`namespace ${namespace}`, `repo ${START}`, `pages ${PAGES.join(', ')}`];

/** True when Cloudflare said the thing is there already. */
const there = error => error.status === 409 || /exist/i.test(error.message);

/** Runs git with the pass in its environment only: never in an argument, a file or the remote. */
const defaultGit = (args, { cwd, pass }) => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  env: { ...process.env, GIT_TERMINAL_PROMPT: '0', GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.extraHeader',
    GIT_CONFIG_VALUE_0: `Authorization: Bearer ${pass}` } }).trim();

/** Makes the namespace and the start repo when missing, and pushes the start pages; answers one `ok` line a step. */
export async function setup({ staging = false, env, request = fetch, git = defaultGit, pages = join(repoRoot, 'schema', 'knowledge'),
  config = parseConfig(join(repoRoot, 'app', 'wrangler.relay.jsonc')) }) {
  const namespace = namespaceOf(config, staging);
  const account = env.CLOUDFLARE_ACCOUNT_ID;
  if (!env.CLOUDFLARE_API_TOKEN || !account) throw new Error('Set CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID in the .env.');
  const cf = cloudflare(env.CLOUDFLARE_API_TOKEN, request);
  const base = `/accounts/${account}/artifacts/namespaces`;
  const lines = [];
  const made = async (path, body) => {
    try {
      await cf(path, 'POST', body);
      return 'made';
    } catch (error) {
      if (there(error)) return 'there';
      throw error;
    }
  };
  lines.push(`ok namespace ${namespace} (${await made(base, { namespace })})`);
  lines.push(`ok repo ${START} (${await made(`${base}/${namespace}/repos`, { name: START, default_branch: BRANCH,
    description: 'The start of each Relay Everything knowledge web.' })})`);
  const repo = await cf(`${base}/${namespace}/repos/${START}`);
  const remote = repo?.remote ?? `https://${account}.artifacts.cloudflare.net/git/${namespace}/${START}.git`;
  const { plaintext: pass } = await cf(`${base}/${namespace}/tokens`, 'POST', { repo: START, scope: 'write', ttl: PASS_SECONDS });
  const work = mkdtempSync(join(tmpdir(), 'relay-knowledge-'));
  try {
    git(['clone', '--quiet', remote, work], { pass });
    git(['checkout', '--quiet', '-B', BRANCH], { cwd: work, pass });
    for (const page of PAGES) copyFileSync(join(pages, page), join(work, page));
    git(['add', ...PAGES], { cwd: work, pass });
    if (!git(['status', '--porcelain'], { cwd: work, pass })) {
      lines.push(`ok pages (unchanged)`);
      return lines;
    }
    git(['-c', 'user.name=Relay Everything', '-c', 'user.email=knowledge@localhost', 'commit', '--quiet', '-m', 'The start pages'],
      { cwd: work, pass });
    git(['push', '--quiet', 'origin', `HEAD:${BRANCH}`], { cwd: work, pass });
    lines.push(`ok pages (sent ${PAGES.join(', ')})`);
    return lines;
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

if (isMain(import.meta.url)) {
  const { values } = parseCli({ usage: USAGE, options: { staging: { type: 'boolean' }, 'dry-run': { type: 'boolean' } } });
  const staging = !!values.staging;
  try {
    if (values['dry-run']) {
      const namespace = namespaceOf(parseConfig(join(repoRoot, 'app', 'wrangler.relay.jsonc')), staging);
      for (const step of plan(namespace)) console.log(`would ${step}`);
    } else {
      // From publish-relay-server.mjs the key is in the environment already, and the export has no .git to find .env by.
      const env = process.env.CLOUDFLARE_API_TOKEN ? process.env : { ...process.env, ...cloudflareEnv(repoRoot) };
      for (const line of await setup({ staging, env })) console.log(line);
    }
  } catch (error) {
    console.error(`relay-knowledge-setup: ${error.message}`);
    process.exitCode = 1;
  }
}
