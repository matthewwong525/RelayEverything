#!/usr/bin/env node
// Makes the one Apple Distribution certificate that signs every iPhone build, and stores it where the build reads it.
// Spec: openspec/specs/relay-app-builds/spec.md. The yearly renewal and the revoke step: wiki/open-source.md#phone-builds.
import { spawnSync } from 'node:child_process';
import { createPrivateKey, randomBytes, sign } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { isMain, parseCli } from './lib-cli.mjs';
import { primaryRoot } from '../.claude/skills/memory/scripts/lib/primary-root.mjs';
import { parseEnv } from '../.claude/skills/memory/scripts/lib/store.mjs';

const USAGE = `usage: node scripts/ios-signing-cert.mjs [--renew]

Reads the App Store Connect key (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8) from the primary worktree's .env. When the
saved certificate is still on Apple's account and has more than 30 days left, it keeps it. Else it asks Apple for a
new Apple Distribution certificate, makes the .p12 with a new password in a temporary folder, and writes
IOS_DIST_CERT_P12 and IOS_DIST_CERT_PASSWORD to .env and to the repository's GitHub secrets.

--renew   make a new certificate even when the saved one is still good

Prints one result= line with the certificate id and expiry only: made, kept, full (revoke one first), or failed.`;

export const REPO = 'matthewwong525/RelayEverything';
export const NAMES = { p12: 'IOS_DIST_CERT_P12', password: 'IOS_DIST_CERT_PASSWORD' };
const API = 'https://api.appstoreconnect.apple.com/v1';
// Apple allows a team three distribution certificates; Apple Distribution and the older iOS Distribution share them.
export const LIMIT = 3;
const KINDS = ['DISTRIBUTION', 'IOS_DISTRIBUTION'];
const RENEW_DAYS = 30;
const DAY_MS = 24 * 60 * 60 * 1000;
export const CERTIFICATES_PAGE = 'https://developer.apple.com/account/resources/certificates/list';

const b64url = value => Buffer.from(typeof value === 'string' ? value : JSON.stringify(value)).toString('base64url');

/** A 20-minute App Store Connect token, signed ES256 with the key's .p8 text. */
export function ascToken({ keyId, issuerId, p8 }, now = Date.now()) {
  const iat = Math.floor(now / 1000);
  const head = `${b64url({ alg: 'ES256', kid: keyId, typ: 'JWT' })}.${b64url({ iss: issuerId, iat, exp: iat + 20 * 60, aud: 'appstoreconnect-v1' })}`;
  const signature = sign('sha256', Buffer.from(head), { key: createPrivateKey(p8), dsaEncoding: 'ieee-p1363' });
  return `${head}.${signature.toString('base64url')}`;
}

/** The distribution certificates that still count against Apple's limit. */
export const active = (certificates, now = Date.now()) => certificates.filter(({ attributes: a }) =>
  KINDS.includes(a.certificateType) && Date.parse(a.expirationDate) > now);

/** Null while there is room for one more; else what the person does on developer.apple.com. */
export function limitMessage(certificates, now = Date.now()) {
  const list = active(certificates, now);
  if (list.length < LIMIT) return null;
  const names = list.map(({ id, attributes: a }) => `${a.displayName ?? a.name} (${id}, ends ${a.expirationDate.slice(0, 10)})`);
  return `Apple's account holds ${list.length} distribution certificates, its limit. On ${CERTIFICATES_PAGE}, revoke one that no build uses, then run this again: ${names.join('; ')}`;
}

// openssl prints whole bytes, so a serial can start with a zero that Apple's list drops.
const bareSerial = serial => serial.toUpperCase().replace(/^0+/, '');

/** The saved certificate's entry on Apple, when it is there and has more than 30 days left. */
export function keepable(certificates, serial, now = Date.now()) {
  if (!serial) return null;
  return active(certificates, now).find(({ attributes: a }) =>
    a.serialNumber && bareSerial(a.serialNumber) === bareSerial(serial) && Date.parse(a.expirationDate) - now > RENEW_DAYS * DAY_MS) ?? null;
}

/** The .env text with `name` set to `value`, in place when the line exists, else added at the end. */
export function setEnvLine(body, name, value) {
  const line = `${name}=${value}`;
  const pattern = new RegExp(`^${name}=.*$`, 'm');
  if (pattern.test(body)) return body.replace(pattern, () => line);
  return `${body}${body === '' || body.endsWith('\n') ? '' : '\n'}${line}\n`;
}

function openssl(args, env = {}) {
  const out = spawnSync('openssl', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...env } });
  // openssl's own error text never holds a password: those go in through the environment.
  if (out.status !== 0) throw new Error(`openssl ${args[0]} failed: ${out.stderr.trim().split('\n')[0]}`);
  return out.stdout;
}

/** The serial number of the certificate in a base64 .p12, or null when it can't be read. */
export function p12Serial(p12, password, dir) {
  if (!p12 || !password) return null;
  const file = join(dir, 'saved.p12');
  writeFileSync(file, Buffer.from(p12, 'base64'), { mode: 0o600 });
  try {
    const pem = openssl(['pkcs12', '-in', file, '-nokeys', '-clcerts', '-passin', 'env:RELAY_P12_PASS'], { RELAY_P12_PASS: password });
    const out = spawnSync('openssl', ['x509', '-noout', '-serial'], { input: pem, encoding: 'utf8' });
    return out.status === 0 ? out.stdout.trim().replace(/^serial=/, '') : null;
  } catch {
    return null;
  }
}

/** A new private key and its certificate request, in `dir`. Returns the request's PEM text. */
export function makeRequest(dir) {
  openssl(['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', join(dir, 'key.pem'), '-out', join(dir, 'request.csr'),
    '-subj', '/CN=Relay Everything iPhone builds']);
  return readFileSync(join(dir, 'request.csr'), 'utf8');
}

/** The base64 .p12 of Apple's certificate (base64 DER) and the key in `dir`, locked with `password`. */
export function makeP12(dir, certificateContent, password) {
  writeFileSync(join(dir, 'apple.cer'), Buffer.from(certificateContent, 'base64'));
  openssl(['x509', '-inform', 'DER', '-in', join(dir, 'apple.cer'), '-out', join(dir, 'apple.pem')]);
  // SHA1 and 3DES, so the Mac's keychain on the build machine can open the file.
  openssl(['pkcs12', '-export', '-inkey', join(dir, 'key.pem'), '-in', join(dir, 'apple.pem'), '-name', 'Apple Distribution',
    '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1',
    '-out', join(dir, 'signing.p12'), '-passout', 'env:RELAY_P12_PASS'], { RELAY_P12_PASS: password });
  return readFileSync(join(dir, 'signing.p12')).toString('base64');
}

/** Calls the App Store Connect API; Apple's error detail never holds a key. */
export function appleApi(key) {
  return async (method, path, body) => {
    const response = await fetch(`${API}${path}`, {
      method,
      headers: { authorization: `Bearer ${ascToken(key)}`, 'content-type': 'application/json' },
      body: body && JSON.stringify(body),
    });
    const json = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(`Apple answered ${response.status}: ${json.errors?.[0]?.detail ?? json.errors?.[0]?.title ?? 'no detail'}`);
    return json;
  };
}

function gh(args, input) {
  const out = spawnSync('gh', args, { input, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  if (out.status !== 0) throw new Error(`gh ${args.slice(0, 2).join(' ')} failed: ${(out.stderr ?? out.error?.message ?? '').trim().split('\n')[0]}`);
}

/** Throws when gh can't set the secrets, so the check runs before Apple spends a certificate place. */
export const ghReady = () => gh(['auth', 'status']);

/** Writes every value to each .env first, so the .p12 and its password always match there, then to GitHub. */
export function saveValues(envFiles, repo) {
  return values => {
    for (const file of envFiles) {
      const body = existsSync(file) ? readFileSync(file, 'utf8') : '';
      writeFileSync(file, Object.entries(values).reduce((text, [name, value]) => setEnvLine(text, name, value), body));
    }
    for (const [name, value] of Object.entries(values)) gh(['secret', 'set', name, '--repo', repo], value);
  };
}

// The whole step, with Apple, the saving and the output passed in. Returns the result= line; `log` gets only
// that line, so no key, password or certificate reaches the screen.
export async function run({ env, api, save, ready = () => {}, log, renew = false, now = Date.now() }) {
  const dir = mkdtempSync(join(tmpdir(), 'relay-ios-cert-'));
  try {
    const { data: certificates } = await api('GET', `/certificates?filter[certificateType]=${KINDS.join(',')}&limit=200`);
    const kept = !renew && keepable(certificates, p12Serial(env[NAMES.p12], env[NAMES.password], dir), now);
    let line;
    if (kept) line = `result=kept id=${kept.id} expires=${kept.attributes.expirationDate.slice(0, 10)}`;
    else if (limitMessage(certificates, now)) line = `result=full ${limitMessage(certificates, now)}`;
    else {
      ready();
      const csrContent = makeRequest(dir);
      const { data } = await api('POST', '/certificates', { data: { type: 'certificates', attributes: { certificateType: 'DISTRIBUTION', csrContent } } });
      const password = randomBytes(24).toString('base64url');
      const p12 = makeP12(dir, data.attributes.certificateContent, password);
      save({ [NAMES.p12]: p12, [NAMES.password]: password });
      line = `result=made id=${data.id} expires=${data.attributes.expirationDate.slice(0, 10)}`;
    }
    log(line);
    return line;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** The .env files this computer keeps: the primary worktree's, and this worktree's own copy when it has one. */
function envFiles() {
  const { root, primary } = primaryRoot();
  return [...new Set([primary, root])].map(dir => join(dir, '.env')).filter(existsSync);
}

if (isMain(import.meta.url)) {
  const { values } = parseCli({ usage: USAGE, options: { renew: { type: 'boolean' } } });
  const files = envFiles();
  // The primary worktree's values win; this worktree's copy fills gaps.
  const env = Object.assign({}, ...files.slice().reverse().map(file => parseEnv(readFileSync(file, 'utf8'))));
  const missing = ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_P8'].filter(name => !env[name]);
  if (missing.length) {
    console.log(`result=failed no ${missing.join(', ')} in .env (see .env.example)`);
    process.exit(1);
  }
  const key = { keyId: env.ASC_KEY_ID, issuerId: env.ASC_ISSUER_ID, p8: Buffer.from(env.ASC_KEY_P8, 'base64').toString('utf8') };
  try {
    const line = await run({ env, api: appleApi(key), save: saveValues(files, REPO), ready: ghReady, log: console.log, renew: values.renew });
    process.exit(line.startsWith('result=full') ? 1 : 0);
  } catch (error) {
    console.log(`result=failed ${error.message}`);
    process.exit(1);
  }
}
