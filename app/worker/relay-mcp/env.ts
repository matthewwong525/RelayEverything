// The connector's bindings, from app/wrangler.relay-mcp.jsonc: the directory's database, each person's space, the
// sign-in store and the server whose sign-in it uses. Nothing else.
import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";

export type McpEnv = {
  DB: D1Database;
  SPACES: DurableObjectNamespace;
  OAUTH_KV: KVNamespace;
  RELAY_MCP_ADDRESS: string;
  /** The Relay Everything server that signs a person in, then sends them back to /callback. */
  RELAY_SERVER_URL: string;
  /** Set by the OAuth provider before it calls the sign-in pages. */
  OAUTH_PROVIDER: OAuthHelpers;
};

/** What a grant keeps: the person whose space its tools read. A grant from before spaces has no person. */
export type GrantProps = { personId?: string };
