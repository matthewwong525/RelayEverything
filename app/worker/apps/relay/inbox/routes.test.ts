import { expect, it, vi } from "vitest";
import { ben, call, directoryDb, matthew, NOW, phone } from "../../../../tests/relay";
import { DOMAIN, inboxEnv } from "../../../../tests/relay-inbox";
import { hold, KEEP_MS } from "./held";

const MAIL = { RELAY_INBOX_HMAC_KEY: "test-inbox-key", RELAY_INBOX_MAIL_DOMAIN: DOMAIN };
const address = expect.stringMatching(new RegExp(`^notes-[a-z2-7]{10}@${DOMAIN.replaceAll(".", "\\.")}$`));

it("shows the signed-in person their own notes address, the same each time, and the shared one", async () => {
  const first = await call(matthew, "GET", "inbox", undefined, MAIL);
  expect(first).toEqual({ status: 200, json: { email: { on: true, address, shared: `notes@${DOMAIN}` } } });
  expect((await call(matthew, "GET", "inbox", undefined, MAIL)).json).toEqual(first.json);
  expect((await call(ben, "GET", "inbox", undefined, MAIL)).json.email.address).not.toBe(first.json.email.address);
});

it("makes a new address in place of the old one", async () => {
  const old = (await call(matthew, "GET", "inbox", undefined, MAIL)).json.email.address;
  const made = await call(matthew, "POST", "inbox/address", {}, MAIL);
  expect(made.json.email.address).toEqual(address);
  expect(made.json.email.address).not.toBe(old);
  expect((await call(matthew, "GET", "inbox", undefined, MAIL)).json.email.address).toBe(made.json.email.address);
});

it("says email is off, with no address, on a server with no mail domain or key", async () => {
  expect((await call(matthew, "GET", "inbox")).json).toEqual({ email: { on: false, address: null, shared: null } });
  expect((await call(matthew, "POST", "inbox/address", {})).status).toBe(503);
  expect(directoryDb.sql.prepare("SELECT count(*) AS count FROM relay_inbox_links").get()).toEqual({ count: 0 });
});

it("refuses a device key and a caller with no person", async () => {
  for (const [method, route] of [["GET", "inbox"], ["POST", "inbox/address"], ["POST", "inbox/sweep"]]) {
    expect((await call(phone, method, route, method === "POST" ? {} : undefined, MAIL)).status).toBe(403);
    expect((await call(null, method, route, method === "POST" ? {} : undefined, MAIL)).status).toBe(401);
  }
});

it("runs the kept mail's daily sweep by hand on staging, and never on the live server", async () => {
  vi.setSystemTime(NOW - KEEP_MS - 1);
  await hold(inboxEnv(), "cy@example.com", { channel: "email", id: "m-1", sentAt: NOW, text: "Old", files: [] });
  vi.setSystemTime(NOW);
  expect((await call(matthew, "POST", "inbox/sweep", {}, { ...MAIL, WONG_ENVIRONMENT: "production" })).status).toBe(403);
  expect((await call(matthew, "POST", "inbox/sweep", {}, { ...MAIL, WONG_ENVIRONMENT: "staging" })).json).toEqual({ deleted: 1 });
});
