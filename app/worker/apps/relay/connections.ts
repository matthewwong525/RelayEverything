// GET connections: the email, phones, computers, AI app and webhook names and notes addresses, for Account and the
// connection pages. From the caller's own space: never a key, nor a webhook's address, secret, kinds or send state.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asPersonOrPhone } from "./caller.ts";
import { addressOf, inboxOf, SHARED, type InboxEnv } from "./inbox/links.ts";
import type { Env } from "./store.ts";

/** The connector's Grants entrypoint, as much of it as this route reads: app/worker/relay-mcp/index.ts. */
type Grants = { list(personId: string): Promise<{ apps: { name: string; connectedAt: number }[] }> };

const device = z.strictObject({
  id: z.string(), name: z.string(), kind: z.enum(["phone", "computer"]).describe("phone: a phone's key. computer: Claude Code or Codex."),
  since: z.number().describe("When the device connected, in ms."),
  lastChatAt: z.number().nullable().describe("When the device last saved a chat, in ms, or null."),
});
type Row = { id: string; name: string; reaches: string; created_at: number; last_at: number | null };

export const connections = defineAction({
  operationId: "relay.connections", summary: "List what you connected",
  description: "Your account's email, your phones and computers, the names of your connected AI apps and of your webhooks, and your "
    + "two notes addresses, for the Account and connection pages. It holds no key, and no webhook address, secret or send state. "
    + "Where the AI connector is not set up, the AI apps list is empty; where email is off, both addresses are null.",
  input: z.strictObject({}),
  output: z.strictObject({
    email: z.string().describe("The email of the account the key or sign-in belongs to."),
    thisDevice: z.string().nullable().describe("The calling device's id, or null for a sign-in."),
    devices: z.array(device).describe("Each phone and computer that is not signed out, oldest first. No API key."),
    aiApps: z.array(z.strictObject({ name: z.string(), connectedAt: z.number().nullable() })).describe("Each connected AI app."),
    webhooks: z.array(z.strictObject({ name: z.string() })).describe("Each webhook, paused ones too."),
    notesAddress: z.string().nullable().describe("Your secret notes address, made on first read, or null when email is off."),
    sharedAddress: z.string().nullable().describe("The shared notes address for your sign-in email, or null when email is off."),
  }),
  encoding: "none", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPersonOrPhone<ActionCall>(async ({ space, caller, env }) => {
    const connector = (env as Env & { RELAY_MCP?: Grants }).RELAY_MCP;
    const mail = env as Env & InboxEnv;
    const inbox = inboxOf(mail);
    const [apps, devices, hooks, notesAddress] = await Promise.all([
      connector ? connector.list(caller.personId).then(answer => answer.apps) : [],
      space.db.prepare(`SELECT d.id, d.name, d.reaches, d.created_at, (SELECT max(c.last_at) FROM relay_chats c WHERE c.device_id = d.id) AS last_at
        FROM relay_devices d WHERE d.reaches IN ('phone', 'agent', 'chats') AND d.revoked_at IS NULL ORDER BY d.created_at, d.id`).all<Row>(),
      space.db.prepare("SELECT name FROM relay_webhooks ORDER BY created_at, id").all<{ name: string }>(),
      addressOf(mail, caller.personId),
    ]);
    return Response.json({
      email: caller.email ?? "", thisDevice: caller.device?.id ?? null,
      devices: devices.results.map(row => ({ id: row.id, name: row.name, kind: row.reaches === "phone" ? "phone" : "computer",
        since: row.created_at, lastChatAt: row.last_at })),
      aiApps: apps.map(({ name, connectedAt }) => ({ name, connectedAt })),
      webhooks: hooks.results.map(({ name }) => ({ name })),
      notesAddress, sharedAddress: inbox && `${SHARED}@${inbox.domain}`,
    }, { headers: { "Cache-Control": "no-store" } });
  }),
});
