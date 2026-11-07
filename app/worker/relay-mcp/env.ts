// The connector's bindings, from app/wrangler.relay-mcp.jsonc: the directory's database, each person's space, the
// webhooks' queue, the sign-in store, the server whose sign-in it uses, and the Google client. Nothing else.
import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";

export type McpEnv = {
  DB: D1Database;
  SPACES: DurableObjectNamespace;
  /** Wakes the person's webhooks after an added note. */
  RELAY_WEBHOOKS: Queue;
  OAUTH_KV: KVNamespace;
  RELAY_MCP_ADDRESS: string;
  /** The Relay Everything server that signs a person in, then sends them back to /callback. */
  RELAY_SERVER_URL: string;
  /** The Google client the server signs in with, to refresh a person's Google sign-in. Unset: no Google here. */
  RELAY_GOOGLE_CLIENT_ID?: string;
  RELAY_GOOGLE_SIGN_IN_SECRET?: string;
  /** Set by the OAuth provider before it calls the sign-in pages. */
  OAUTH_PROVIDER: OAuthHelpers;
};

/** A grant's person, its `adds` with its device and name, and `google`, as its consent page said. An older grant
 *  lacks what came later: a person (before spaces), `adds` (it only reads), `google` (it never reaches Google). */
export type GrantProps = { personId?: string; adds?: true; google?: true; deviceId?: string; name?: string };
