// Mail to notes@ from a checked email with no account yet: kept sealed for 30 days, at most 100 messages and 50 MB
// for each email, then made into notes when that email signs in. wiki/relay-spaces.md#ways-in
import { directory, normalEmail, type Person } from "../people.ts";
import type { Wait } from "../sign-in/index.ts";
import { heldFiles, type HeldFilesEnv } from "../space.ts";
import { base64 } from "../webhooks/sign.ts";
import { bySignIn, inboxOf, senderHmac, type InboxEnv } from "./links.ts";
import { fitted, receive, type InboxFile, type InboxItem, type ReceiveEnv } from "./receive.ts";

export const KEEP_MS = 30 * 24 * 60 * 60_000;
const MAX_KEPT = 100;
const MAX_BYTES = 50 * 1024 * 1024;
const IV = 12;
const encoder = new TextEncoder();

export type HeldEnv = InboxEnv & ReceiveEnv;
/** What a kept row's sealed body holds: the message, and each file's name and type, whose bytes wait in the bucket. */
type Body = Pick<InboxItem, "id" | "sentAt" | "text"> & { left: string[]; files: Pick<InboxFile, "name" | "type">[] };
type Row = { id: string; sender_hmac: string; body: string };

const folderOf = (hmac: string, id: string) => `held/${hmac}/${id}/`;
const fromBase64 = (text: string) => Uint8Array.from(atob(text), char => char.charCodeAt(0));

/** The key that seals one email's kept mail, made by HKDF from the server's key and the email, which D1 never holds. */
async function sealingKey(secret: string, email: string): Promise<CryptoKey> {
  const base = await crypto.subtle.importKey("raw", encoder.encode(secret), "HKDF", false, ["deriveKey"]);
  return crypto.subtle.deriveKey({ name: "HKDF", hash: "SHA-256", salt: encoder.encode("relay-inbox-held"), info: encoder.encode(normalEmail(email)) },
    base, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}

/** AES-256-GCM with a fresh IV, and its name as associated data, so a copy under another name fails to open. */
async function seal(key: CryptoKey, bytes: Uint8Array, name: string): Promise<Uint8Array> {
  const iv = crypto.getRandomValues(new Uint8Array(IV));
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: encoder.encode(name) }, key, bytes));
  const out = new Uint8Array(IV + sealed.length);
  out.set(iv);
  out.set(sealed, IV);
  return out;
}

async function open(key: CryptoKey, data: Uint8Array, name: string): Promise<Uint8Array | null> {
  try {
    return new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: data.subarray(0, IV), additionalData: encoder.encode(name) },
      key, data.subarray(IV)));
  } catch {
    return null;
  }
}

/** Deletes the rows and each one's files. */
async function drop(env: HeldFilesEnv, rows: Pick<Row, "id" | "sender_hmac">[]) {
  const files = heldFiles(env);
  for (const row of rows) await files.removeAll(folderOf(row.sender_hmac, row.id));
}

/** Keeps a message from an email with no account, sealed, then drops that email's oldest past 100 messages or 50 MB. */
export async function hold(env: HeldEnv, email: string, item: InboxItem): Promise<void> {
  const inbox = inboxOf(env);
  if (!inbox) return;
  const fit = fitted(item);
  const [key, hmac, id] = [await sealingKey(inbox.key, email), await senderHmac(inbox.key, email), crypto.randomUUID()];
  const folder = folderOf(hmac, id);
  const files = heldFiles(env);
  for (const [index, file] of fit.files.entries()) await files.put(`${folder}${index}`, await seal(key, file.bytes, `${folder}${index}`));
  const body: Body = { id: fit.id, sentAt: fit.sentAt, text: fit.text, left: fit.left, files: fit.files.map(({ name, type }) => ({ name, type })) };
  const sealed = await seal(key, encoder.encode(JSON.stringify(body)), id);
  const size = sealed.byteLength + fit.files.reduce((total, file) => total + file.bytes.byteLength, 0);
  const db = directory(env);
  await db.prepare("INSERT INTO relay_inbox_held (id, channel, sender_hmac, sent_at, size, body, created_at) VALUES (?, 'email', ?, ?, ?, ?, ?)")
    .bind(id, hmac, fit.sentAt, size, base64(sealed), Date.now()).run();
  const { results } = await db.prepare(`DELETE FROM relay_inbox_held WHERE id IN (SELECT id FROM (SELECT id,
      ROW_NUMBER() OVER newest AS n, SUM(size) OVER newest AS total FROM relay_inbox_held WHERE channel = 'email' AND sender_hmac = ?
      WINDOW newest AS (ORDER BY created_at DESC, rowid DESC)) WHERE n > ? OR total > ?) RETURNING id, sender_hmac`)
    .bind(hmac, MAX_KEPT, MAX_BYTES).all<Row>();
  await drop(env, results);
  // A self-host has no daily sweep, so each kept mail clears the old ones too.
  await sweep(env);
}

/** Makes the email's kept mail into notes in its person's space, oldest first with their first times, then deletes
 *  it. A claim run twice stores once: each note keeps its message id. With no kept mail, it is one lookup. */
export async function claim(env: HeldEnv, email: string): Promise<number> {
  const inbox = inboxOf(env);
  if (!inbox || !env.SPACES) return 0;
  const hmac = await senderHmac(inbox.key, email);
  const db = directory(env);
  const waiting = await db.prepare("SELECT 1 FROM relay_inbox_held WHERE channel = 'email' AND sender_hmac = ? LIMIT 1").bind(hmac).first();
  const caller = waiting && await bySignIn(env, email);
  if (!caller) return 0;
  const key = await sealingKey(inbox.key, email);
  const { results } = await db.prepare(`SELECT id, sender_hmac, body FROM relay_inbox_held WHERE channel = 'email' AND sender_hmac = ?
    ORDER BY sent_at, created_at`).bind(hmac).all<Row>();
  let claimed = 0;
  for (const row of results) {
    const opened = await open(key, fromBase64(row.body), row.id);
    if (opened) {
      const body = JSON.parse(new TextDecoder().decode(opened)) as Body;
      const files = await filesOf(env, key, folderOf(hmac, row.id), body);
      await receive(env, caller, { channel: "email", id: body.id, sentAt: body.sentAt, text: body.text, ...files });
      claimed++;
    }
    await drop(env, [row]);
    await db.prepare("DELETE FROM relay_inbox_held WHERE id = ?").bind(row.id).run();
  }
  return claimed;
}

/** A kept message's files, opened; one that is gone or does not open is named as left out. */
async function filesOf(env: HeldEnv, key: CryptoKey, folder: string, body: Body): Promise<{ files: InboxFile[]; left: string[] }> {
  const store = heldFiles(env);
  const files: InboxFile[] = [];
  const left = [...body.left];
  for (const [index, file] of body.files.entries()) {
    const sealed = await store.get(`${folder}${index}`);
    const bytes = sealed && await open(key, sealed, `${folder}${index}`);
    if (bytes) files.push({ ...file, bytes });
    else left.push(`${file.name} (could not be read)`);
  }
  return { files, left };
}

/** Deletes kept mail older than 30 days, and its files; answers how many. It reads no space. */
export async function sweep(env: HeldFilesEnv & Pick<HeldEnv, "DB">, now = Date.now()): Promise<number> {
  const { results } = await directory(env).prepare("DELETE FROM relay_inbox_held WHERE created_at < ? RETURNING id, sender_hmac")
    .bind(now - KEEP_MS).all<Row>();
  await drop(env, results);
  return results.length;
}

/** Each sign-in's claim, after the answer when the Worker can wait, so a claim that stops partway finishes later.
 *  The sign-in's env holds the whole server's bindings; claim reads none a server without email lacks. */
export const claimOnSignIn = (env: object, wait?: Wait) => async (person: Person) => {
  const work = claim(env as HeldEnv, person.email).catch(() => 0);
  if (wait) wait(work);
  else await work;
};
