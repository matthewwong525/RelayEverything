// A person's Google sign-in: the refresh token sealed in their space, short access tokens kept only in this isolate's
// memory, and its end at Google. Only the sign-in is stored; no email, event, file or contact is.
import { GOOGLE } from "../sign-in/oidc.ts";
import type { PersonSpace } from "../space.ts";

export type GoogleEnv = { RELAY_GOOGLE_CLIENT_ID?: string; RELAY_GOOGLE_SIGN_IN_SECRET?: string };
export type Connection = { email: string; scopes: string[]; connectedAt: number };
type Row = { email: string; scopes: string; token: ArrayBuffer; connected_at: number };

export const REVOKE_URL = "https://oauth2.googleapis.com/revoke";
/** The name the refresh token is sealed under, so no other sealed value opens as it. */
const SEALED = "google";
const MINUTE = 60_000;

/** A request Relay Everything does not pass to Google, with the status to answer. */
export class GoogleRefusal extends Error {
  readonly status: 400 | 403 | 405 | 503;
  constructor(message: string, status: 400 | 403 | 405 | 503) {
    super(message);
    this.status = status;
  }
}

/** The Google client's id and secret, or null on a server with no Google client. */
export const clientOf = ({ RELAY_GOOGLE_CLIENT_ID: id, RELAY_GOOGLE_SIGN_IN_SECRET: secret }: GoogleEnv) => id && secret ? { id, secret } : null;

/** Each person's access token, while it lasts, for the sealed sign-in it came from: a new connection has new bytes. */
const cache = new Map<string, { sealed: string; token: string; until: number }>();
const sealedOf = (row: Row) => btoa(String.fromCharCode(...new Uint8Array(row.token)));

const rowOf = (space: PersonSpace) =>
  space.db.prepare("SELECT email, scopes, token, connected_at FROM relay_google WHERE id = 1").first<Row>();

/** The person's Google address, permissions and when they connected, or null. */
export async function connectionOf(space: PersonSpace): Promise<Connection | null> {
  const row = await rowOf(space);
  return row && { email: row.email, scopes: row.scopes.split(" "), connectedAt: row.connected_at };
}

/** Seals the refresh token in the space, in place of any connection before. */
export async function keep(space: PersonSpace, { email, scopes, refreshToken }: { email: string; scopes: string[]; refreshToken: string }) {
  const sealed = await space.seal(SEALED, new TextEncoder().encode(refreshToken));
  cache.delete(space.personId);
  await space.db.prepare(`INSERT INTO relay_google (id, email, scopes, token, connected_at) VALUES (1, ?, ?, ?, ?)
    ON CONFLICT (id) DO UPDATE SET email = excluded.email, scopes = excluded.scopes, token = excluded.token, connected_at = excluded.connected_at`)
    .bind(email, scopes.join(" "), sealed.slice().buffer, Date.now()).run();
}

/** Ends a token at Google. A failed end is not tried again: the space and its key go anyway. */
export async function revoke(token: string): Promise<void> {
  await fetch(REVOKE_URL, { method: "POST", body: new URLSearchParams({ token }) }).catch(() => null);
}

const opened = async (space: PersonSpace, row: Row) => {
  const bytes = await space.open(SEALED, new Uint8Array(row.token));
  return bytes && new TextDecoder().decode(bytes);
};

async function remove(space: PersonSpace) {
  cache.delete(space.personId);
  await space.db.prepare("DELETE FROM relay_google WHERE id = 1").run();
}

/** Ends the connection at Google and deletes it from the space; false when there was none. */
export async function disconnect(space: PersonSpace): Promise<boolean> {
  const row = await rowOf(space);
  if (!row) return false;
  const token = await opened(space, row);
  if (token) await revoke(token);
  await remove(space);
  return true;
}

/** A live access token for the person's Google, or null when none is connected. A refresh token that Google ended,
 *  or that no longer opens, deletes the connection, so the page offers Connect Google again. */
export async function accessToken(env: GoogleEnv, space: PersonSpace): Promise<string | null> {
  const row = await rowOf(space);
  if (!row) return null;
  const found = cache.get(space.personId);
  if (found?.sealed === sealedOf(row) && found.until > Date.now()) return found.token;
  const client = clientOf(env);
  const refreshToken = await opened(space, row);
  if (!client || !refreshToken) {
    if (!refreshToken) await remove(space);
    return null;
  }
  const response = await fetch(GOOGLE.token, { method: "POST", body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken,
    client_id: client.id, client_secret: client.secret }) }).catch(() => null);
  const answer = (await response?.json().catch(() => ({})) ?? {}) as { access_token?: unknown; expires_in?: unknown; error?: unknown };
  if (answer.error === "invalid_grant") {
    await remove(space);
    return null;
  }
  if (!response?.ok || typeof answer.access_token !== "string") {
    throw new GoogleRefusal(`Google's sign-in ${response ? `answered ${response.status}` : "could not be reached"}. Try again.`, 503);
  }
  const seconds = typeof answer.expires_in === "number" ? answer.expires_in : 3600;
  cache.set(space.personId, { sealed: sealedOf(row), token: answer.access_token, until: Date.now() + seconds * 1000 - MINUTE });
  return answer.access_token;
}
