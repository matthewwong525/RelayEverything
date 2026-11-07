// The connector's sign-in pages. /authorize asks the person to approve the AI app by name, then sends them to the
// server's own sign-in; /callback trades the server's one-time code for the person whose space the app may use.
import { AuthorizationError, type AuthRequest } from "@cloudflare/workers-oauth-provider";
import { hashToken } from "../apps/relay/people.ts";
import type { GrantProps, McpEnv } from "./env.ts";

const html = (body: string, status = 200, headers = new Headers()) => {
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  return new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Relay Everything</title><body style="font-family:system-ui;max-width:32rem;margin:3rem auto;padding:0 1rem">${body}</body>`, { status, headers });
};
const escape = (text: string) => text.replace(/[&<>"']/g, char => `&#${char.charCodeAt(0)};`);
const refused = (message: string, status = 400) => html(`<h1>Relay Everything</h1><p>${escape(message)}</p>`, status);

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
  return html(`<h1>Connect ${escape(about.clientName)} to Relay Everything?</h1>
<p>It can then read your Relay Everything notes, health, places and saved chats, and add notes, when you ask it. It can't change or delete them.</p>
<p>Its answers go to <b>${escape(about.redirectHost)}</b>.${about.redirectIsLoopback ? " That is an app on this computer." : ""}</p>
<form method="post"><input type="hidden" name="handle" value="${escape(handle)}">
<button name="choice" value="approve">Connect</button> <button name="choice" value="deny">Cancel</button></form>`, 200, headers);
}

/** The approve or cancel button: cancel goes back to the app, approve on to the server's own sign-in. */
async function chosen(request: Request, env: McpEnv): Promise<Response> {
  const form = await request.formData();
  const handle = String(form.get("handle") ?? "");
  if (form.get("choice") !== "approve") {
    const { headers } = await env.OAUTH_PROVIDER.denyConsent(request, handle);
    return new Response(null, { status: 302, headers });
  }
  const approved = await env.OAUTH_PROVIDER.approveConsent(request, handle);
  const { state, headers } = await env.OAUTH_PROVIDER.beginUpstream(approved.request, { headers: approved.headers });
  const signIn = new URL("/apps/relay/sign-in/connect", env.RELAY_SERVER_URL);
  signIn.searchParams.set("state", state);
  headers.set("Location", signIn.href);
  return new Response(null, { status: 302, headers });
}

/** Trades the server's code for its person, once: the code is gone after this, and after 5 minutes. */
async function personOf(env: McpEnv, code: string): Promise<string | null> {
  const found = await env.DB.withSession("first-primary").prepare("DELETE FROM relay_connect_codes WHERE code_sha256 = ? AND expires_at > ? RETURNING person_id")
    .bind(await hashToken(code), Date.now()).first<{ person_id: string }>();
  return found?.person_id ?? null;
}

/** The server sends the signed-in person back here with a code: trade it for the person, then let the app in. Its
 *  grant may add notes, as the consent page said, under a device of its own, made on its first note. */
async function callback(request: Request, env: McpEnv): Promise<Response> {
  const { request: authRequest, headers } = await env.OAUTH_PROVIDER.finishUpstream(request);
  const code = new URL(request.url).searchParams.get("code");
  if (!code) return refused("The sign-in did not finish. Start again from your AI app.");
  const personId = await personOf(env, code);
  if (!personId) return refused("This sign-in was used already, or is too old. Start again from your AI app.");
  const client = await env.OAUTH_PROVIDER.lookupClient(authRequest.clientId);
  const name = client?.clientName?.trim() || authRequest.clientId;
  const deviceId = crypto.randomUUID();
  const props: GrantProps = { personId, adds: true, deviceId, name };
  const { redirectTo } = await env.OAUTH_PROVIDER.completeAuthorization({ request: authRequest, userId: personId,
    metadata: { name, deviceId }, scope: authRequest.scope, props });
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
