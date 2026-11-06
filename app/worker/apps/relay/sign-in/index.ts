// Relay Everything's own sign-in, under /apps/relay/sign-in/: an email code, Apple or Google, sign-out, and the AI
// connector's hand-off. The directory keeps each session, code and key only as a SHA-256. wiki/relay-spaces.md
import type { DirectoryEnv } from "../people.ts";
import type { Identity } from "../store.ts";
import { connect } from "./connect.ts";
import { code, email, methods } from "./email.ts";
import { callback, start } from "./oidc.ts";
import { answer, signOut } from "./session.ts";

export type SignInEnv = DirectoryEnv & {
  RELAY_CHECKER_SHA256?: string;
  RELAY_EMAIL?: SendEmail; RELAY_SIGN_IN_FROM?: string; RELAY_SIGN_IN_LIMIT?: RateLimit;
  RELAY_APPLE_TEAM_ID?: string; RELAY_APPLE_SERVICES_ID?: string; RELAY_APPLE_SIGN_IN_KEY?: string; RELAY_APPLE_SIGN_IN_KEY_ID?: string;
  RELAY_GOOGLE_CLIENT_ID?: string; RELAY_GOOGLE_SIGN_IN_SECRET?: string;
  RELAY_MCP_CALLBACK?: string;
};

type Handler = (request: Request, env: SignInEnv, identity: Identity) => Promise<Response>;

const PREFIX = "/apps/relay/sign-in/";
const ROUTES = new Map<string, Handler>([
  ["GET methods", methods],
  ["POST email", email],
  ["POST code", code],
  ["GET apple", start("apple")],
  ["GET google", start("google")],
  ["POST apple/callback", callback("apple")],
  ["GET google/callback", callback("google")],
  ["POST out", signOut],
  ["GET connect", connect],
]);
// Apple posts its answer from its own site; the state cookie, not the Origin, protects that one.
const CROSS_SITE = "POST apple/callback";

/** A sign-in route's answer, or null for an address outside the sign-in. */
export async function signIn(request: Request, env: SignInEnv, identity: Identity): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith(PREFIX)) return null;
  const name = `${request.method} ${url.pathname.slice(PREFIX.length)}`;
  const route = ROUTES.get(name);
  if (!route) return answer(404, "not_found", "Not found");
  if (request.method === "POST" && name !== CROSS_SITE && request.headers.get("Origin") !== url.origin) {
    return answer(403, "forbidden", "This request did not come from the Relay Everything page.");
  }
  return route(request, env, identity);
}
