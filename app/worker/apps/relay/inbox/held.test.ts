import { expect, it, vi } from "vitest";
import { ANA, bucket, directoryDb, env, NOW, spaces } from "../../../../tests/relay";
import { heldFiles } from "../space";
import { inboxEnv } from "../../../../tests/relay-inbox";
import { signIn, type SignInEnv } from "../sign-in/index";
import { claim, claimOnSignIn, hold, KEEP_MS, sweep } from "./held";
import type { InboxItem } from "./receive";

const CY = "cy@example.com";
const PDF = new TextEncoder().encode("%PDF-1.4 sketch");
const item = (id: string, sentAt: number, more: Partial<InboxItem> = {}): InboxItem =>
  ({ channel: "email", id, sentAt, text: `Idea ${id}`, files: [], ...more });
const held = () => directoryDb.sql.prepare("SELECT id, sender_hmac, sent_at, size, body FROM relay_inbox_held ORDER BY created_at").all() as
  { id: string; sender_hmac: string; sent_at: number; size: number; body: string }[];
const join = (email = CY) => directoryDb.sql.prepare("INSERT INTO relay_people (id, email, created_at) VALUES (?, ?, ?)").run("p-cy", email, NOW);
const notesOf = (person: string) => spaces.sql(person).prepare("SELECT text, recorded_at FROM relay_notes ORDER BY recorded_at").all();

it("keeps mail from an email with no account sealed, then makes it notes in order of sending when that email joins", async () => {
  await hold(inboxEnv(), CY, item("m-2", NOW - 1000, { files: [{ name: "sketch.pdf", type: "application/pdf", bytes: PDF }] }));
  await hold(inboxEnv(), "Cy@Example.com", item("m-1", NOW - 5000));
  expect(held()).toHaveLength(2);
  expect(new Set(held().map(row => row.sender_hmac)).size).toBe(1);
  // Neither the directory nor the bucket holds the words, the email or the file's bytes in the clear.
  const stored = JSON.stringify(held()) + [...bucket.objects.values()].map(bytes => Buffer.from(bytes).toString("latin1")).join("");
  for (const secret of ["Idea", "cy@example.com", "sketch", "%PDF"]) expect(stored).not.toContain(secret);
  expect(await claim(inboxEnv(), CY)).toBe(0);

  join();
  expect(await claim(inboxEnv(), CY)).toBe(2);
  expect(notesOf("p-cy")).toEqual([{ text: "Idea m-1", recorded_at: NOW - 5000 }, { text: "Idea m-2", recorded_at: NOW - 1000 }]);
  expect(spaces.sql("p-cy").prepare("SELECT name, content_type FROM relay_attachments").all()).toEqual([{ name: "sketch.pdf",
    content_type: "application/pdf" }]);
  expect([held(), [...bucket.objects.keys()].filter(key => key.startsWith("held/"))]).toEqual([[], []]);
  expect(await claim(inboxEnv(), CY)).toBe(0);
  expect(notesOf("p-cy")).toHaveLength(2);
});

it("stores a message once when a claim runs twice before it deletes", async () => {
  await hold(inboxEnv(), CY, item("m-1", NOW - 5000));
  join();
  const [row] = held();
  await claim(inboxEnv(), CY);
  directoryDb.sql.prepare("INSERT INTO relay_inbox_held (id, channel, sender_hmac, sent_at, size, body, created_at) VALUES (?, 'email', ?, ?, ?, ?, ?)")
    .run(row.id, row.sender_hmac, row.sent_at, row.size, row.body, NOW);
  expect(await claim(inboxEnv(), CY)).toBe(1);
  expect(notesOf("p-cy")).toHaveLength(1);
});

it("keeps at most 100 messages for one email, dropping the oldest, and leaves other emails' alone", async () => {
  await hold(inboxEnv(), "dee@example.com", item("d-1", NOW));
  for (let index = 0; index < 101; index++) {
    vi.setSystemTime(NOW + index);
    await hold(inboxEnv(), CY, item(`m-${index}`, NOW + index));
  }
  expect(held()).toHaveLength(101);
  join();
  expect(await claim(inboxEnv(), CY)).toBe(100);
  expect((notesOf("p-cy")[0] as { text: string }).text).toBe("Idea m-1");
  expect(held()).toHaveLength(1);
});

it("keeps at most 50 MB for one email, dropping the oldest message and its files", async () => {
  const file = (name: string) => [{ name, type: "application/octet-stream", bytes: new Uint8Array(20 * 1024 * 1024) }];
  for (const [index, name] of ["a.bin", "b.bin", "c.bin"].entries()) {
    vi.setSystemTime(NOW + index);
    await hold(inboxEnv(), CY, item(`m-${index}`, NOW + index, { files: file(name) }));
  }
  expect(held()).toHaveLength(2);
  expect([...bucket.objects.keys()].filter(key => key.startsWith("held/"))).toHaveLength(2);
});

it("opens no kept mail with the directory alone, or with another server's key", async () => {
  await hold(inboxEnv(), CY, item("m-1", NOW));
  join();
  expect(await claim(inboxEnv({ RELAY_INBOX_HMAC_KEY: "another-key" }), CY)).toBe(0);
  expect(held()).toHaveLength(1);
  const [row] = held();
  directoryDb.sql.prepare("UPDATE relay_inbox_held SET body = ?").run(Buffer.from("not sealed").toString("base64"));
  expect(await claim(inboxEnv(), CY)).toBe(0);
  expect([held(), notesOf("p-cy")]).toEqual([[], []]);
  expect(row.body).not.toContain("Idea");
});

it("names a kept file that is gone as not read, and keeps kept mail under held/ only", async () => {
  await hold(inboxEnv(), CY, item("m-1", NOW, { files: [{ name: "sketch.pdf", type: "application/pdf", bytes: PDF }] }));
  for (const key of [...bucket.objects.keys()]) bucket.objects.delete(key);
  join();
  await claim(inboxEnv(), CY);
  expect(notesOf("p-cy")).toEqual([{ text: "Idea m-1\n\nLeft out: sketch.pdf (could not be read).", recorded_at: NOW }]);
  await expect(heldFiles(inboxEnv()).put(`people/${ANA}/x`, PDF)).rejects.toThrow("held/");
});

it("keeps nothing with email off, and a failed claim never fails the sign-in", async () => {
  await hold(env(), CY, item("m-1", NOW));
  expect(held()).toEqual([]);
  const broken = inboxEnv({ DB: { withSession: () => { throw new Error("The directory is down"); } } });
  await expect(claimOnSignIn(broken)({ id: "p-cy", email: CY })).resolves.toBeUndefined();
});

it("sweeps only mail kept over 30 days, with its files", async () => {
  await hold(inboxEnv(), CY, item("m-old", NOW, { files: [{ name: "old.pdf", type: "application/pdf", bytes: PDF }] }));
  vi.setSystemTime(NOW + KEEP_MS);
  await hold(inboxEnv(), CY, item("m-new", NOW + KEEP_MS));
  expect(held()).toHaveLength(2);
  expect(await sweep(inboxEnv(), NOW + KEEP_MS + 1)).toBe(1);
  expect(held().map(row => row.sent_at)).toEqual([NOW + KEEP_MS]);
  expect([...bucket.objects.keys()].filter(key => key.startsWith("held/"))).toEqual([]);
});

/** Signs in with an emailed code, as the page does, and answers the sign-in's answer and the work it left to wait. */
async function signInWithCode(email = CY) {
  const mail = { sent: [] as { text: string }[], send: vi.fn(async (message: { text: string }) => { mail.sent.push(message); return { messageId: "m" }; }) };
  const signUp = inboxEnv({ RELAY_EMAIL: mail, RELAY_SIGN_IN_FROM: "sign-in@example.com", RELAY_SIGN_UP: "open",
    RELAY_SIGN_IN_LIMIT: { limit: async () => ({ success: true }) } }) as unknown as SignInEnv;
  const post = (path: string, body: unknown) => new Request(`https://relay.example.com/apps/relay/sign-in/${path}`,
    { method: "POST", body: JSON.stringify(body), headers: { Origin: "https://relay.example.com", "content-type": "application/json" } });
  await signIn(post("email", { email }), signUp, null);
  const waits: Promise<unknown>[] = [];
  const answer = await signIn(post("code", { email, code: /\d{6}/.exec(mail.sent[0].text)![0] }), signUp, null, work => waits.push(work));
  return { answer: answer!, waits };
}

it("makes kept mail notes when its email signs up with a code", async () => {
  await hold(inboxEnv(), CY, item("m-1", NOW - 5000));
  const { answer, waits } = await signInWithCode();
  expect(answer.status).toBe(200);
  expect(waits).toHaveLength(1);
  await Promise.all(waits);
  const { id } = directoryDb.sql.prepare("SELECT id FROM relay_people WHERE email = ?").get(CY) as { id: string };
  expect(notesOf(id)).toEqual([{ text: "Idea m-1", recorded_at: NOW - 5000 }]);
  expect(held()).toEqual([]);
});

it("finishes a claim that stopped partway at the next sign-in, storing each message once", async () => {
  await hold(inboxEnv(), CY, item("m-1", NOW - 5000));
  await hold(inboxEnv(), CY, item("m-2", NOW - 1000));
  join();
  // The first claim stops after its first message, as when the Worker's time to wait runs out.
  const base = inboxEnv();
  let deletes = 0;
  const session = (mode: D1SessionConstraint) => new Proxy(base.DB.withSession(mode), { get: (inner, name) => name === "prepare"
    ? (sql: string) => {
      if (sql.startsWith("DELETE FROM relay_inbox_held WHERE id") && ++deletes > 1) throw new Error("Time is up");
      return inner.prepare(sql);
    }
    : Reflect.get(inner, name) });
  const stops = { ...base, DB: { withSession: session } as unknown as D1Database };
  await expect(claim(stops, CY)).rejects.toThrow("Time is up");
  expect(held()).toHaveLength(1);

  const { answer, waits } = await signInWithCode();
  expect(answer.status).toBe(200);
  await Promise.all(waits);
  expect(notesOf("p-cy")).toEqual([{ text: "Idea m-1", recorded_at: NOW - 5000 }, { text: "Idea m-2", recorded_at: NOW - 1000 }]);
  expect(held()).toEqual([]);
});
