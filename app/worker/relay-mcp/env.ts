// The connector's bindings, from app/wrangler.relay-mcp.jsonc: Relay's database, the sign-in store, the owner and
// the Access for SaaS sign-in's values, which scripts/relay-mcp-setup.mjs puts as secrets. Nothing else.
import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";

export type McpEnv = {
  DB: D1Database;
  OAUTH_KV: KVNamespace;
  WONG_OWNER_EMAIL: string;
  RELAY_MCP_ADDRESS: string;
  ACCESS_CLIENT_ID: string;
  ACCESS_CLIENT_SECRET: string;
  ACCESS_AUTHORIZATION_URL: string;
  ACCESS_TOKEN_URL: string;
  ACCESS_JWKS_URL: string;
  /** Set by the OAuth provider before it calls the sign-in pages. */
  OAUTH_PROVIDER: OAuthHelpers;
};

export const owner = (env: Pick<McpEnv, "WONG_OWNER_EMAIL">) => env.WONG_OWNER_EMAIL.trim().toLowerCase();
