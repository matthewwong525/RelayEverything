// Run with: node --test scripts/ios-signing-cert.test.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { generateKeyPairSync, verify } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { CERTIFICATES_PAGE, LIMIT, NAMES, ascToken, keepable, limitMessage, p12Serial, run, setEnvLine } from './ios-signing-cert.mjs';

const now = Date.parse('2026-11-07T12:00:00Z');
const cert = (id, type, ends, serial = id) => ({ id, attributes: { certificateType: type, expirationDate: ends, displayName: `cert ${id}`, serialNumber: serial } });
const hasOpenssl = spawnSync('openssl', ['version']).status === 0;

test('the token is an ES256 JWT for App Store Connect that lives 20 minutes', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const token = ascToken({ keyId: 'KEY123', issuerId: 'issuer-1', p8: privateKey.export({ type: 'pkcs8', format: 'pem' }) }, now);
  const [head, body, signature] = token.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(head, 'base64url')), { alg: 'ES256', kid: 'KEY123', typ: 'JWT' });
  const claims = JSON.parse(Buffer.from(body, 'base64url'));
  assert.deepEqual(claims, { iss: 'issuer-1', iat: now / 1000, exp: now / 1000 + 1200, aud: 'appstoreconnect-v1' });
  assert.ok(verify('sha256', Buffer.from(`${head}.${body}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')));
});

test('a full account stops with the revoke step; expired and development certificates do not count', () => {
  const full = Array.from({ length: LIMIT }, (_, i) => cert(`d${i}`, i ? 'DISTRIBUTION' : 'IOS_DISTRIBUTION', '2027-06-01T00:00:00Z'));
  const message = limitMessage(full, now);
  assert.match(message, /revoke one/);
  assert.ok(message.includes(CERTIFICATES_PAGE));
  assert.match(message, /d0/);
  assert.equal(limitMessage([...full.slice(1), cert('old', 'DISTRIBUTION', '2026-01-01T00:00:00Z'), cert('dev', 'DEVELOPMENT', '2027-06-01T00:00:00Z')], now), null);
});

test('the saved certificate is kept only while Apple has it with more than 30 days left', () => {
  const list = [cert('a', 'DISTRIBUTION', '2027-06-01T00:00:00Z', '0ABC'), cert('b', 'DISTRIBUTION', '2026-11-20T00:00:00Z', '0DEF')];
  assert.equal(keepable(list, '0abc', now).id, 'a');
  assert.equal(keepable(list, '0DEF', now), null);
  assert.equal(keepable(list, '0999', now), null);
  assert.equal(keepable(list, null, now), null);
  assert.equal(keepable([cert('z', 'DISTRIBUTION', '2027-06-01T00:00:00Z', '7f1a')], '007F1A', now).id, 'z');
  assert.equal(keepable([cert('z', 'DISTRIBUTION', '2027-06-01T00:00:00Z', '007F1A')], '7f1a', now).id, 'z');
});

test('a .env line is replaced in place, or added at the end', () => {
  assert.equal(setEnvLine('A=1\nIOS_DIST_CERT_P12=old\nB=2\n', 'IOS_DIST_CERT_P12', 'n$&ew'), 'A=1\nIOS_DIST_CERT_P12=n$&ew\nB=2\n');
  assert.equal(setEnvLine('A=1', 'X', 'y'), 'A=1\nX=y\n');
  assert.equal(setEnvLine('', 'X', 'y'), 'X=y\n');
});

// A stand-in for Apple: it signs the request with its own made-up authority, as Apple's API would.
function fakeApple(dir, certificates) {
  spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', join(dir, 'ca.key'), '-out', join(dir, 'ca.pem'), '-days', '2', '-subj', '/CN=Test CA']);
  return async (method, path, body) => {
    if (method === 'GET') return { data: certificates };
    writeFileSync(join(dir, 'in.csr'), body.data.attributes.csrContent);
    spawnSync('openssl', ['x509', '-req', '-in', join(dir, 'in.csr'), '-CA', join(dir, 'ca.pem'), '-CAkey', join(dir, 'ca.key'), '-days', '2', '-outform', 'DER', '-out', join(dir, 'out.cer')]);
    return { data: { id: 'NEWCERT', attributes: { certificateContent: readFileSync(join(dir, 'out.cer')).toString('base64'), expirationDate: '2027-11-07T12:00:00.000+0000' } } };
  };
}

test('a new certificate is saved as a .p12 that opens with its password, and only its id and expiry are printed', { skip: !hasOpenssl }, async () => {
  const dir = mkdtempSync(join(tmpdir(), 'relay-cert-test-'));
  try {
    const saved = {};
    const printed = [];
    const line = await run({ env: {}, api: fakeApple(dir, []), save: values => Object.assign(saved, values), log: text => printed.push(text), now });
    assert.equal(line, 'result=made id=NEWCERT expires=2027-11-07');
    assert.deepEqual(printed, [line]);
    assert.deepEqual(Object.keys(saved), [NAMES.p12, NAMES.password]);
    assert.ok(saved[NAMES.password].length >= 24);
    for (const value of Object.values(saved)) assert.ok(!printed.join('\n').includes(value));
    assert.match(p12Serial(saved[NAMES.p12], saved[NAMES.password], dir), /^[0-9A-F]+$/);
    assert.equal(p12Serial(saved[NAMES.p12], 'wrong', dir), null);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a failed gh check stops before Apple makes a certificate', async () => {
  const api = async method => {
    assert.equal(method, 'GET');
    return { data: [] };
  };
  const ready = () => { throw new Error('gh auth status failed'); };
  await assert.rejects(run({ env: {}, api, save: () => assert.fail('saved'), ready, log: () => {}, now }), /gh auth status/);
});

test('a second run keeps the saved certificate, and --renew makes a new one', { skip: !hasOpenssl }, async () => {
  const dir = mkdtempSync(join(tmpdir(), 'relay-cert-test-'));
  try {
    const certificates = [];
    const apple = fakeApple(dir, certificates);
    const env = {};
    await run({ env: {}, api: apple, save: values => Object.assign(env, values), log: () => {}, now });
    const serial = p12Serial(env[NAMES.p12], env[NAMES.password], dir);
    certificates.push(cert('NEWCERT', 'DISTRIBUTION', '2027-11-07T12:00:00.000+0000', `00${serial.toLowerCase()}`));
    const noPost = async (method, ...rest) => (method === 'GET' ? apple(method, ...rest) : assert.fail('posted'));
    const kept = await run({ env, api: noPost, save: () => assert.fail('saved'), log: () => {}, now });
    assert.equal(kept, 'result=kept id=NEWCERT expires=2027-11-07');
    const saved = {};
    const renewed = await run({ env, api: apple, save: values => Object.assign(saved, values), log: () => {}, renew: true, now });
    assert.match(renewed, /^result=made /);
    assert.notEqual(saved[NAMES.password], env[NAMES.password]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a full account makes nothing and saves nothing', async () => {
  const full = Array.from({ length: LIMIT }, (_, i) => cert(`d${i}`, 'DISTRIBUTION', '2027-06-01T00:00:00Z'));
  const api = async method => {
    assert.equal(method, 'GET');
    return { data: full };
  };
  const line = await run({ env: {}, api, save: () => assert.fail('saved'), log: () => {}, now });
  assert.match(line, /^result=full /);
});
