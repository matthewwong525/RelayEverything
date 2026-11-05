// GET ai-apps and POST ai-apps-disconnect: the AI apps the owner connected to Relay's AI connector, and ending one.
// Only the owner reaches them, never a device key: device.ts lists no ai-apps route.
import { z } from "zod";
import { checkerOwns, defineAction, humanEmail, ownerEmail, type Action } from "../../api/contract.ts";
import { refused, type Env, type Identity } from "./store.ts";

/** What the connector's Grants entrypoint answers: app/worker/relay-mcp/index.ts. */
type Grants = {
  list(): Promise<{ address: string; apps: { id: string; name: string; connectedAt: number }[] }>;
  revoke(id: string): Promise<void>;
};

const grants = (env: Env) => (env as Env & { RELAY_MCP?: Grants }).RELAY_MCP;
const isOwner = (env: Env, identity: Identity) => {
  const email = humanEmail(identity);
  return (email !== null && email === ownerEmail(env)) || checkerOwns(env, identity);
};
const ERRORS = { unavailable: "The AI connector is not set up here." };

/** The binding first, then the owner, then the call. */
const guarded = (run: (connector: Grants, input: unknown) => Promise<Response>): Action["handler"] =>
  async (_request, env, { identity, input }) => {
    const connector = grants(env);
    if (!connector) return refused(503, ERRORS.unavailable);
    if (!isOwner(env, identity)) return refused(403, "Only Relay's owner sees the connected AI apps.");
    return run(connector, input);
  };

const app = z.strictObject({ id: z.string(), name: z.string(), connectedAt: z.number() });

export const aiApps = defineAction({
  operationId: "relay.ai-apps", summary: "List connected AI apps",
  description: "List the AI chat apps connected to Relay's AI connector, with the address to connect another.",
  input: z.strictObject({}), output: z.strictObject({ address: z.string(), apps: z.array(app) }),
  encoding: "none", effect: "read", agentAvailable: false, errors: ERRORS, examples: [],
  handler: guarded(async connector => Response.json(await connector.list())),
});

export const aiAppDisconnect = defineAction({
  operationId: "relay.ai-app-disconnect", summary: "Disconnect an AI app",
  description: "End one AI app's connection to Relay: its sign-in stops working at once.",
  input: z.strictObject({ id: z.string().regex(/^[A-Za-z0-9_:-]{1,128}$/).describe("The connection's id, from the list of connected AI apps.") }),
  output: z.strictObject({ id: z.string() }), encoding: "json", effect: "write", agentAvailable: false, confirmWith: "relay.ai-apps",
  errors: ERRORS, examples: [],
  handler: guarded(async (connector, input) => {
    const { id } = input as { id: string };
    await connector.revoke(id);
    return Response.json({ id });
  }),
});
