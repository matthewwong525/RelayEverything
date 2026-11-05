// The connector's sign-in pages. /authorize asks the owner to approve the AI app by name, then sends them to the
// Access for SaaS sign-in; /callback checks Access's ID token and admits only WONG_OWNER_EMAIL.
import { AuthorizationError, type AuthRequest } from "@cloudflare/workers-oauth-provider";
import { owner, type McpEnv } from "./env.ts";

const html = (body: string, status = 200, headers = new Headers()) => {
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  return new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Relay</title><body style="font-family:system-ui;max-width:32rem;margin:3rem auto;padding:0 1rem">${body}</body>`, { status, headers });
};
const escape = (text: string) => text.replace(/[&<>"']/g, char => `&#${char.charCodeAt(0)};`);
const refused = (message: string, status = 400) => html(`<h1>Relay</h1><p>${escape(message)}</p>`, status);

/** The page that names the AI app and where its answers go, before any sign-in. */
async function consent(request: Request, env: McpEnv): Promise<Response> {
  let authRequest: AuthRequest;
  try {
    authRequest = await env.OAUTH_PROVIDER.parseAuthRequest(request);
  } catch {
    return refused("This connect link is not valid. Start again from your AI app.");
  }
  const about = await env.OAUTH_PROVIDER.describeConsent(authRequest);
  const { handle, headers } = await env.OAUTH_PROVIDER.beginConsent(authRequest);
  return html(`<h1>Connect ${escape(about.clientName)} to Relay?</h1>
<p>It can then read your Relay notes, health and places when you ask it. It can't change them.</p>
<p>Its answers go to <b>${escape(about.redirectHost)}</b>.${about.redirectIsLoopback ? " That is an app on this computer." : ""}</p>
<form method="post"><input type="hidden" name="handle" value="${escape(handle)}">
<button name="choice" value="approve">Connect</button> <button name="choice" value="deny">Cancel</button></form>`, 200, headers);
}

/** The approve or cancel button: cancel goes back to the app, approve on to the Access sign-in. */
async function chosen(request: Request, env: McpEnv): Promise<Response> {
  const form = await request.formData();
  const handle = String(form.get("handle") ?? "");
  if (form.get("choice") !== "approve") {
    const { headers } = await env.OAUTH_PROVIDER.denyConsent(request, handle);
    return new Response(null, { status: 302, headers });
  }
  const approved = await env.OAUTH_PROVIDER.approveConsent(request, handle);
  const { state, headers } = await env.OAUTH_PROVIDER.beginUpstream(approved.request, { headers: approved.headers });
  const signIn = new URL(env.ACCESS_AUTHORIZATION_URL);
  signIn.search = new URLSearchParams({ client_id: env.ACCESS_CLIENT_ID, redirect_uri: new URL("/callback", request.url).href,
    response_type: "code", scope: "openid email", state }).toString();
  headers.set("Location", signIn.href);
  return new Response(null, { status: 302, headers });
}

type Claims = { aud?: string | string[]; exp?: number; email?: string };
const decode = (segment: string) => Uint8Array.from(atob(segment.replace(/-/g, "+").replace(/_/g, "/")), char => char.charCodeAt(0));
const json = <T>(segment: string) => JSON.parse(new TextDecoder().decode(decode(segment))) as T;

/** The ID token's claims when Access signed it for this connector and it has not expired; null otherwise. */
export async function verifyIdToken(token: string, env: Pick<McpEnv, "ACCESS_JWKS_URL" | "ACCESS_CLIENT_ID">): Promise<Claims | null> {
  try {
    const [head, body, signature] = token.split(".");
    const { kid, alg } = json<{ kid?: string; alg?: string }>(head);
    if (alg !== "RS256") return null;
    const { keys } = await (await fetch(env.ACCESS_JWKS_URL)).json<{ keys: (JsonWebKey & { kid?: string })[] }>();
    const jwk = keys.find(key => key.kid === kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    if (!await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, decode(signature), new TextEncoder().encode(`${head}.${body}`))) return null;
    const claims = json<Claims>(body);
    const audiences = [claims.aud].flat();
    return audiences.includes(env.ACCESS_CLIENT_ID) && typeof claims.exp === "number" && claims.exp > Date.now() / 1000 ? claims : null;
  } catch {
    return null;
  }
}

/** Access sends the owner back here: trade the code for an ID token, check it, then let the AI app in. */
async function callback(request: Request, env: McpEnv): Promise<Response> {
  const { request: authRequest, headers } = await env.OAUTH_PROVIDER.finishUpstream(request);
  const code = new URL(request.url).searchParams.get("code");
  if (!code) return refused("The sign-in did not finish. Start again from your AI app.");
  const answer = await fetch(env.ACCESS_TOKEN_URL, { method: "POST", body: new URLSearchParams({ grant_type: "authorization_code", code,
    redirect_uri: new URL("/callback", request.url).href, client_id: env.ACCESS_CLIENT_ID, client_secret: env.ACCESS_CLIENT_SECRET }) });
  const { id_token: idToken } = answer.ok ? await answer.json<{ id_token?: string }>() : {};
  const claims = idToken ? await verifyIdToken(idToken, env) : null;
  if (!claims) return refused("The sign-in could not be checked. Start again from your AI app.", 403);
  // The second lock: a wider Access policy still admits no one else.
  if (claims.email?.toLowerCase() !== owner(env)) return refused("Only Relay's owner can connect an AI app.", 403);
  const client = await env.OAUTH_PROVIDER.lookupClient(authRequest.clientId);
  const { redirectTo } = await env.OAUTH_PROVIDER.completeAuthorization({ request: authRequest, userId: owner(env),
    metadata: { name: client?.clientName?.trim() || authRequest.clientId }, scope: authRequest.scope, props: { email: owner(env) } });
  headers.set("Location", redirectTo);
  return new Response(null, { status: 302, headers });
}

const PAGES: Record<string, (request: Request, env: McpEnv) => Promise<Response>> =
  { "GET /authorize": consent, "POST /authorize": chosen, "GET /callback": callback };

/** Every address but /mcp and the OAuth endpoints the provider answers itself. */
export const authHandler = {
  async fetch(request: Request, env: McpEnv): Promise<Response> {
    const page = PAGES[`${request.method} ${new URL(request.url).pathname}`];
    if (!page) return new Response("Not found", { status: 404 });
    try {
      return await page(request, env);
    } catch (error) {
      if (error instanceof AuthorizationError) return refused(`${error.description} Start again from your AI app.`);
      throw error;
    }
  },
};
