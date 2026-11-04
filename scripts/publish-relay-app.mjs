#!/usr/bin/env node
// Copies the published mobile/ folder, and nothing else, to the public relay-app repository on GitHub.
// Spec: openspec/specs/relay-app-publish/spec.md. AGENTS.md runs it after each publish.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { isMain, parseCli } from './lib-cli.mjs';
import { primaryRoot } from '../.claude/skills/memory/scripts/lib/primary-root.mjs';
import { parseEnv } from '../.claude/skills/memory/scripts/lib/store.mjs';

const USAGE = `usage: node scripts/publish-relay-app.mjs [--ref <commit>] [--repo <owner/name>] [--dry-run]

Exports mobile/ at --ref (default origin/main), refuses keys and private notes, and pushes it as one commit to
--repo (default matthewwong525/relay-app), creating that public repository once. Prints one result= line.`;

const FOLDER = 'mobile';
// Secret-shaped files and private notes; .env.example is the one .env file allowed out.
const PRIVATE_PATH = /(^|\/)(\.env(?!\.example$)[^/]*|key\.properties|google-services\.json|GoogleService-Info\.plist|[^/]*\.(jks|keystore|p12|pem|key|mobileprovision)|[^/]*\.private\.[^/]*)$|(^|\/)notes\//i;
const KEY_TEXT = /gh[pousr]_[A-Za-z0-9]{30,}|github_pat_\w{40,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[abpr]-[\w-]{10,}|sk-[A-Za-z0-9_-]{20,}/;

const run = (cmd, args, opts = {}) => execFileSync(cmd, args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], ...opts }).trim();

/** Each file that must not leave, with why; `secrets` are the private .env values. Never returns a value. */
export function blocked(files, secrets) {
  return files.flatMap(({ path, text }) => {
    if (PRIVATE_PATH.test(path)) return [{ path, why: 'a key file or private note' }];
    if (KEY_TEXT.test(text)) return [{ path, why: 'text shaped like a key' }];
    if (secrets.some(value => text.includes(value))) return [{ path, why: 'a value from .env' }];
    return [];
  });
}

/** The .env values long enough to recognise; short ones like `0` would match everywhere. */
export function envSecrets(text) {
  return Object.values(parseEnv(text)).filter(value => value.length >= 8);
}

function walk(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    if (!prefix && entry.name === '.git') return [];
    const path = prefix + entry.name;
    return entry.isDirectory() ? walk(join(dir, entry.name), `${path}/`) : [path];
  });
}

function exportFolder(root, ref, dir) {
  const tar = execFileSync('git', ['-C', root, 'archive', ref, `${FOLDER}/`]);
  execFileSync('tar', ['-x', '-C', dir, `--strip-components=1`], { input: tar });
}

function cloneOrCreate(repo, dir, dryRun) {
  try {
    run('gh', ['repo', 'view', repo, '--json', 'name']);
  } catch {
    if (dryRun) return run('git', ['init', '-q', '-b', 'main', dir]);
    run('gh', ['repo', 'create', repo, '--public', '--description', 'Relay ring phone app']);
  }
  run('git', ['clone', '-q', `https://github.com/${repo}.git`, dir]);
}

function publish({ ref, repo, dryRun }) {
  const root = run('git', ['rev-parse', '--show-toplevel']);
  const sha = run('git', ['-C', root, 'rev-parse', '--verify', `${ref}^{commit}`]);
  if (!run('git', ['-C', root, 'ls-tree', '--name-only', sha, `${FOLDER}/`])) return `result=empty commit=${sha.slice(0, 7)}`;
  const work = mkdtempSync(join(tmpdir(), 'relay-app-'));
  try {
    const app = join(work, 'export');
    const clone = join(work, 'clone');
    mkdirSync(app);
    exportFolder(root, sha, app);
    const envFile = join(primaryRoot(root).primary, '.env');
    const secrets = existsSync(envFile) ? envSecrets(readFileSync(envFile, 'utf8')) : [];
    const files = walk(app).map(path => ({ path, text: readFileSync(join(app, path), 'latin1') }));
    const stops = blocked(files, secrets);
    if (stops.length) return `result=refused ${stops.map(stop => `${stop.path} (${stop.why})`).join(', ')}`;
    cloneOrCreate(repo, clone, dryRun);
    for (const path of readdirSync(clone)) if (path !== '.git') rmSync(join(clone, path), { recursive: true });
    run('cp', ['-a', `${app}/.`, clone]);
    run('git', ['-C', clone, 'add', '-A']);
    if (!run('git', ['-C', clone, 'status', '--porcelain'])) return `result=unchanged commit=${sha.slice(0, 7)}`;
    if (dryRun) return `result=would-push files=${files.length} commit=${sha.slice(0, 7)}`;
    run('git', ['-C', clone, 'commit', '-q', '-m', `Relay app from relay-ring ${sha.slice(0, 7)}`]);
    run('git', ['-C', clone, 'push', '-q', 'origin', 'HEAD:main']);
    return `result=pushed repo=https://github.com/${repo} commit=${sha.slice(0, 7)}`;
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

if (isMain(import.meta.url)) {
  const { values } = parseCli({
    usage: USAGE,
    options: { ref: { type: 'string', default: 'origin/main' }, repo: { type: 'string', default: 'matthewwong525/relay-app' }, 'dry-run': { type: 'boolean' } },
  });
  const line = publish({ ref: values.ref, repo: values.repo, dryRun: values['dry-run'] });
  console.log(line);
  if (line.startsWith('result=refused')) process.exit(1);
}
