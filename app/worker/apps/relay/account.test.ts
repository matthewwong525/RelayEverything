import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ANA, BEN, ben, benPhone, bucket, call, checker, directoryDb, matthew, NOW, owner, phone, rows, sendPhoto, spaces } from "../../../tests/relay";
import { hashToken } from "./people";

const PEOPLE_TABLES = ["relay_keys", "relay_sessions", "relay_logins", "relay_connect_codes"];

/** The AI connector's grants: one each for Ana and Ben, gone once revoked. */
function connector() {
  const held = new Map([["grant-ana", ANA], ["grant-ben", BEN]]);
  return {
    list: vi.fn(async (person: string) => ({ apps: [...held].filter(([, holder]) => holder === person).map(([id]) => ({ id })) })),
    revoke: vi.fn(async (id: string, person: string) => held.get(id) === person && held.delete(id)),
  };
}

/** How many rows each directory table holds for a person. */
const counts = (person: string) => PEOPLE_TABLES.map(table =>
  (directoryDb.sql.prepare(`SELECT count(*) AS count FROM ${table} WHERE person_id = ?`).get(person) as { count: number }).count);

beforeEach(() => {
  const note = (person: string, id: string, device: string) => spaces.sql(person).prepare(`INSERT INTO relay_notes (id, device_id, source,
    text, recorded_at, created_at) VALUES (?, ?, 'typed', 'Buy flux', ?, ?)`).run(id, device, NOW, NOW);
  note(ANA, "note-ana", "d-phone");
  note(BEN, "note-ben", "d-ben");
  // Three of Ana's recordings take two pages of the bucket's list.
  for (const name of ["a", "b", "c"]) bucket.objects.set(`people/${ANA}/${name}`, new Uint8Array([1]));
  bucket.objects.set(`people/${BEN}/d`, new Uint8Array([2]));
  for (const [person, subject] of [[ANA, "apple-ana"], [BEN, "apple-ben"]]) {
    directoryDb.sql.prepare("INSERT INTO relay_logins (provider, subject, person_id, created_at) VALUES ('apple', ?, ?, ?)").run(subject, person, NOW);
    directoryDb.sql.prepare("INSERT INTO relay_connect_codes (code_sha256, person_id, expires_at) VALUES (?, ?, ?)").run(`code-${person}`, person, NOW + 1);
  }
  for (const email of ["ana@example.com", "ben@example.com"]) {
    directoryDb.sql.prepare("INSERT INTO relay_sign_in_codes (email, code_sha256, expires_at) VALUES (?, 'x', ?)").run(email, NOW + 1);
  }
});

afterEach(() => vi.restoreAllMocks());

it("answers the signed-in person's own email, and none for the preview checker", async () => {
  expect(await call(matthew, "GET", "account")).toEqual({ status: 200, json: { email: "ana@example.com" } });
  expect(await call(ben, "GET", "account")).toEqual({ status: 200, json: { email: "ben@example.com" } });
  expect(await call(owner, "GET", "account")).toEqual({ status: 200, json: { email: "ana@example.com" } });
  expect(await call(checker, "GET", "account", undefined, { RELAY_CHECKER_SHA256: await hashToken("checker.access") }))
    .toEqual({ status: 200, json: { email: "" } });
  expect((await call(phone, "GET", "account")).status).toBe(403);
  expect((await call(null, "GET", "account")).status).toBe(401);
});

it("deletes nothing unless the typed email is the account's own", async () => {
  const grants = connector();
  for (const email of ["ben@example.com", "", "ana@example.org"]) {
    expect((await call(matthew, "POST", "account-delete", { email }, { RELAY_MCP: grants })).status, email).toBe(400);
  }
  // The checker has no email, so it can never delete its test person.
  const checked = { RELAY_MCP: grants, RELAY_CHECKER_SHA256: await hashToken("checker.access") };
  expect((await call(checker, "POST", "account-delete", { email: "" }, checked)).status).toBe(400);
  expect((await call(phone, "POST", "account-delete", { email: "ana@example.com" }, { RELAY_MCP: grants })).status).toBe(403);
  expect(grants.list).not.toHaveBeenCalled();
  expect(counts(ANA)).toEqual([4, 1, 1, 1]);
  expect(bucket.objects.size).toBe(4);
  expect(rows("relay_notes")).toHaveLength(1);
});

it("deletes Ana's account whole, and leaves Ben's data, key and session as they were", async () => {
  const grants = connector();
  expect(await call(matthew, "POST", "account-delete", { email: " Ana@Example.com " }, { RELAY_MCP: grants }))
    .toEqual({ status: 200, json: { deleted: true } });
  // Her key, her session and her AI app are refused from now on.
  expect((await call(phone, "GET", "key")).status).toBe(403);
  expect((await call(matthew, "GET", "account")).status).toBe(401);
  expect(grants.revoke.mock.calls).toEqual([["grant-ana", ANA]]);
  expect(await grants.list(ANA)).toEqual({ apps: [] });
  // Her recordings, her space and her rows in the directory are gone.
  expect([...bucket.objects.keys()]).toEqual([`people/${BEN}/d`]);
  expect(spaces.objects.has(ANA)).toBe(false);
  expect(counts(ANA)).toEqual([0, 0, 0, 0]);
  expect(directoryDb.sql.prepare("SELECT email FROM relay_people").all()).toEqual([{ email: "ben@example.com" }]);
  expect(directoryDb.sql.prepare("SELECT email FROM relay_sign_in_codes").all()).toEqual([{ email: "ben@example.com" }]);
  // Ben is untouched.
  expect(counts(BEN)).toEqual([1, 1, 1, 1]);
  expect(rows("relay_notes", BEN)).toEqual([expect.objectContaining({ id: "note-ben" })]);
  expect(await call(benPhone, "GET", "key")).toEqual({ status: 200, json: { device: "Ben's phone" } });
  expect(await call(ben, "GET", "account")).toEqual({ status: 200, json: { email: "ben@example.com" } });
  expect(await grants.list(BEN)).toEqual({ apps: [{ id: "grant-ben" }] });
});

it("deletes an account with no recordings, on a server with no AI connector", async () => {
  bucket.objects.delete(`people/${BEN}/d`);
  expect(await call(ben, "POST", "account-delete", { email: "ben@example.com" })).toEqual({ status: 200, json: { deleted: true } });
  expect(counts(BEN)).toEqual([0, 0, 0, 0]);
  expect([...bucket.objects.keys()].every(name => name.startsWith(`people/${ANA}/`))).toBe(true);
  expect(counts(ANA)).toEqual([4, 1, 1, 1]);
});

it("leaves no way in when a step fails partway, and a second try finishes the deletion", async () => {
  const grants = connector();
  bucket.delete.mockRejectedValueOnce(new Error("R2 is down"));
  const failed = await call(matthew, "POST", "account-delete", { email: "ana@example.com" }, { RELAY_MCP: grants }).catch(() => null);
  expect(failed?.status ?? 500).toBe(500);
  // Her keys, sessions, logins and AI app are gone, though her notes are still there.
  expect(counts(ANA)).toEqual([0, 0, 0, 0]);
  expect((await call(phone, "GET", "key")).status).toBe(403);
  expect((await call(matthew, "GET", "account")).status).toBe(401);
  expect(await grants.list(ANA)).toEqual({ apps: [] });
  expect(rows("relay_notes")).toHaveLength(1);
  // Signed in again, she deletes again, and this time it all goes.
  expect(await call(owner, "POST", "account-delete", { email: "ana@example.com" }, { RELAY_MCP: grants }))
    .toEqual({ status: 200, json: { deleted: true } });
  expect([...bucket.objects.keys()]).toEqual([`people/${BEN}/d`]);
  expect(spaces.objects.has(ANA)).toBe(false);
  expect(directoryDb.sql.prepare("SELECT email FROM relay_people").all()).toEqual([{ email: "ben@example.com" }]);
});

it("deletes Ana's photos with her account, and leaves Ben's", async () => {
  await sendPhoto(phone);
  await sendPhoto(benPhone);
  expect([...bucket.objects.keys()].filter(key => key.includes("/photos/"))).toHaveLength(2);
  expect((await call(matthew, "POST", "account-delete", { email: "ana@example.com" })).status).toBe(200);
  expect([...bucket.objects.keys()].filter(key => key.startsWith(`people/${ANA}/`))).toEqual([]);
  expect([...bucket.objects.keys()].filter(key => key.startsWith(`people/${BEN}/photos/`))).toHaveLength(1);
  expect(rows("relay_photos", BEN)).toHaveLength(1);
});
