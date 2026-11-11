// A person's devices on the Relay Everything page: make a key, list the devices, turn one off. The directory keeps only
// each key's SHA-256; an AI app's device shows on the AI apps card, and the keyless Email and Web devices nowhere.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asPerson, asPersonOrPhone, CHECKER_PERSON } from "./caller.ts";
import { refused } from "./store.ts";
import { directory, hashToken, randomToken, type DirectoryEnv } from "./people.ts";
import type { Caller, PersonSpace, Reach } from "./space.ts";

const reaches = z.enum(["phone", "chats", "api", "agent"])
  .describe("phone: notes, files, health, places and photos, from a phone. chats: an older Claude Code key that only saves chats. " +
    "api: the web API, which reads and adds notes. agent: a computer's key from Claude Code or Codex, which saves chats and reads through the web API.");
type Reaches = z.infer<typeof reaches>;
// A phone's and a computer's keys come only from their own sign-ins, and a chat-only key no longer from anywhere.
const addable = z.enum(["api"]).describe("api: an API key for the web API, which reads and adds notes. " +
  "A phone signs in from the Relay Everything app, and a computer from Claude Code or Codex with /relay:connect.");
const device = z.strictObject({ id: z.string(), name: z.string(), reaches, createdAt: z.number(), revokedAt: z.number().nullable() });
const ERRORS = { not_found: "You have no device with this id." };
type Row = { id: string; name: string; reaches: Reaches; created_at: number; revoked_at: number | null };

/** The web API on this server's AI connector: the origin of the connector's sign-in callback, then `/v1`. */
export function apiAddress(env: object): string | null {
  const callback = (env as { RELAY_MCP_CALLBACK?: string }).RELAY_MCP_CALLBACK;
  return callback ? `${new URL(callback).origin}/v1` : null;
}

export const devices = defineAction({
  operationId: "relay.devices", summary: "List the devices", description: "List your devices and their keys' state, newest last. No key shows.",
  input: z.strictObject({}), output: z.strictObject({ devices: z.array(device) }),
  encoding: "none", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ space }) => {
    const { results } = await space.db.prepare(`SELECT id, name, reaches, created_at, revoked_at FROM relay_devices WHERE reaches NOT IN ('app', 'inbox')
      ORDER BY created_at, id`).all<Row>();
    return Response.json({ devices: results.map(row => ({ id: row.id, name: row.name, reaches: row.reaches,
      createdAt: row.created_at, revokedAt: row.revoked_at })) });
  }),
});

export const deviceAdd = defineAction({
  operationId: "relay.devices-add", summary: "Add an API key",
  description: "Make an API key for the web API. The answer holds the key, which shows only this once, and names the web API's " +
    "address. A phone or a computer gets its key by signing in instead.",
  input: z.strictObject({ name: z.string().trim().min(1).max(60).describe("A name you know the device by."), reaches: addable }),
  output: z.strictObject({ id: z.string(), name: z.string(), reaches, key: z.string().describe("Shown this once."),
    api: z.string().nullable().describe("An API key's web API address, or null when this server has no AI connector.") }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ space, caller, env, call }) => {
    const { name } = call.input as { name: string };
    const { id, key } = await makeDevice(space, env, caller, name, "api");
    return Response.json({ id, name, reaches: "api", key, api: apiAddress(env) });
  }),
});

/** Makes a device in the person's space and its key in the directory, for *Add an API key* and the phone's and
 *  computer's sign-ins. The answer holds the key, which only the caller's answer may show. */
export async function makeDevice(space: PersonSpace, env: Pick<DirectoryEnv, "DB">, caller: Caller, name: string, reach: Reach) {
  const [id, key, now] = [crypto.randomUUID(), `rek_${randomToken()}`, Date.now()];
  await space.db.prepare(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches)
    VALUES (?, ?, ?, '', ?, NULL, ?)`).bind(id, name, `rek:${id}`, now, reach).run();
  const db = directory(env);
  // The checker has no account of its own, so its key needs its fixed person row: a made-up address, never mailed.
  await db.batch([db.prepare("INSERT OR IGNORE INTO relay_people (id, email, created_at) SELECT ?, ?, ? WHERE ? = 'checker'")
    .bind(CHECKER_PERSON, "checker@example.invalid", now, caller.kind),
  db.prepare("INSERT INTO relay_keys (key_sha256, person_id, device_id, reaches, created_at) VALUES (?, ?, ?, ?, ?)")
    .bind(await hashToken(key), caller.personId, id, reach, now)]);
  return { id, key };
}

export const deviceOff = defineAction({
  operationId: "relay.devices-off", summary: "Sign out a device",
  description: "Turn off a device's key: it stops at once. The device's notes stay. A phone's key may sign out only your phones.",
  input: z.strictObject({ id: z.string().min(1).max(64).describe("The device's id, from the list of devices.") }),
  output: z.strictObject({ id: z.string(), revokedAt: z.number() }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  handler: asPersonOrPhone<ActionCall>(async ({ space, caller, env, call }) => {
    const { id } = call.input as { id: string };
    // Only a device the list shows: a keyless way in, such as the page's Web device, has no key to turn off. A lost
    // phone may sign out only the person's phones, who sign in again: never a computer or an API key.
    const row = await space.db.prepare(`UPDATE relay_devices SET revoked_at = coalesce(revoked_at, ?) WHERE id = ? AND reaches NOT IN ('app', 'inbox')
      AND (? = 0 OR reaches = 'phone') RETURNING revoked_at`)
      .bind(Date.now(), id, caller.device ? 1 : 0).first<{ revoked_at: number }>();
    if (!row && caller.device) return refused(403, "A phone can sign out only your phones.");
    if (!row) return Response.json({ error: { code: "not_found", message: ERRORS.not_found } }, { status: 404 });
    await directory(env).prepare("UPDATE relay_keys SET revoked_at = coalesce(revoked_at, ?) WHERE person_id = ? AND device_id = ?")
      .bind(row.revoked_at, caller.personId, id).run();
    return Response.json({ id, revokedAt: row.revoked_at });
  }),
});
