// A person's devices on the Relay Everything page: make a key, list the devices, turn one off. The directory keeps only
// each key's SHA-256; a connected app's device row shows on the AI apps card instead.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asPerson, CHECKER_PERSON } from "./caller.ts";
import { directory, hashToken, randomToken } from "./people.ts";

const reaches = z.enum(["phone", "chats", "api"])
  .describe("phone: notes, health and places, from a phone or the Pebble app. chats: Claude Code chats. api: the web API, which reads and adds notes.");
type Reaches = z.infer<typeof reaches>;
const device = z.strictObject({ id: z.string(), name: z.string(), reaches, createdAt: z.number(), revokedAt: z.number().nullable() });
const ERRORS = { not_found: "You have no device with this id." };
type Row = { id: string; name: string; reaches: Reaches; created_at: number; revoked_at: number | null };

/** The web API on this server's AI connector: the origin of the connector's sign-in callback, then `/v1`. */
function apiAddress(env: object): string | null {
  const callback = (env as { RELAY_MCP_CALLBACK?: string }).RELAY_MCP_CALLBACK;
  return callback ? `${new URL(callback).origin}/v1` : null;
}

export const devices = defineAction({
  operationId: "relay.devices", summary: "List the devices", description: "List your devices and their keys' state, newest last. No key shows.",
  input: z.strictObject({}), output: z.strictObject({ devices: z.array(device) }),
  encoding: "none", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ space }) => {
    const { results } = await space.db.prepare(`SELECT id, name, reaches, created_at, revoked_at FROM relay_devices WHERE reaches != 'app'
      ORDER BY created_at, id`).all<Row>();
    return Response.json({ devices: results.map(row => ({ id: row.id, name: row.name, reaches: row.reaches,
      createdAt: row.created_at, revokedAt: row.revoked_at })) });
  }),
});

export const deviceAdd = defineAction({
  operationId: "relay.devices-add", summary: "Add a device",
  description: "Make a key for a new device. The answer holds the key, its QR code text and, for a phone key, the Pebble signing secret: each " +
    "shows only this once. An API key's answer names the web API's address.",
  input: z.strictObject({ name: z.string().trim().min(1).max(60).describe("A name you know the device by."), reaches }),
  output: z.strictObject({ id: z.string(), name: z.string(), reaches, key: z.string().describe("Shown this once."),
    qr: z.string().describe("What the phone scans: the server's address and the key."),
    pebbleSecret: z.string().nullable().describe("A phone key's Pebble signing secret, shown this once."),
    api: z.string().nullable().describe("An API key's web API address, or null when this server has no AI connector.") }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ space, caller, env, call }) => {
    const { name, reaches: reach } = call.input as { name: string; reaches: Reaches };
    const [id, key, now] = [crypto.randomUUID(), `rek_${randomToken()}`, Date.now()];
    const pebbleSecret = reach === "phone" ? randomToken() : null;
    await space.db.batch([
      space.db.prepare(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches)
        VALUES (?, ?, ?, '', ?, NULL, ?)`).bind(id, name, `rek:${id}`, now, reach),
      ...pebbleSecret ? [space.db.prepare("INSERT INTO relay_device_secrets (device_id, pebble_secret) VALUES (?, ?)").bind(id, pebbleSecret)] : [],
    ]);
    const db = directory(env);
    // The checker has no account of its own, so its key needs its fixed person row: a made-up address, never mailed.
    await db.batch([db.prepare("INSERT OR IGNORE INTO relay_people (id, email, created_at) SELECT ?, ?, ? WHERE ? = 'checker'")
      .bind(CHECKER_PERSON, "checker@example.invalid", now, caller.kind),
    db.prepare("INSERT INTO relay_keys (key_sha256, person_id, device_id, reaches, created_at) VALUES (?, ?, ?, ?, ?)")
      .bind(await hashToken(key), caller.personId, id, reach, now)]);
    const qr = JSON.stringify({ relay: 1, server: call.url.origin, key });
    return Response.json({ id, name, reaches: reach, key, qr, pebbleSecret, api: reach === "api" ? apiAddress(env) : null });
  }),
});

export const deviceOff = defineAction({
  operationId: "relay.devices-off", summary: "Turn off a device",
  description: "Turn off a device's key: it stops at once. The device's notes stay.",
  input: z.strictObject({ id: z.string().min(1).max(64).describe("The device's id, from the list of devices.") }),
  output: z.strictObject({ id: z.string(), revokedAt: z.number() }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  handler: asPerson<ActionCall>(async ({ space, caller, env, call }) => {
    const { id } = call.input as { id: string };
    const row = await space.db.prepare("UPDATE relay_devices SET revoked_at = coalesce(revoked_at, ?) WHERE id = ? RETURNING revoked_at")
      .bind(Date.now(), id).first<{ revoked_at: number }>();
    if (!row) return Response.json({ error: { code: "not_found", message: ERRORS.not_found } }, { status: 404 });
    await directory(env).prepare("UPDATE relay_keys SET revoked_at = coalesce(revoked_at, ?) WHERE person_id = ? AND device_id = ?")
      .bind(row.revoked_at, caller.personId, id).run();
    return Response.json({ id, revokedAt: row.revoked_at });
  }),
});
