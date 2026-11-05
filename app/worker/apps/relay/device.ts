// Relay's device keys: one Access service token per phone, one for the Pebble app and one per Claude Code computer,
// each a row in relay_devices and each send-only. scripts/relay-device-key.mjs makes and revokes them.
import { refused, session, type Identity } from "./store.ts";

/** What a key is for: a phone or the Pebble app adds notes, health and places; a chat key adds chats. */
export type Reach = "phone" | "chats";

/** Each kind of key only adds data, so every reach is POST, plus `GET key`, which answers only the key's own name. A
 *  read such as `GET chats` shares an address with a send, so the method is checked too. */
const REACH: Record<Reach, { routes: RegExp; refusal: string }> = {
  phone: { routes: /^\/apps\/relay\/api\/(?:pebble|notes|health|locations)$/, refusal: "A device key can only send to Relay." },
  chats: { routes: /^\/apps\/relay\/api\/(?:chats|chat-saves)$/, refusal: "A chat key can only send chats." },
};
const KEY_CHECK = "/apps/relay/api/key";

/** True when a key of this reach may call the method on the address. */
export function reaches(reach: Reach, method: string, pathname: string): boolean {
  return method === "GET" ? pathname === KEY_CHECK : method === "POST" && REACH[reach].routes.test(pathname);
}

// Git holds only the checker's fingerprint: its Client ID stays in .env with the other checker values.
const sha256 = async (text: string) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))].map(byte => byte.toString(16).padStart(2, "0")).join("");

type Device = { id: string; name: string; reaches: Reach };
type Row = Device & { revoked_at: number | null };

const find = (db: D1Database, clientId: string) =>
  session({ DB: db }).prepare("SELECT id, name, reaches, revoked_at FROM relay_devices WHERE token_client_id = ?").bind(clientId).first<Row>();
/** A row from before keys had a reach is a phone's. */
const reachOf = (row: Row): Reach => row.reaches === "chats" ? "chats" : "phone";

/** The Worker's check before every route: null lets the call go on. People go on to the usual checks, and so does the
 *  checker, named by its Client ID; every other service token must be an unrevoked device. */
export async function deviceGate(env: { DB?: D1Database; RELAY_CHECKER_SHA256?: string }, identity: Identity,
  method: string, pathname: string): Promise<Response | null> {
  if (identity?.kind !== "service" || await sha256(identity.id) === env.RELAY_CHECKER_SHA256) return null;
  let row: Row | null;
  try {
    row = env.DB ? await find(env.DB, identity.id) : null;
  } catch {
    return refused(503, "Device keys could not be read. Try again.");
  }
  // A key on no list, such as a staging phone's after a staging reset, would else count as the checker and own staging.
  if (!row) return refused(403, "This key is on no list of devices.");
  if (row.revoked_at !== null) return refused(403, "This device key is turned off.");
  const reach = reachOf(row);
  return reaches(reach, method, pathname) ? null : refused(403, REACH[reach].refusal);
}

/** The device behind a call, or null for a person, another machine or a revoked key. */
export async function deviceOf(env: { DB: D1Database }, identity: Identity): Promise<Device | null> {
  if (identity?.kind !== "service") return null;
  const row = await find(env.DB, identity.id);
  return row && row.revoked_at === null ? { id: row.id, name: row.name, reaches: reachOf(row) } : null;
}
