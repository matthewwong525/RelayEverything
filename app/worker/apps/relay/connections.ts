// GET connections: the account's email and the names of its AI apps and webhooks, for the phone's Account page. From
// the caller's own space: never a webhook's address, secret, kinds or send state.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asPersonOrPhone } from "./caller.ts";
import type { Env } from "./store.ts";

/** The connector's Grants entrypoint, as much of it as this route reads: app/worker/relay-mcp/index.ts. */
type Grants = { list(personId: string): Promise<{ apps: { name: string }[] }> };

const named = z.array(z.strictObject({ name: z.string() }));

export const connections = defineAction({
  operationId: "relay.connections", summary: "List what you connected, by name",
  description: "Your account's email and the names of your connected AI apps and of your webhooks, for the phone's Account page. "
    + "It holds no address, secret or send state. Where the AI connector is not set up, the AI apps list is empty.",
  input: z.strictObject({}),
  output: z.strictObject({
    email: z.string().describe("The email of the account the key or sign-in belongs to."),
    aiApps: named.describe("Each connected AI app."), webhooks: named.describe("Each webhook, paused ones too."),
  }),
  encoding: "none", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPersonOrPhone<ActionCall>(async ({ space, caller, env }) => {
    const connector = (env as Env & { RELAY_MCP?: Grants }).RELAY_MCP;
    const [apps, { results }] = await Promise.all([
      connector ? connector.list(caller.personId).then(answer => answer.apps) : [],
      space.db.prepare("SELECT name FROM relay_webhooks ORDER BY created_at, id").all<{ name: string }>(),
    ]);
    return Response.json({ email: caller.email ?? "", aiApps: apps.map(({ name }) => ({ name })), webhooks: results.map(({ name }) => ({ name })) },
      { headers: { "Cache-Control": "no-store" } });
  }),
});
