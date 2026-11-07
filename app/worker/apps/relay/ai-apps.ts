// GET ai-apps and POST ai-apps-disconnect: the AI apps a person connected to Relay Everything's AI connector, and
// ending one. Each person sees and ends only their own; a device key reaches neither.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asPerson } from "./caller.ts";
import type { Env } from "./store.ts";

/** What the connector's Grants entrypoint answers: app/worker/relay-mcp/index.ts. */
type Grants = {
  list(personId: string): Promise<{ address: string; apps: { id: string; name: string; connectedAt: number }[] }>;
  revoke(id: string, personId: string): Promise<boolean>;
};

const grants = (env: Env) => (env as Env & { RELAY_MCP?: Grants }).RELAY_MCP;
const ERRORS = { unavailable: "The AI connector is not set up here.", not_found: "You have no connected AI app with this id." };
const error = (code: keyof typeof ERRORS, status: number) =>
  Response.json({ error: { code, message: ERRORS[code] } }, { status, headers: { "Cache-Control": "no-store" } });

const app = z.strictObject({ id: z.string(), name: z.string(), connectedAt: z.number() });

export const aiApps = defineAction({
  operationId: "relay.ai-apps", summary: "List connected AI apps",
  description: "List the AI chat apps you connected to Relay Everything's AI connector, with the address to connect another.",
  input: z.strictObject({}), output: z.strictObject({ address: z.string(), apps: z.array(app) }),
  encoding: "none", effect: "read", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  handler: asPerson<ActionCall>(async ({ caller, env }) => {
    const connector = grants(env);
    return connector ? Response.json(await connector.list(caller.personId)) : error("unavailable", 503);
  }),
});

export const aiAppDisconnect = defineAction({
  operationId: "relay.ai-app-disconnect", summary: "Disconnect an AI app",
  description: "End one of your AI apps' connection to Relay Everything: its sign-in stops working at once.",
  input: z.strictObject({ id: z.string().regex(/^[A-Za-z0-9_:-]{1,128}$/).describe("The connection's id, from the list of connected AI apps.") }),
  output: z.strictObject({ id: z.string() }), encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false,
  confirmWith: "relay.ai-apps", errors: ERRORS, examples: [],
  handler: asPerson<ActionCall>(async ({ caller, env, call }) => {
    const connector = grants(env);
    if (!connector) return error("unavailable", 503);
    const { id } = call.input as { id: string };
    return await connector.revoke(id, caller.personId) ? Response.json({ id }) : error("not_found", 404);
  }),
});
