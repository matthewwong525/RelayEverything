// The Relay-only Worker a person installs in their own account: Relay's routes, page, webhooks and device keys from
// the same files as the full app, and none of WongStack's. self-host/SETUP.md
import { dispatch } from "./api/contract.ts";
import { getAccessIdentity, type AccessEnv } from "./access.ts";
import type { AppEnv } from "./apps/index.ts";
import { queues, routes, scheduled } from "./apps/relay/api.ts";
import { deviceGate } from "./apps/relay/device.ts";

const PAGE = "/apps/relay/";
const RELAY_API = /^\/apps\/relay\/api(?:\/(.*))?$/;

/** Relay's API, or null for an address that is not Relay's. Only the owner gets past Access, so every route's
 *  mapping is the Relay app's own. */
function relayRoute(request: Request, env: AppEnv, url: URL, identity: Awaited<ReturnType<typeof getAccessIdentity>>) {
  const match = RELAY_API.exec(url.pathname);
  if (!match) return null;
  const route = match[1] ?? "";
  const handler = routes.get(`${request.method} ${route}`);
  if (!handler) return Response.json({ error: "Not found" }, { status: 404 });
  return dispatch(handler, request, env, { url, route, identity }, { apps: ["relay"] });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const identity = await getAccessIdentity(request, env);
    if (!identity) return new Response("Unauthorized", { status: 401, headers: { "Cache-Control": "no-store" } });
    const device = await deviceGate(env, identity, request.method, url.pathname);
    if (device) return device;
    const api = relayRoute(request, env, url, identity);
    if (api) return api;
    if (/^\/(?:apps\/[^/]+\/)?api(?:\/|$)/.test(url.pathname)) return Response.json({ error: "Not found" }, { status: 404 });
    if (url.pathname === "/") return Response.redirect(new URL(PAGE, url).href, 302);
    return env.ASSETS.fetch(request);
  },

  async scheduled(_controller, env) {
    await scheduled(env);
  },

  // An install names its one queue after itself, so every batch is the webhooks'.
  async queue(batch, env) {
    await [...queues.values()][0](batch, env);
  },
} satisfies ExportedHandler<AppEnv & AccessEnv>;
