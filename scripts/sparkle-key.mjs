#!/usr/bin/env node
// Makes the Ed25519 key that signs each Mac app update, which the app checks before it installs one. Only its public
// half goes in the app (mobile/macos/Runner/Info.plist). mobile/README.md#the-mac-app says why a new key is a last resort.
import { spawnSync } from 'node:child_process';
import { createPrivateKey, createPublicKey, generateKeyPairSync, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { isMain, parseCli } from './lib-cli.mjs';
import { REPO, envFiles, ghReady, saveValues } from './ios-signing-cert.mjs';
import { parseEnv } from '../.claude/skills/memory/scripts/lib/store.mjs';

const USAGE = `usage: node scripts/sparkle-key.mjs [--renew]

Makes the key that signs each Mac app update, and writes it as SPARKLE_ED_PRIVATE_KEY to .env and to the repository's
GitHub secrets. Prints one result= line with the public key, for SUPublicEDKey in mobile/macos/Runner/Info.plist.

When a key is already saved, in .env or on GitHub, it makes none and prints the saved key's public half when .env has it.
--renew   make a new key anyway. Every installed Mac app then refuses each update, until the person installs one by hand.`;

export const NAME = 'SPARKLE_ED_PRIVATE_KEY';
// The DER start of an Ed25519 PKCS#8 private key, before its 32-byte seed.
const PKCS8_START = Buffer.from('302e020100300506032b657004220420', 'hex');

/** The private key from Sparkle's own form: the base64 32-byte seed that its `generate_keys -x` writes. */
export function privateKeyOf(seed) {
  const bytes = Buffer.from(seed ?? '', 'base64');
  if (bytes.length !== 32) throw new Error(`${NAME} must be a base64 32-byte Ed25519 seed`);
  return createPrivateKey({ key: Buffer.concat([PKCS8_START, bytes]), format: 'der', type: 'pkcs8' });
}

const base64 = base64url => Buffer.from(base64url, 'base64url').toString('base64');

/** SUPublicEDKey: the base64 32-byte public key. */
export const publicKeyOf = seed => base64(createPublicKey(privateKeyOf(seed)).export({ format: 'jwk' }).x);

/** `sparkle:edSignature`: the base64 Ed25519 signature of the whole file. */
export const edSignature = (seed, bytes) => sign(null, bytes, privateKeyOf(seed)).toString('base64');

/** A new seed, in Sparkle's form. */
export const newSeed = () => base64(generateKeyPairSync('ed25519').privateKey.export({ format: 'jwk' }).d);

// The whole step, with GitHub, the saving and the new key passed in. Returns the result= line: no private key.
export function run({ env, onGitHub = () => false, save, ready = () => {}, renew = false, make = newSeed }) {
  if (!renew && env[NAME]) return `result=kept public=${publicKeyOf(env[NAME])}`;
  if (!renew && onGitHub()) return `result=kept ${NAME} is a GitHub secret but not in .env: copy it to .env, or pass --renew`;
  ready();
  const seed = make();
  save({ [NAME]: seed });
  return `result=made public=${publicKeyOf(seed)}`;
}

function secretOnGitHub() {
  const out = spawnSync('gh', ['secret', 'list', '--repo', REPO, '--json', 'name'], { encoding: 'utf8' });
  if (out.status !== 0) throw new Error(`gh secret list failed: ${(out.stderr ?? '').trim().split('\n')[0]}`);
  return JSON.parse(out.stdout).some(secret => secret.name === NAME);
}

if (isMain(import.meta.url)) {
  const { values } = parseCli({ usage: USAGE, options: { renew: { type: 'boolean' } } });
  const files = envFiles();
  // The primary worktree's values win; this worktree's copy fills gaps.
  const env = Object.assign({}, ...files.slice().reverse().map(file => parseEnv(readFileSync(file, 'utf8'))));
  try {
    console.log(run({ env, onGitHub: secretOnGitHub, save: saveValues(files, REPO), ready: ghReady, renew: values.renew }));
  } catch (error) {
    console.log(`result=failed ${error.message}`);
    process.exit(1);
  }
}
