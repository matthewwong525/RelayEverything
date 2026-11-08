import { expect, it } from "vitest";
import { ANA, BEN, directoryDb, env } from "../../../../tests/relay";
import { addressOf, byAddress, bySignIn, newAddress } from "./links";
import { DOMAIN, inboxEnv } from "../../../../tests/relay-inbox";

const localOf = (address: string | null) => address!.slice(0, address!.indexOf("@"));

it("makes a person's secret address on first read, keeps it, and finds its person by it", async () => {
  const address = await addressOf(inboxEnv(), ANA);
  expect(address).toMatch(new RegExp(`^notes-[a-z2-7]{10}@${DOMAIN.replaceAll(".", "\\.")}$`));
  expect(await addressOf(inboxEnv(), ANA)).toBe(address);
  expect(await addressOf(inboxEnv(), BEN)).not.toBe(address);
  expect((await byAddress(inboxEnv(), localOf(address)))?.personId).toBe(ANA);
  // The directory keeps only an HMAC of the address to find it, never the address alone as its key.
  const [row] = directoryDb.sql.prepare("SELECT sender_hmac, shown FROM relay_inbox_links WHERE person_id = ?").all(ANA) as { sender_hmac: string }[];
  expect(row.sender_hmac).toMatch(/^[0-9a-f]{64}$/);
});

it("finds no one at a replaced address, a made-up one, or with email off", async () => {
  const old = await addressOf(inboxEnv(), ANA);
  const fresh = await newAddress(inboxEnv(), ANA);
  expect(fresh).not.toBe(old);
  expect(await byAddress(inboxEnv(), localOf(old))).toBeNull();
  expect((await byAddress(inboxEnv(), localOf(fresh)))?.personId).toBe(ANA);
  expect(await byAddress(inboxEnv(), "notes-aaaaaaaaaa")).toBeNull();
  expect(await byAddress(inboxEnv(), "notes")).toBeNull();
  expect(await byAddress(inboxEnv({ RELAY_INBOX_HMAC_KEY: "another-key" }), localOf(fresh))).toBeNull();
  expect(await addressOf(env(), ANA)).toBeNull();
  expect(await newAddress(env(), ANA)).toBeNull();
});

it("finds a person by their sign-in email in any case, and no one for an email with no account", async () => {
  expect((await bySignIn(inboxEnv(), " Ana@Example.com "))?.personId).toBe(ANA);
  expect(await bySignIn(inboxEnv(), "cy@example.com")).toBeNull();
});
