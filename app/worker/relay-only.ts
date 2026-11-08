// The Relay Everything server: the shared server at app.relayeverything.com, and the Worker a person installs in their
// own account. Relay Everything's routes, page, sign-in and webhooks, and none of WongStack's. self-host/SETUP.md
import { dispatch } from "./api/contract.ts";
import { getAccessIdentity, type AccessEnv } from "./access.ts";
import type { AppEnv } from "./apps/index.ts";
import { queues, routes } from "./apps/relay/api.ts";
import { relayGate } from "./apps/relay/caller.ts";
import { email } from "./apps/relay/inbox/email.ts";
import { sweep } from "./apps/relay/inbox/held.ts";
import type { InboxEnv } from "./apps/relay/inbox/links.ts";
import { signIn, type SignInEnv } from "./apps/relay/sign-in/index.ts";

const PAGE = "/apps/relay/";
const PHONE_KEY = "/apps/relay/sign-in/phone/key";
const RELAY_API = /^\/apps\/relay\/api(?:\/(.*))?$/;

/** `access` on a self-host, which keeps Cloudflare Access for its owner; the shared server signs people in itself. */
type ServerEnv = AppEnv & AccessEnv & SignInEnv & InboxEnv & { RELAY_SIGN_IN?: string };

/** Relay Everything's API, or null for an address that is not its. Each route opens only its caller's space, so the
 *  company's sign-in policy has no part here: without the owner email it reads as an older install's, which admits. */
function relayRoute(request: Request, env: ServerEnv, url: URL, identity: Awaited<ReturnType<typeof getAccessIdentity>>) {
  const match = RELAY_API.exec(url.pathname);
  if (!match) return null;
  const route = match[1] ?? "";
  const handler = routes.get(`${request.method} ${route}`);
  if (!handler) return Response.json({ error: "Not found" }, { status: 404 });
  const { WONG_OWNER_EMAIL: _owner, ...rest } = env;
  return dispatch(handler, request, rest as AppEnv, { url, route, identity }, { apps: ["relay"] });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const access = env.RELAY_SIGN_IN === "access";
    const identity = access ? await getAccessIdentity(request, env) : null;
    // Behind Access, only a key's own calls, and a phone's trade of its sign-in code, pass the wall without a person.
    if (access && !identity && !request.headers.has("Authorization") && !(request.method === "POST" && url.pathname === PHONE_KEY)) {
      return new Response("Unauthorized", { status: 401, headers: { "Cache-Control": "no-store" } });
    }
    const signedIn = await signIn(request, env, identity, ctx && (work => ctx.waitUntil(work)));
    if (signedIn) return signedIn;
    const gate = await relayGate(request, env, identity, url.pathname);
    if (gate) return gate;
    const api = relayRoute(request, env, url, identity);
    if (api) return api;
    if (/^\/(?:apps\/[^/]+\/)?api(?:\/|$)/.test(url.pathname)) return Response.json({ error: "Not found" }, { status: 404 });
    if (url.pathname === "/") return Response.redirect(new URL(PAGE, url).href, 302);
    return env.ASSETS.fetch(request);
  },

  // Mail to the server's mail domain, from Cloudflare Email Routing: wiki/relay-spaces.md#ways-in
  async email(message, env) {
    await email(message, env);
  },

  // Each day: delete kept mail from an email with no account, older than 30 days. POST inbox/sweep runs it by hand.
  async scheduled(_controller, env) {
    await sweep(env);
  },

  // A server names its one queue after itself, so every batch is the webhooks'.
  async queue(batch, env) {
    await [...queues.values()][0](batch, env);
  },
} satisfies ExportedHandler<ServerEnv>;
