#!/usr/bin/env node
// Relay Everything's AI connector trial: drives the sign-in an AI app runs, then prints one line per check. It needs
// no person, except --sign-in, which asks a person to sign in once. wiki/stack/relay-ai-connector.md#try-it
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { parseEnv } from 'node:util';
import { primaryRoot } from '../.claude/skills/memory/scripts/lib/primary-root.mjs';
import { isMain, parseCli, usageError } from './lib-cli.mjs';
import { parseConfig, repoRoot } from './lib-wrangler-config.mjs';
import { target } from './relay-mcp-setup.mjs';

const USAGE = `usage: node scripts/relay-mcp-trial.mjs [--live | --sign-in]
  (none)     the staging connector, with no sign-in: metadata, an app's registration, the consent page, the hand-off
             to the server's sign-in, and each refusal
  --sign-in  the same, then a person signs in once in a browser on this computer; the app's token reads their notes
             and adds a made-up note, through /mcp and through the web API
  --live     the live connector: it answers its metadata and refuses /mcp and /v1/ with no token`;

const APP_NAME = 'Relay Everything trial';
const WAIT = 10 * 60 * 1000;

export function parseArgs(args) {
  const { values } = parseCli({ usage: USAGE, args, options: { live: { type: 'boolean' }, 'sign-in': { type: 'boolean' } } });
  if (values.live && values['sign-in']) usageError(USAGE, '--sign-in tries the staging connector only');
  return { live: !!values.live, signIn: !!values['sign-in'] };
}

/** A PKCE pair, as an AI app makes one. */
export function pkce() {
  const verifier = randomBytes(32).toString('base64url');
  return { verifier, challenge: createHash('sha256').update(verifier).digest('base64url') };
}

/** The cookies a browser keeps between two pages. */
export function cookieJar() {
  const cookies = new Map();
  return {
    header: () => [...cookies].map(([name, value]) => `${name}=${value}`).join('; '),
    keep(response) {
      for (const cookie of response.headers.getSetCookie()) {
        const [, name, value] = /^([^=]+)=([^;]*)/.exec(cookie) ?? [];
        if (name && value) cookies.set(name, value); else if (name) cookies.delete(name);
      }
    },
  };
}

/** The `code` the connector sent back to the app's address: from the browser, or from a pasted address. */
function waitForCode(server) {
  return new Promise((resolve, reject) => {
    const lines = createInterface({ input: process.stdin });
    const done = (code, error) => { clearTimeout(timer); lines.close(); server.close(); error ? reject(error) : resolve(code); };
    const timer = setTimeout(() => done(null, new Error('no sign-in came back in 10 minutes')), WAIT);
    const codeOf = text => { try { return new URL(text.trim()).searchParams.get('code'); } catch { return null; } };
    server.on('request', (request, response) => {
      const code = codeOf(`http://127.0.0.1${request.url}`);
      response.end(code ? 'Signed in. You can close this page.' : 'No sign-in code here.');
      if (code) done(code);
    });
    lines.on('line', line => { const code = codeOf(line); if (code) done(code); });
  });
}

/** One trial. `request` is fetch; a test can stand in for it. Answers whether every check passed. */
export async function trial({ live, signIn, env, request = fetch, log = console.log }) {
  const goal = target(parseConfig(join(repoRoot, 'app', 'wrangler.relay-mcp.jsonc')), !live);
  const origin = new URL(goal.address).origin;
  let passed = true;
  const check = (name, ok, detail = '') => { passed &&= ok; log(ok ? `ok ${name}` : `failed ${name}${detail && `: ${detail}`}`); };
  const mcp = (headers = {}, body = { method: 'tools/list' }) => request(`${origin}/mcp`, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream', ...headers },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, ...body }) });
  const json = async response => response.ok ? response.json() : {};
  const api = (path, headers = {}, init = {}) => request(`${origin}/v1/${path}`, { ...init, headers: { ...headers, ...init.headers } });

  log(`Trying ${goal.worker} at ${origin}`);
  const metadata = await request(`${origin}/.well-known/oauth-authorization-server`);
  check('answers its OAuth metadata', (await json(metadata)).registration_endpoint === `${origin}/register`, `${metadata.status}`);
  const bare = await mcp();
  check('refuses /mcp with no token', bare.status === 401, `${bare.status}`);
  const anonymous = await api('me');
  check('refuses the web API with no token', anonymous.status === 401, `${anonymous.status}`);
  if (live) return passed;

  const described = await api('openapi.json');
  check('describes the web API with no sign-in', (await json(described)).openapi === '3.1.0', `${described.status}`);
  // A well-formed key the server never made: the web API refuses it before it reads anything.
  const unknownKey = await api('me', { Authorization: `Bearer rek_${'x'.repeat(43)}` });
  check("refuses an unknown key on the web API", unknownKey.status === 403, `${unknownKey.status}`);

  const resource = await request(`${origin}/.well-known/oauth-protected-resource/mcp`);
  check('names its /mcp as the resource', (await json(resource)).resource === goal.address, `${resource.status}`);
  const wrong = await mcp({ Authorization: 'Bearer made-up-person:made-up-grant:made-up-token' });
  check('refuses a wrong token', wrong.status === 401, `${wrong.status}`);
  const checker = env.CF_ACCESS_STAGING_CLIENT_ID && { 'CF-Access-Client-Id': env.CF_ACCESS_STAGING_CLIENT_ID,
    'CF-Access-Client-Secret': env.CF_ACCESS_STAGING_CLIENT_SECRET ?? '' };
  if (checker) {
    const viaKey = await mcp(checker);
    check('refuses a service token', viaKey.status === 401, `${viaKey.status}`);
  }

  const server = signIn ? createServer() : null;
  if (server) await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const redirect = `http://127.0.0.1:${server?.address().port ?? 8976}/callback`;
    const registered = await request(`${origin}/register`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ client_name: APP_NAME, redirect_uris: [redirect], token_endpoint_auth_method: 'none' }) });
    const { client_id: clientId } = await json(registered);
    check('lets an AI app register itself', !!clientId, `${registered.status}`);
    if (!clientId) return false;

    const { verifier, challenge } = pkce();
    const authorize = `${origin}/authorize?${new URLSearchParams({ response_type: 'code', client_id: clientId, redirect_uri: redirect,
      code_challenge: challenge, code_challenge_method: 'S256', state: 'relay-trial', resource: goal.address })}`;
    const jar = cookieJar();
    const consent = await request(authorize, { redirect: 'manual' });
    jar.keep(consent);
    const page = await consent.text();
    const handle = /name="handle" value="([^"]+)"/.exec(page)?.[1];
    check('shows a consent page that names the app', consent.status === 200 && page.includes(`Connect ${APP_NAME} to Relay Everything?`) && !!handle,
      `${consent.status}`);
    const approved = await request(`${origin}/authorize`, { method: 'POST', redirect: 'manual', headers: { Cookie: jar.header() },
      body: new URLSearchParams({ handle: handle ?? '', choice: 'approve' }) });
    const signInPage = new URL(approved.headers.get('Location') ?? 'about:blank');
    check("sends an approved app on to the server's sign-in", approved.status === 302 && !!signInPage.searchParams.get('state')
      && `${signInPage.origin}${signInPage.pathname}` === `${goal.server}/apps/relay/sign-in/connect`, `${approved.status} ${signInPage.hostname}`);
    if (signInPage.protocol === 'https:') {
      // No one is signed in here, so the server must not send a code back to the connector.
      const stranger = await request(signInPage.href, { redirect: 'manual' });
      check('the server sends no code to someone not signed in', !(stranger.headers.get('Location') ?? '').startsWith(`${origin}/callback`),
        `${stranger.status}`);
    }
    const forged = await request(`${origin}/callback?${new URLSearchParams({ code: 'made-up', state: 'made-up' })}`, { redirect: 'manual' });
    check('refuses a made-up sign-in answer', [400, 403].includes(forged.status), `${forged.status}`);
    const exchange = code => request(`${origin}/token`, { method: 'POST',
      body: new URLSearchParams({ grant_type: 'authorization_code', code, redirect_uri: redirect, client_id: clientId, code_verifier: verifier }) });
    const madeUp = await exchange('made-up');
    check('gives no token for a made-up code', madeUp.status === 400, `${madeUp.status}`);
    if (!server) return passed;

    log('Open this link in a browser on this computer, click Connect, and sign in to Relay Everything.');
    log('If the browser is on another computer, paste the address it ends on here.');
    log(authorize);
    const { access_token: token } = await json(await exchange(await waitForCode(server)));
    check("the person's sign-in gives the app a token", !!token);
    if (!token) return false;
    const found = await mcp({ Authorization: `Bearer ${token}` }, { method: 'tools/call', params: { name: 'search', arguments: { query: 'milk' } } });
    check("the token reads the person's notes", !!(await json(found)).result?.content, `${found.status}`);
    const bearer = { Authorization: `Bearer ${token}` };
    const listed = await api('notes?q=milk', bearer);
    check("the token reads the person's notes on the web API", Array.isArray((await json(listed)).notes), `${listed.status}`);
    const note = text => ({ clientId: `trial-${randomUUID()}`, text });
    const added = await api('notes', bearer, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(note('A made-up note from the Relay Everything trial, through the web API.')) });
    check('the token adds a note on the web API', added.status === 201, `${added.status}`);
    const tool = await mcp(bearer, { method: 'tools/call', params: { name: 'add_note',
      arguments: note('A made-up note from the Relay Everything trial, through add_note.') } });
    const toolAnswer = (await json(tool)).result;
    check('the token adds a note with add_note', !!toolAnswer?.content && !toolAnswer.isError, `${tool.status}`);
    log(`Disconnect "${APP_NAME}" on the preview's AI apps card when you are done. Its two made-up notes stay.`);
    return passed;
  } finally {
    server?.close();
  }
}

if (isMain(import.meta.url)) {
  const file = join(primaryRoot(process.cwd()).primary, '.env');
  const env = existsSync(file) ? parseEnv(readFileSync(file, 'utf8')) : {};
  trial({ ...parseArgs(process.argv.slice(2)), env }).then(passed => {
    console.log(passed ? 'trial: pass' : 'trial: fail');
    process.exitCode = passed ? 0 : 1;
  }, error => {
    console.error(`relay-mcp-trial: ${error.message}`);
    process.exitCode = 1;
  });
}
