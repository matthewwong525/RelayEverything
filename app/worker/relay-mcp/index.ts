// The connector Worker: the OAuth provider answers sign-in, tokens and /mcp; /v1/ takes a token or an API key; Grants
// lets the Relay Everything server list and end one person's connections over a service binding.
import { getOAuthApi, OAuthProvider, type OAuthProviderOptions } from "@cloudflare/workers-oauth-provider";
import { WorkerEntrypoint } from "cloudflare:workers";
import { apiKeyCaller, KEY } from "../apps/relay/caller.ts";
import { problem, v1, type Status } from "./api.ts";
import type { Asker } from "./answers.ts";
import { appDeviceOff, grantAsker, keyAsker } from "./asker.ts";
import { authHandler } from "./auth.ts";
import type { GrantProps, McpEnv } from "./env.ts";
import { openApi } from "./openapi.ts";
import { mcpHandler } from "./tools.ts";

const IDLE = 30 * 24 * 3600;

/** The provider's settings. Its one resource is the environment's own /mcp address, which every token is bound to:
 *  the installed provider refuses a route outside it, so /v1/ is answered before the provider (design Decision 7). */
const options = (env: McpEnv): OAuthProviderOptions<McpEnv> => ({
  apiRoute: "/mcp", apiHandler: mcpHandler, defaultHandler: authHandler,
  authorizeEndpoint: "/authorize", tokenEndpoint: "/token", clientRegistrationEndpoint: "/register",
  resourceMetadata: { resource: env.RELAY_MCP_ADDRESS, resource_name: "Relay Everything" },
  // A stolen access token works for an hour at most; the app refreshes it while the owner keeps it connected.
  accessTokenTTL: 3600,
  // An app in use stays connected: each refresh moves its end 30 days on, so it drops after 30 days unused.
  refreshTokenTTL: IDLE, refreshTokenIdleTTL: IDLE,
});

// The API takes a bearer token and never a cookie, so any web page may call it, such as Swagger in a browser.
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "Authorization, Content-Type",
  "Access-Control-Allow-Methods": "GET, POST", "Access-Control-Max-Age": "86400" };

/** Tells a caller with no valid token where to read how to get one, as /mcp's own refusal does. */
const challenge = (env: McpEnv) => {
  const address = new URL(env.RELAY_MCP_ADDRESS);
  return { "WWW-Authenticate": `Bearer resource_metadata="${address.origin}/.well-known/oauth-protected-resource${address.pathname}"` };
};

/** An API key's caller, or the refusal caller.ts gave, in the API's own error shape. */
async function keyCaller(env: McpEnv, header: string): Promise<Asker | Response> {
  const key = KEY.exec(header);
  if (!key) return problem(401, "This key is not one Relay Everything makes.", challenge(env));
  const caller = await apiKeyCaller(env, key[1]);
  if (!(caller instanceof Response)) return keyAsker(env, caller as Parameters<typeof keyAsker>[1]);
  const { error } = await caller.json() as { error: { message: string } };
  return problem(caller.status as Status, error.message);
}

/** A connected app's caller: a live token this provider made for its one resource, whose grant names a person. */
async function tokenCaller(env: McpEnv, token: string): Promise<Asker | Response> {
  const found = await getOAuthApi(options(env), env).unwrapToken<GrantProps>(token);
  const asker = found?.audience === env.RELAY_MCP_ADDRESS ? grantAsker(env, found.grant.props) : null;
  return asker ?? problem(401, "This token is not valid: it ended, or its app was disconnected. Connect the app again.", challenge(env));
}

async function api(request: Request, env: McpEnv): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { status: 204 });
  if (new URL(request.url).pathname === "/v1/openapi.json") {
    return Response.json(openApi(new URL(env.RELAY_MCP_ADDRESS).origin), { headers: { "Cache-Control": "public, max-age=300" } });
  }
  const header = request.headers.get("Authorization") ?? "";
  const token = /^Bearer (\S+)$/.exec(header)?.[1];
  if (!token) return problem(401, "Send a connected app's token or an API key as `Authorization: Bearer …`.", challenge(env));
  const asker = token.startsWith("rek_") ? await keyCaller(env, header) : await tokenCaller(env, token);
  return asker instanceof Response ? asker : v1(request, asker);
}

export default {
  async fetch(request: Request, env: McpEnv, ctx: ExecutionContext): Promise<Response> {
    if (!new URL(request.url).pathname.startsWith("/v1/")) return new OAuthProvider(options(env)).fetch(request, env, ctx);
    const answer = await api(request, env);
    const headers = new Headers(answer.headers);
    for (const [name, value] of Object.entries(CORS)) headers.set(name, value);
    return new Response(answer.body, { status: answer.status, headers });
  },
};

/** One person's connected apps, for the server's page. Only a service binding reaches this, and the server names
 *  the person only from its own sign-in. */
export class Grants extends WorkerEntrypoint<McpEnv> {
  private grantsOf(personId: string) {
    return getOAuthApi(options(this.env), this.env).listUserGrants(personId, { limit: 100 });
  }

  async list(personId: string) {
    const { items } = await this.grantsOf(personId);
    const apps = items.map(grant => ({ id: grant.id, name: String(grant.metadata.name), connectedAt: grant.createdAt * 1000 }));
    return { address: this.env.RELAY_MCP_ADDRESS, apps: apps.sort((a, b) => b.connectedAt - a.connectedAt) };
  }

  /** Ends one of the person's connections: its tokens stop working at once, and its device row shows it off. False
   *  when the person has no such one. A grant from before adding has no device, so its made-up id matches no row. */
  async revoke(id: string, personId: string): Promise<boolean> {
    const grant = (await this.grantsOf(personId)).items.find(item => item.id === id);
    if (!grant) return false;
    await getOAuthApi(options(this.env), this.env).revokeGrant(id, personId);
    await appDeviceOff(this.env, personId, String(grant.metadata.deviceId));
    return true;
  }
}
