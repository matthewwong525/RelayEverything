// The connector's bindings, from app/wrangler.relay-mcp.jsonc: the directory's database, each person's space and the
// file store its photos are sealed in, the webhooks' queue, the sign-in store and the server whose sign-in it uses.
import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";
import type { SpaceEnv } from "../apps/relay/space.ts";

export type McpEnv = SpaceEnv & {
  DB: D1Database;
  /** Wakes the person's webhooks after an added note. */
  RELAY_WEBHOOKS: Queue;
  OAUTH_KV: KVNamespace;
  RELAY_MCP_ADDRESS: string;
  /** The Relay Everything server that signs a person in, then sends them back to /callback. */
  RELAY_SERVER_URL: string;
  /** Set by the OAuth provider before it calls the sign-in pages. */
  OAUTH_PROVIDER: OAuthHelpers;
};

/** A grant's person, and for an app whose consent page said it adds notes, `adds` with its device and name. A grant
 *  from before spaces has no person; one from before adding has no `adds`, so it only reads. */
export type GrantProps = { personId?: string; adds?: true; deviceId?: string; name?: string };
