// Relay's device keys: one Cloudflare Access service token per phone and one for the Pebble app, each a row in
// relay_devices. scripts/relay-device-key.mjs makes and revokes them; a revoked key reaches nothing.
import { refused, session, type Identity } from "./store.ts";

/** The only addresses a device key reaches, whatever the method: the app's router answers the rest. */
const DEVICE_ROUTES = /^\/apps\/relay\/api\/(?:pebble|notes|health|locations|timeline|audio)$/;

// Git holds only the checker's fingerprint: its Client ID stays in .env with the other checker values.
const sha256 = async (text: string) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))].map(byte => byte.toString(16).padStart(2, "0")).join("");

type Device = { id: string; name: string };
type Row = Device & { revoked_at: number | null };

const find = (db: D1Database, clientId: string) =>
  session({ DB: db }).prepare("SELECT id, name, revoked_at FROM relay_devices WHERE token_client_id = ?").bind(clientId).first<Row>();

/** The Worker's check before every route: null lets the call go on. People go on to the usual checks, and so does the
 *  checker, named by its Client ID; every other service token must be an unrevoked device. */
export async function deviceGate(env: { DB?: D1Database; RELAY_CHECKER_SHA256?: string }, identity: Identity,
  pathname: string): Promise<Response | null> {
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
  return DEVICE_ROUTES.test(pathname) ? null : refused(403, "A device key reaches only Relay.");
}

/** The device behind a call, or null for a person, another machine or a revoked key. */
export async function deviceOf(env: { DB: D1Database }, identity: Identity): Promise<Device | null> {
  if (identity?.kind !== "service") return null;
  const row = await find(env.DB, identity.id);
  return row && row.revoked_at === null ? { id: row.id, name: row.name } : null;
}
