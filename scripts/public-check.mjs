#!/usr/bin/env node
// Keeps keys and private notes out of the public RelayEverything repository: the files here now, or every past commit.
// Spec: openspec/specs/relay-open-source/spec.md. CI's Test job and app/'s npm test run --tree; wiki/open-source.md.
import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { isMain, parseCli, usageError } from './lib-cli.mjs';
import { primaryRoot } from '../.claude/skills/memory/scripts/lib/primary-root.mjs';
import { parseEnv } from '../.claude/skills/memory/scripts/lib/store.mjs';

const USAGE = `usage: node scripts/public-check.mjs [--tree | --history | --notes]

--tree     (default) every file Git tracks or would track here, as it is on disk now
--history  every file in every commit that any ref reaches, and every commit message
--notes    a list for a person to read: lines in openspec/, wiki/ and Markdown files of every commit that name
           health or location values, phone numbers, street addresses, or emails that no commit author uses

--tree and --history refuse key files, private notes, key-shaped text, and values from the primary worktree's
.env and app/.dev.vars, naming the file (and commit) and never the value. --notes never fails.
Prints one result= line: clean, refused <where> (<why>), ..., or listed <count>.`;

// Secret-shaped files and private notes; the .example copies are the ones allowed out.
const PRIVATE_PATH = /(^|\/)(\.env(?!\.example$)[^/]*|\.dev\.vars(?!\.example$)[^/]*|key\.properties|google-services\.json|GoogleService-Info\.plist|[^/]*\.(jks|keystore|p12|p8|pem|key|cer|certSigningRequest|mobileprovision|provisionprofile)|[^/]*\.private\.[^/]*)$|(^|\/)notes\//i;
const KEY_TEXT = /gh[pousr]_[A-Za-z0-9]{30,}|github_pat_\w{40,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[abpr]-[\w-]{10,}|\bsk-[A-Za-z0-9_-]{20,}|\b[sr]k_live_[A-Za-z0-9]{16,}|AIza[0-9A-Za-z_-]{35}|\bwongm_[A-Za-z0-9_-]{20,}/;
// .env names whose values are IDs, not keys: Access still guards every route (design.md of the open-source change).
const PUBLIC_NAMES = ['CLOUDFLARE_ACCOUNT_ID'];
const SECRET_FILES = ['.env', 'app/.dev.vars'];

// What --notes looks for, each a kind a person reads past. Never printed with its value.
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/g;
// Reserved example domains (RFC 2606) and no-reply senders hold no person's address.
const PUBLIC_EMAIL = /@(?:[\w-]+\.)*(?:example\.(?:com|org|net)|example|test|invalid|localhost)$|^noreply@|^no-reply@|@users\.noreply\.github\.com$/i;
const NOTE_KINDS = [
  ['a phone number', /(?<![\w.:/-])(?:\+\d{1,3}[\s.-]?)?(?:\(\d{3}\)\s?|\d{3}[\s.-])\d{3}[\s.-]\d{4}(?![\w.-])/],
  ['a street address', /\b\d{1,5}\s+(?:[A-Z][a-z]+\s+){1,3}(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Way|Place|Pl|Terrace|Crescent)\b/],
  ['a location value', /-?\b\d{1,2}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}\b|"(?:lat|lng|lon|latitude|longitude)"\s*:\s*-?\d/i],
  ['a health value', /\b\d{2,3}\s?bpm\b|\b\d{1,3}(?:,\d{3})+\s+steps\b|\b\d{3,}\s+steps\b|\b\d{2,3}\/\d{2,3}\s?mm\s?Hg\b|\bslept\s+\d|"(?:heart_?rate|steps|bpm|weight)"\s*:\s*\d/i],
];
const NOTE_FILE = /^(openspec|wiki)\/|\.mdx?$/i;
// Copied libraries are public already, under their makers' names.
const NOT_OURS = /^vendor\//;

const BUFFER = 512 * 1024 * 1024;
const run = (root, args, input) => execFileSync('git', ['-C', root, ...args], { input, maxBuffer: BUFFER, stdio: ['pipe', 'pipe', 'pipe'] });
const text = (root, args) => run(root, args).toString('utf8');

/** Each file that must not go public, with why; `secrets` are the private .env values. Never returns a value. */
export function blocked(files, secrets) {
  return files.flatMap(({ path, text: body }) => {
    const why = PRIVATE_PATH.test(path) ? 'a key file or private note'
      : KEY_TEXT.test(body) ? 'text shaped like a key'
        : secrets.some(value => body.includes(value)) ? 'a value from .env' : null;
    return why ? [{ path, why }] : [];
  });
}

/** The .env values long enough to recognise, but those under `skip`; short ones like `0` would match everywhere. */
export function envSecrets(body, skip = []) {
  return Object.entries(parseEnv(body)).filter(([name, value]) => !skip.includes(name) && value.length >= 8).map(([, value]) => value);
}

/** The private values on this computer: the primary worktree's and this worktree's .env and app/.dev.vars. */
export function localSecrets(root) {
  let primary = root;
  try {
    ({ primary } = primaryRoot(root));
  } catch {
    // Not a linked worktree Git can place: this checkout's own files are all there is.
  }
  const files = [...new Set([primary, root])].flatMap(dir => SECRET_FILES.map(file => join(dir, file))).filter(existsSync);
  return [...new Set(files.flatMap(file => envSecrets(readFileSync(file, 'utf8'), PUBLIC_NAMES)))];
}

/** Every file Git tracks, or would track, in the checkout at `root`, read from disk. Links are skipped. */
export function treeFiles(root) {
  return text(root, ['ls-files', '-z', '--cached', '--others', '--exclude-standard']).split('\0').filter(Boolean)
    .filter((path, index, all) => all.indexOf(path) === index)
    .filter(path => existsSync(join(root, path)) && lstatSync(join(root, path)).isFile())
    .map(path => ({ path, text: readFileSync(join(root, path), 'latin1') }));
}

/** Each path and each file content in every commit any ref reaches, once, at the oldest commit holding it. */
export function historyFiles(root) {
  const commits = text(root, ['rev-list', '--all', '--reverse', '--topo-order']).split('\n').filter(Boolean);
  const paths = new Map();
  const blobs = new Map();
  for (const commit of commits) {
    for (const entry of text(root, ['ls-tree', '-r', '-z', commit]).split('\0').filter(Boolean)) {
      const [meta, path] = entry.split('\t');
      const [mode, type, sha] = meta.split(' ');
      if (type !== 'blob' || mode === '120000') continue;
      if (!paths.has(path)) paths.set(path, commit);
      if (!blobs.has(sha)) blobs.set(sha, { commit, path });
    }
  }
  const contents = readBlobs(root, [...blobs.keys()]);
  return {
    paths: [...paths].map(([path, commit]) => ({ commit, path })),
    blobs: [...blobs].map(([sha, where]) => ({ ...where, text: contents.get(sha) })),
    messages: commits.map(commit => ({ commit, text: text(root, ['log', '-1', '--format=%B', commit]) })),
  };
}

function readBlobs(root, shas) {
  const contents = new Map();
  if (!shas.length) return contents;
  const out = run(root, ['cat-file', '--batch'], `${shas.join('\n')}\n`);
  let at = 0;
  while (at < out.length) {
    const end = out.indexOf(0x0a, at);
    const [sha, , size] = out.subarray(at, end).toString('latin1').split(' ');
    const length = Number(size);
    contents.set(sha, out.subarray(end + 1, end + 1 + length).toString('latin1'));
    at = end + 1 + length + 1;
  }
  return contents;
}

const short = commit => commit.slice(0, 10);

/** Refusals in the files here now: `<path> (<why>)`. */
export function checkTree(root, secrets) {
  return blocked(treeFiles(root), secrets).map(({ path, why }) => `${path} (${why})`);
}

/** Refusals anywhere in history: `<commit>:<path> (<why>)`, a commit message as `<commit>:(message)`. */
export function checkHistory(root, secrets) {
  const { paths, blobs, messages } = historyFiles(root);
  const named = blocked(paths.map(({ path }) => ({ path, text: '' })), []).map(({ path }) => path);
  const hits = [
    ...paths.filter(({ path }) => named.includes(path)).map(({ commit, path }) => `${short(commit)}:${path} (a key file or private note)`),
    ...blobs.filter(({ path }) => !named.includes(path)).flatMap(({ commit, path, text: body }) =>
      blocked([{ path: 'file', text: body }], secrets).map(({ why }) => `${short(commit)}:${path} (${why})`)),
    ...messages.flatMap(({ commit, text: body }) =>
      blocked([{ path: 'message', text: body }], secrets).map(({ why }) => `${short(commit)}:(message) (${why})`)),
  ];
  return [...new Set(hits)];
}

/** The emails commits are made under: the authors' own, which may be public. */
export function authorEmails(root) {
  return new Set(text(root, ['log', '--all', '--format=%ae%n%ce']).split('\n').filter(Boolean).map(email => email.toLowerCase()));
}

/** Kinds of private detail on one line, never the detail itself. */
export function noteKinds(line, authors) {
  const kinds = NOTE_KINDS.filter(([, pattern]) => pattern.test(line)).map(([kind]) => kind);
  const emails = (line.match(EMAIL) ?? []).filter(email => !authors.has(email.toLowerCase()) && !PUBLIC_EMAIL.test(email));
  return emails.length ? [...kinds, 'an email address'] : kinds;
}

/** Lines in plans, the wiki and Markdown, in every commit, that may name a person's private detail. */
export function listNotes(root) {
  const authors = authorEmails(root);
  return historyFiles(root).blobs
    .filter(({ path }) => NOTE_FILE.test(path) && !NOT_OURS.test(path))
    .flatMap(({ commit, path, text: body }) => body.split('\n').flatMap((line, index) =>
      noteKinds(line, authors).map(kind => `${short(commit)}:${path}:${index + 1} ${kind}`)));
}

function main() {
  const { values } = parseCli({
    usage: USAGE,
    options: { tree: { type: 'boolean' }, history: { type: 'boolean' }, notes: { type: 'boolean' } },
  });
  if ([values.tree, values.history, values.notes].filter(Boolean).length > 1) usageError(USAGE, 'choose one of --tree, --history, --notes');
  const root = text(process.cwd(), ['rev-parse', '--show-toplevel']).trim();
  if (values.notes) {
    const notes = listNotes(root);
    for (const note of notes) console.log(note);
    console.log(`result=listed ${notes.length}`);
    return;
  }
  const secrets = localSecrets(root);
  const hits = values.history ? checkHistory(root, secrets) : checkTree(root, secrets);
  if (!hits.length) return console.log('result=clean');
  console.log(`result=refused ${hits.join(', ')}`);
  process.exitCode = 1;
}

if (isMain(import.meta.url)) main();
