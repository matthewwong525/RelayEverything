// Hides keys in chat text before it leaves the computer. The shapes copy the memory store's scan.mjs by name, so a
// test fails when one list gains a shape the other lacks; private key blocks and Slack tokens are added here.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

export const HIDDEN = '[hidden]';
const MIN_VALUE = 8;
export const SHAPES = [
  ['GitHub token', /\bgh[pousr]_[A-Za-z0-9]{20,}/g],
  ['GitHub fine-grained token', /\bgithub_pat_[A-Za-z0-9_]{20,}/g],
  ['API key (sk-)', /\bsk-[A-Za-z0-9_-]{20,}/g],
  ['AWS access key', /\bAKIA[0-9A-Z]{16}\b/g],
  ['JWT', /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g],
  ['Memory login marker', /\bwongl_[A-Za-z0-9_-]{43}\b/g],
  ['Memory key', /\bwongm_[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{20,}/g],
  ['Bearer header', /\b(Bearer\s+)[A-Za-z0-9._~+/=-]{20,}/g],
  ['Private key block', /-----BEGIN ([A-Z ]*)PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)/g],
  ['Slack token', /\bxox[abposr]-[A-Za-z0-9-]{10,}/g],
];

/** The nearest file of this name in `dir` or a folder above it, or null. */
function nearest(dir, name) {
  for (let at = dir; ; at = dirname(at)) {
    if (existsSync(join(at, name))) return join(at, name);
    if (dirname(at) === at) return null;
  }
}

/** Values of 8 characters or more from the nearest `.env` and `.dev.vars`, longest first. */
export function envValues(cwd) {
  const values = ['.env', '.dev.vars'].flatMap(name => {
    const file = nearest(cwd, name);
    if (!file) return [];
    return readFileSync(file, 'utf8').split('\n').map(line => /^\s*(?:export\s+)?[A-Za-z_]\w*\s*=\s*(.*)$/.exec(line)?.[1].trim())
      .filter(Boolean).map(value => value.replace(/^(['"])(.*)\1$/, '$2'));
  });
  return [...new Set(values.filter(value => value.length >= MIN_VALUE))].sort((a, b) => b.length - a.length);
}

/** Hides `.env` values, then every key shape; a Bearer header keeps its word. */
export function hide(text, values = []) {
  const known = values.reduce((out, value) => out.split(value).join(HIDDEN), text);
  return SHAPES.reduce((out, [name, shape]) =>
    out.replace(shape, (_, bearer) => name === 'Bearer header' ? `${bearer}${HIDDEN}` : HIDDEN), known);
}

/** A hide function for chats run in `cwd`. */
export function hider(cwd) {
  let values = [];
  try {
    values = envValues(cwd);
  } catch {
    // An unreadable .env still leaves every key shape hidden.
  }
  return text => hide(text, values);
}
