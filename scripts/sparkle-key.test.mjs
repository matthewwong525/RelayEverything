// Run with: node --test scripts/sparkle-key.test.mjs
import assert from 'node:assert/strict';
import { createPublicKey, verify } from 'node:crypto';
import test from 'node:test';
import { NAME, edSignature, newSeed, privateKeyOf, publicKeyOf, run } from './sparkle-key.mjs';

// A fixed seed: RFC 8032's first Ed25519 test key, and its public key in Sparkle's base64 form.
const SEED = Buffer.from('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60', 'hex').toString('base64');
const PUBLIC = Buffer.from('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', 'hex').toString('base64');

test("a seed in Sparkle's form gives its public key and signatures that the public key accepts", () => {
  assert.equal(publicKeyOf(SEED), PUBLIC);
  const file = Buffer.from('a disk image');
  const signature = edSignature(SEED, file);
  assert.equal(Buffer.from(signature, 'base64').length, 64);
  const key = createPublicKey({ key: { kty: 'OKP', crv: 'Ed25519', x: Buffer.from(PUBLIC, 'base64').toString('base64url') }, format: 'jwk' });
  assert.ok(verify(null, file, key, Buffer.from(signature, 'base64')));
  // RFC 8032's signature of the empty message, so the form matches Sparkle's own signer byte for byte.
  assert.equal(Buffer.from(edSignature(SEED, Buffer.alloc(0)), 'base64').toString('hex'),
    'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b');
});

test('a new seed is 32 bytes of base64, and a seed of another length is refused', () => {
  const seed = newSeed();
  assert.equal(Buffer.from(seed, 'base64').length, 32);
  assert.notEqual(seed, newSeed());
  assert.throws(() => privateKeyOf(Buffer.alloc(64).toString('base64')), /base64 32-byte Ed25519 seed/);
});

test('a first run saves a new key and prints only its public half', () => {
  const saved = [];
  const line = run({ env: {}, save: values => saved.push(values), make: () => SEED });
  assert.deepEqual(saved, [{ [NAME]: SEED }]);
  assert.equal(line, `result=made public=${PUBLIC}`);
  assert.doesNotMatch(line, new RegExp(SEED.replace(/[+/]/g, '\\$&')));
});

test('a saved key is never replaced without --renew, in .env or on GitHub', () => {
  const save = () => assert.fail('saved');
  assert.equal(run({ env: { [NAME]: SEED }, save, ready: save }), `result=kept public=${PUBLIC}`);
  assert.match(run({ env: {}, onGitHub: () => true, save }), /^result=kept .* is a GitHub secret but not in \.env/);
  const saved = [];
  run({ env: { [NAME]: SEED }, onGitHub: () => true, save: values => saved.push(values), renew: true, make: () => 'AAAA' + SEED.slice(4) });
  assert.equal(saved.length, 1);
});

test('a failed gh check stops before a key is made', () => {
  const ready = () => { throw new Error('gh auth status failed'); };
  assert.throws(() => run({ env: {}, save: () => assert.fail('saved'), ready, make: () => assert.fail('made') }), /gh auth/);
});
