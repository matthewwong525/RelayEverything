#!/usr/bin/env node
// Builds the published site/ folder, refuses anything private, and deploys it as the public Relay website.
// Spec: openspec/specs/relay-website/spec.md. AGENTS.md runs it after each publish; wiki/relay-website.md.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { gunzipSync } from 'node:zlib';
import { isMain, parseCli } from './lib-cli.mjs';
import { blocked, envSecrets } from './public-check.mjs';
import { stripJsonc } from './lib-wrangler-config.mjs';
import { primaryRoot } from '../.claude/skills/memory/scripts/lib/primary-root.mjs';
import { parseEnv } from '../.claude/skills/memory/scripts/lib/store.mjs';

const USAGE = `usage: node scripts/publish-relay-site.mjs [--ref <commit>] [--staging] [--dry-run]

Exports site/ at --ref (default origin/main), installs, tests and builds it, refuses anything private, and deploys
it to the Worker relay (relayeverything.com). --staging deploys to relay-staging, the preview address,
and leaves the live site as it was. --dry-run stops before the deploy. Prints one result= line.`;

const FOLDER = 'site';
const PUBLIC_WORKERS = ['relay', 'relay-staging'];
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/;
const ACCESS_TEAM = /[a-z0-9-]+\.cloudflareaccess\.com/i;
const WORKER_HOST = /([a-z0-9-]+)\.[a-z0-9-]+\.workers\.dev/gi;
// Access IDs and audiences, database IDs, fingerprints and the owner's email: the private site's config values.
const PRIVATE_VALUE = new RegExp(`\\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\b|\\b[0-9a-f]{32,}\\b|${EMAIL.source}`, 'gi');
// Library code credits its translators by email; any address in a page's own text is refused.
const LIBRARY = /\.m?js$/;
const PICTURE = /\.(png|jpe?g|gif|webp|avif|ico|woff2?|ttf)$/i;

const run = (cmd, args, opts = {}) => execFileSync(cmd, args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], ...opts }).trim();

/** Each host the private site's routes name, in every environment, such as its own domain. */
function routeHosts(text) {
  const config = JSON.parse(stripJsonc(text));
  return [config, ...Object.values(config.env ?? {})].flatMap(environment => environment.routes ?? [])
    .map(route => (typeof route === 'string' ? route : route.pattern).replace(/^https?:\/\//, '').replace(/^\*\.?/, '').split('/')[0]);
}

/** The private site's IDs, emails and own domains from its wrangler config, which no public file may hold. */
export const privateValues = text => [...new Set([...(text.match(PRIVATE_VALUE) ?? []), ...routeHosts(text)])];

/** What only the website must not hold, beyond `blocked()`: each file with why, never the value. */
export function siteBlocked(files, values) {
  return files.flatMap(({ path, text }) => {
    const why = !LIBRARY.test(path) && EMAIL.test(text) ? 'an email address'
      : ACCESS_TEAM.test(text) ? 'a Cloudflare Access address'
        : [...text.matchAll(WORKER_HOST)].some(([, name]) => !PUBLIC_WORKERS.includes(name.toLowerCase())) ? 'another Worker\'s address'
          : values.some(value => text.toLowerCase().includes(value.toLowerCase())) ? 'a value from app/wrangler.jsonc' : null;
    return why ? [{ path, why }] : [];
  });
}

/** Every file under `dir`, as text: a picture by its name alone, and a compressed search index unpacked. */
export function readFiles(dir) {
  return readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter(entry => entry.isFile())
    .map(entry => join(entry.parentPath, entry.name).slice(dir.length + 1))
    .map(path => {
      if (PICTURE.test(path)) return { path, text: '' };
      const bytes = readFileSync(join(dir, path));
      return { path, text: (bytes[0] === 0x1f && bytes[1] === 0x8b ? gunzipSync(bytes) : bytes).toString('latin1') };
    });
}

/** The refusal line for these files, or null when they are clean. */
export function refusal(files, secrets, values) {
  const stops = [...blocked(files, secrets), ...siteBlocked(files, values)];
  return stops.length ? `result=refused ${stops.map(stop => `${stop.path} (${stop.why})`).join(', ')}` : null;
}

/** The deployed address in wrangler's output: the live site's own domain when it has one, else its workers.dev address. */
export function deployedUrl(output) {
  const domain = output.match(/^\s*([a-z0-9.-]+\.[a-z]+) \(custom domain\)/m)?.[1];
  return domain ? `https://${domain}` : output.match(/https:\/\/relay(?:-staging)?\.[a-z0-9-]+\.workers\.dev/)?.[0] ?? null;
}

function step(name, cmd, args, opts) {
  try {
    return run(cmd, args, opts);
  } catch (error) {
    process.stderr.write(`${error.stdout ?? ''}${error.stderr ?? ''}`);
    throw new Error(`result=failed ${name}`);
  }
}

export function publish({ root, ref, staging, dryRun }) {
  const sha = run('git', ['-C', root, 'rev-parse', '--verify', `${ref}^{commit}`]);
  const commit = `commit=${sha.slice(0, 7)}`;
  if (!run('git', ['-C', root, 'ls-tree', '--name-only', sha, `${FOLDER}/`])) return `result=empty ${commit}`;
  const work = mkdtempSync(join(tmpdir(), 'relay-site-'));
  try {
    execFileSync('tar', ['-x', '-C', work, '--strip-components=1'], { input: execFileSync('git', ['-C', root, 'archive', sha, `${FOLDER}/`], { maxBuffer: 256 * 1024 * 1024 }) });
    const envFile = join(primaryRoot(root).primary, '.env');
    const env = existsSync(envFile) ? readFileSync(envFile, 'utf8') : '';
    const secrets = envSecrets(env);
    const values = privateValues(run('git', ['-C', root, 'show', `${sha}:app/wrangler.jsonc`]));
    const sources = refusal(readFiles(work), secrets, values);
    if (sources) return sources;
    step('install', 'npm', ['ci', '--no-audit', '--no-fund'], { cwd: work });
    step('test', 'npm', ['test'], { cwd: work });
    const built = refusal(readFiles(join(work, 'dist')), secrets, values);
    if (built) return built;
    if (dryRun) return `result=ready ${commit}`;
    const { CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID } = parseEnv(env);
    const output = step('deploy', 'npx', ['wrangler', 'deploy', ...(staging ? ['--env', 'staging'] : [])],
      { cwd: work, env: { ...process.env, CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID } });
    const url = deployedUrl(output);
    return url ? `result=deployed url=${url} ${commit}` : `result=failed deploy (no address in wrangler's output) ${commit}`;
  } catch (error) {
    if (error.message.startsWith('result=')) return `${error.message} ${commit}`;
    throw error;
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

if (isMain(import.meta.url)) {
  const { values } = parseCli({
    usage: USAGE,
    options: { ref: { type: 'string', default: 'origin/main' }, staging: { type: 'boolean' }, 'dry-run': { type: 'boolean' } },
  });
  const root = run('git', ['rev-parse', '--show-toplevel']);
  const line = publish({ root, ref: values.ref, staging: !!values.staging, dryRun: !!values['dry-run'] });
  console.log(line);
  if (!/^result=(deployed|ready|empty)/.test(line)) process.exit(1);
}
