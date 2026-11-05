// The connector Worker: the OAuth provider answers sign-in and tokens, /mcp takes only its own tokens, and Grants
// lets the Relay app list and end the owner's connections over a service binding.
import { getOAuthApi, OAuthProvider, type OAuthProviderOptions } from "@cloudflare/workers-oauth-provider";
import { WorkerEntrypoint } from "cloudflare:workers";
import { authHandler } from "./auth.ts";
import { owner, type McpEnv } from "./env.ts";
import { mcpHandler } from "./tools.ts";

const IDLE = 30 * 24 * 3600;

/** The provider's settings. Its resource is the environment's own /mcp address, which tokens are bound to. */
const options = (env: McpEnv): OAuthProviderOptions<McpEnv> => ({
  apiRoute: "/mcp", apiHandler: mcpHandler, defaultHandler: authHandler,
  authorizeEndpoint: "/authorize", tokenEndpoint: "/token", clientRegistrationEndpoint: "/register",
  resourceMetadata: { resource: env.RELAY_MCP_ADDRESS, resource_name: "Relay" },
  // A stolen access token works for an hour at most; the app refreshes it while the owner keeps it connected.
  accessTokenTTL: 3600,
  // An app in use stays connected: each refresh moves its end 30 days on, so it drops after 30 days unused.
  refreshTokenTTL: IDLE, refreshTokenIdleTTL: IDLE,
});

export default {
  fetch: (request: Request, env: McpEnv, ctx: ExecutionContext) => new OAuthProvider(options(env)).fetch(request, env, ctx),
};

/** The owner's connected AI apps, for the Relay app's page. Only a service binding reaches this. */
export class Grants extends WorkerEntrypoint<McpEnv> {
  async list() {
    const { items } = await getOAuthApi(options(this.env), this.env).listUserGrants(owner(this.env), { limit: 100 });
    const apps = items.map(grant => ({ id: grant.id, name: String(grant.metadata.name), connectedAt: grant.createdAt * 1000 }));
    return { address: this.env.RELAY_MCP_ADDRESS, apps: apps.sort((a, b) => b.connectedAt - a.connectedAt) };
  }

  /** Ends one connection: its tokens stop working at once. */
  async revoke(id: string) {
    await getOAuthApi(options(this.env), this.env).revokeGrant(id, owner(this.env));
  }
}
