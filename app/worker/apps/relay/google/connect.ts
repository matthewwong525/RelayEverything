// Connect Google: GET /apps/relay/google/connect sends a signed-in person to Google for Gmail, Calendar, Drive and
// Contacts, and /callback seals the sign-in in their own space. GET google and POST google-disconnect serve the page.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../../api/contract.ts";
import { asPerson, callerOf, cookie, openSpace, type CallerEnv } from "../caller.ts";
import { randomToken } from "../people.ts";
import { verifyIdToken, challenge } from "../sign-in/jwt.ts";
import { GOOGLE } from "../sign-in/oidc.ts";
import { answer, redirect, secure } from "../sign-in/session.ts";
import type { Caller } from "../space.ts";
import type { Env, Identity } from "../store.ts";
import { clientOf, connectionOf, disconnect, keep, revoke, type GoogleEnv } from "./token.ts";

const PREFIX = "/apps/relay/google/";
const HOME = "/apps/relay/";
const STATE = "relay_google";
const API = "https://www.googleapis.com/auth/";
/** What a connection needs: every one of these, or none is kept. */
export const SCOPES = ["gmail.modify", "calendar", "drive", "contacts.readonly", "contacts.other.readonly"].map(scope => `${API}${scope}`);

type Saved = { state: string; nonce: string; verifier: string; person: string };
type Client = NonNullable<ReturnType<typeof clientOf>>;
type Page = (request: Request, env: Env, caller: Caller, client: Client) => Promise<Response>;

const callbackOf = (url: URL) => `${url.origin}${PREFIX}callback`;
const stateCookie = (url: URL, value: string, seconds: number) =>
  `${STATE}=${value}; Path=${PREFIX}; HttpOnly; SameSite=Lax; Max-Age=${seconds}${secure(url)}`;
const back = (url: URL, outcome?: "connected" | "missing" | "failed") =>
  redirect(outcome ? `${HOME}?google=${outcome}` : HOME, [stateCookie(url, "", 0)]);

/** GET connect: to Google, asking for the four services offline, with PKCE, state and a nonce in a short cookie. */
async function start(request: Request, _env: Env, caller: Caller, client: Client): Promise<Response> {
  const url = new URL(request.url);
  const saved: Saved = { state: randomToken(), nonce: randomToken(), verifier: randomToken(), person: caller.personId };
  const params = new URLSearchParams({ client_id: client.id, redirect_uri: callbackOf(url), response_type: "code",
    scope: ["openid", "email", ...SCOPES].join(" "), access_type: "offline", prompt: "consent", state: saved.state, nonce: saved.nonce,
    code_challenge: await challenge(saved.verifier), code_challenge_method: "S256" });
  return redirect(`${GOOGLE.authorize}?${params}`, [stateCookie(url, btoa(JSON.stringify(saved)), 600)]);
}

function savedOf(request: Request): Saved | null {
  try {
    return JSON.parse(atob(cookie(request, STATE) ?? "")) as Saved;
  } catch {
    return null;
  }
}

type Tokens = { id_token?: unknown; refresh_token?: unknown; scope?: unknown };

/** Trades Google's code for the sign-in's tokens. */
async function tokensOf(url: URL, client: Client, code: string, verifier: string): Promise<Tokens> {
  const response = await fetch(GOOGLE.token, { method: "POST", body: new URLSearchParams({ grant_type: "authorization_code", code,
    redirect_uri: callbackOf(url), client_id: client.id, client_secret: client.secret, code_verifier: verifier }) });
  return response.ok ? await response.json<Tokens>() : {};
}

/** GET callback: a cancel changes nothing; a sign-in missing a permission is ended at Google and not kept. */
async function callback(request: Request, env: Env, caller: Caller, client: Client): Promise<Response> {
  const url = new URL(request.url);
  const saved = savedOf(request);
  // Only the browser and the person that started may finish, so no link can connect into someone else's space.
  if (!saved || url.searchParams.get("state") !== saved.state || saved.person !== caller.personId) return back(url, "failed");
  const code = url.searchParams.get("code");
  if (!code) return back(url);
  const tokens = await tokensOf(url, client, code, saved.verifier);
  const claims = typeof tokens.id_token === "string" ? await verifyIdToken(tokens.id_token, { jwks: GOOGLE.jwks, issuers: GOOGLE.issuers,
    audience: client.id, nonce: saved.nonce }) : null;
  if (!claims || typeof tokens.refresh_token !== "string") return back(url, "failed");
  const granted = typeof tokens.scope === "string" ? tokens.scope.split(" ") : [];
  if (!SCOPES.every(scope => granted.includes(scope))) {
    await revoke(tokens.refresh_token);
    return back(url, "missing");
  }
  const space = openSpace(env, caller);
  if (space instanceof Response) return space;
  await keep(space, { email: claims.email, scopes: SCOPES, refreshToken: tokens.refresh_token });
  return back(url, "connected");
}

const PAGES: Record<string, Page> = { "GET connect": start, "GET callback": callback };

/** A Connect Google page's answer, or null for an address outside it. Only a person signed in on the page connects:
 *  never a device key, the checker, or another Worker. */
export async function googleConnect(request: Request, env: Env & CallerEnv & GoogleEnv, identity: Identity): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith(PREFIX)) return null;
  const page = PAGES[`${request.method} ${url.pathname.slice(PREFIX.length)}`];
  if (!page) return answer(404, "not_found", "Not found");
  const client = clientOf(env);
  if (!client) return answer(503, "unavailable", "This server does not connect Google.");
  const caller = await callerOf(request, env, identity);
  if (caller instanceof Response) return caller;
  if (!caller) return redirect(HOME);
  if (caller.kind !== "session" && caller.kind !== "access") return answer(403, "forbidden", "Sign in on your Relay Everything page to connect Google.");
  return page(request, env, caller, client);
}

const connection = z.strictObject({ email: z.string(), scopes: z.array(z.string()), connectedAt: z.number() });

export const google = defineAction({
  operationId: "relay.google", summary: "Read the Google connection",
  description: "Whether this server connects Google, and the Google address you connected, with its permissions and when.",
  input: z.strictObject({}), output: z.strictObject({ available: z.boolean(), connected: connection.nullable() }),
  encoding: "none", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ space, env }) =>
    Response.json({ available: clientOf(env as GoogleEnv) !== null, connected: await connectionOf(space) }, { headers: { "Cache-Control": "no-store" } })),
});

export const googleDisconnect = defineAction({
  operationId: "relay.google-disconnect", summary: "Disconnect Google",
  description: "End your Google sign-in at Google and delete it from your space: no app or key reaches your Google after this.",
  input: z.strictObject({}), output: z.strictObject({ disconnected: z.boolean().describe("False when no Google was connected.") }),
  encoding: "json", effect: "external", agentAvailable: false, requiresIdentity: false, confirmWith: "relay.google", errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ space }) => Response.json({ disconnected: await disconnect(space) })),
});
