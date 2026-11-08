// Who a mail is for: a person's secret notes address, found by an HMAC of its local part, or the sign-in email that
// the mail's sender checks proved. space-access.test.ts lets this file vouch. wiki/relay-spaces.md#ways-in
import { directory, normalEmail, personByEmail } from "../people.ts";
import { vouch, type Caller } from "../space.ts";

export type InboxEnv = { DB: D1Database; RELAY_INBOX_HMAC_KEY?: string; RELAY_INBOX_MAIL_DOMAIN?: string };
/** The shared address's local part: `notes@` takes mail only from a checked sender. */
export const SHARED = "notes";
const SECRET = /^notes-[a-z2-7]{10}$/;
const BASE32 = "abcdefghijklmnopqrstuvwxyz234567";
const encoder = new TextEncoder();

/** The mail domain and the HMAC key when this server takes email, else null: email turns on only with both. */
export function inboxOf(env: Omit<InboxEnv, "DB">): { domain: string; key: string } | null {
  const domain = env.RELAY_INBOX_MAIL_DOMAIN?.trim().toLowerCase();
  return domain && env.RELAY_INBOX_HMAC_KEY ? { domain, key: env.RELAY_INBOX_HMAC_KEY } : null;
}

/** HMAC-SHA-256 of the text under the server's inbox key, in hex: D1 keeps only this of an address or a sender. */
async function hmacOf(key: string, text: string): Promise<string> {
  const secret = await crypto.subtle.importKey("raw", encoder.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", secret, encoder.encode(text)));
  return Array.from(mac, byte => byte.toString(16).padStart(2, "0")).join("");
}

const addressHmac = (key: string, local: string) => hmacOf(key, `address:${local.toLowerCase()}`);
export const senderHmac = (key: string, email: string) => hmacOf(key, `sender:${normalEmail(email)}`);

/** A new local part: `notes-` and 10 random base32 letters, 50 bits. */
const newLocal = () => `notes-${Array.from(crypto.getRandomValues(new Uint8Array(10)), byte => BASE32[byte & 31]).join("")}`;

const INSERT = "INSERT INTO relay_inbox_links (channel, sender_hmac, person_id, shown, created_at) VALUES ('email', ?, ?, ?, ?)";

/** The person's secret notes address, made on first read; null when this server takes no email. */
export async function addressOf(env: InboxEnv, personId: string): Promise<string | null> {
  const inbox = inboxOf(env);
  if (!inbox) return null;
  const db = directory(env);
  const read = () => db.prepare("SELECT shown FROM relay_inbox_links WHERE person_id = ? AND channel = 'email'").bind(personId).first<{ shown: string }>();
  let row = await read();
  if (!row) {
    const local = newLocal();
    // Two first reads at once make one address: the person's row is unique, so the second insert does nothing.
    await db.prepare(`${INSERT} ON CONFLICT DO NOTHING`).bind(await addressHmac(inbox.key, local), personId, local, Date.now()).run();
    row = await read();
  }
  return row && `${row.shown}@${inbox.domain}`;
}

/** Replaces the person's address: mail to the old one finds no one from now on. */
export async function newAddress(env: InboxEnv, personId: string): Promise<string | null> {
  const inbox = inboxOf(env);
  if (!inbox) return null;
  const db = directory(env);
  const local = newLocal();
  await db.batch([db.prepare("DELETE FROM relay_inbox_links WHERE person_id = ? AND channel = 'email'").bind(personId),
    db.prepare(INSERT).bind(await addressHmac(inbox.key, local), personId, local, Date.now())]);
  return `${local}@${inbox.domain}`;
}

/** True when the local part has a secret address's shape, so a lookup is worth making. */
const isSecret = (local: string) => SECRET.test(local);

/** The person whose secret address this local part is, as the inbox's caller, or null. */
export async function byAddress(env: InboxEnv, local: string): Promise<Caller | null> {
  const inbox = inboxOf(env);
  if (!inbox || !isSecret(local)) return null;
  const row = await directory(env).prepare(`SELECT p.id, p.email FROM relay_inbox_links l JOIN relay_people p ON p.id = l.person_id
    WHERE l.channel = 'email' AND l.sender_hmac = ?`).bind(await addressHmac(inbox.key, local)).first<{ id: string; email: string }>();
  return row && vouch("inbox", row.id, { email: row.email });
}

/** The person who signs in with this email, as the inbox's caller, or null. Call it only for an email the mail's
 *  sender checks proved, or a person's own at sign-in. */
export async function bySignIn(env: InboxEnv, email: string): Promise<Caller | null> {
  const person = await personByEmail(env, email);
  return person && vouch("inbox", person.id, { email: person.email });
}
