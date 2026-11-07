// Relay Everything on the seeded database: the caller comes from the real directory rows, and a preview opens no space.
// Like staging, the runtime has no SPACES: rows inside a space are worker/apps/relay/isolation.test.ts's.
import { createHash } from "node:crypto";
import { beforeEach, expect, it } from "vitest";
import type { AppTests } from "../context.ts";
import { site } from "../identity.ts";
import { resetToSeed } from "../setup.ts";

/** The preview checker's fixed person, seeded by schema/seed.sql (CHECKER_PERSON in caller.ts). */
const CHECKER = "00000000-0000-4000-8000-000000000000";
const PHONE_KEY = `rek_${"p".repeat(43)}`;
const SESSION = "runtime-session-token";
// A preview has no spaces: the route's 503 reaches the caller in the action contract's own words.
const NO_SPACES = "Action failed";
const sha256 = (text: string) => createHash("sha256").update(text).digest("hex");

export const relay: AppTests = context => {
  const db = () => context().runtime.env.DB;
  const people = async () => (await db().prepare("SELECT email FROM relay_people ORDER BY email").all<{ email: string }>()).results
    .map(({ email }) => email);
  /** A Relay Everything route, with a company sign-in, a device key or a session cookie as given. */
  const relay = (method: string, route: string, { token, key, session, body, origin = true }:
    { token?: string; key?: string; session?: string; body?: object; origin?: boolean } = {}) =>
    context().runtime.worker.fetch(`${site.origin}/apps/relay/api/${route}`, {
      method, ...(body && { body: JSON.stringify(body) }),
      headers: { ...(token && { "Cf-Access-Jwt-Assertion": token }), ...(key && { Authorization: `Bearer ${key}` }),
        ...(session && { Cookie: `__Host-relay_session=${session}` }), ...(origin && { Origin: site.origin }),
        ...(body && { "content-type": "application/json" }) },
    });
  const error = async (response: Awaited<ReturnType<typeof relay>>) => [response.status, ((await response.json()) as { error: { message: string } }).error.message];

  beforeEach(async () => {
    await resetToSeed(db());
    const now = Date.now();
    await db().batch([
      db().prepare("INSERT INTO relay_keys (key_sha256, person_id, device_id, reaches, created_at) VALUES (?, ?, 'runtime-phone', 'phone', ?)")
        .bind(sha256(PHONE_KEY), CHECKER, now),
      db().prepare("INSERT INTO relay_sessions (token_sha256, person_id, created_at, expires_at) VALUES (?, ?, ?, ?)")
        .bind(sha256(SESSION), CHECKER, now, now + 3_600_000),
    ]);
  });

  it("refuses a call with no sign-in and no key, and writes nothing", async () => {
    const before = await people();
    for (const [method, route] of [["GET", "timeline"], ["POST", "notes"], ["GET", "key"]]) {
      const response = await relay(method, route, method === "POST" ? { body: { clientId: "runtime-note-1", text: "Hi", createdAt: Date.now() } } : {});
      expect(response.status).toBe(401);
    }
    // A key alone does not pass the company app's sign-in wall: a phone sends to the Relay Everything server.
    expect((await relay("GET", "key", { key: PHONE_KEY })).status).toBe(401);
    expect(await people()).toEqual(before);
  });

  it("checks a device key in the real directory: it reaches only its own routes, and a turned-off or unknown key nothing", async () => {
    const { fay } = context().signed;
    expect(await error(await relay("GET", "timeline", { token: fay, key: PHONE_KEY }))).toEqual([403, "A device key can only send to Relay Everything."]);
    expect(await error(await relay("POST", "webhooks", { token: fay, key: PHONE_KEY, body: {} }))).toEqual([403, "A device key can only send to Relay Everything."]);
    // Its own route passes the check, then finds no space to open: a preview has none.
    expect(await error(await relay("GET", "key", { token: fay, key: PHONE_KEY }))).toEqual([503, NO_SPACES]);
    expect(await error(await relay("GET", "key", { token: fay, key: `rek_${"u".repeat(43)}` }))).toEqual([403, "This key is on no list of devices."]);
    await db().prepare("UPDATE relay_keys SET revoked_at = ? WHERE key_sha256 = ?").bind(Date.now(), sha256(PHONE_KEY)).run();
    expect(await error(await relay("GET", "key", { token: fay, key: PHONE_KEY }))).toEqual([403, "This device key is turned off."]);
  });

  it("makes a person only for one who may join, and a session's change only from the page", async () => {
    const { eli, owner } = context().signed;
    // Sign-up is closed, so Eli's company sign-in gets no Relay Everything person and no space.
    expect(await error(await relay("GET", "timeline", { token: eli }))).toEqual([403, "This email has no Relay Everything account on this server."]);
    expect(await people()).not.toContain("eli@example.invalid");
    // The owner may join: the first call makes their person, with its own id, never the checker's.
    expect(await error(await relay("GET", "timeline", { token: owner }))).toEqual([503, NO_SPACES]);
    const joined = await db().prepare("SELECT id FROM relay_people WHERE email = ?").bind(site.owner).first<{ id: string }>();
    expect(joined?.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(joined?.id).not.toBe(CHECKER);
    // A session cookie names its person from relay_sessions; a change by cookie needs the page's own Origin.
    const { fay } = context().signed;
    expect(await error(await relay("POST", "webhooks", { token: fay, session: SESSION, body: {}, origin: false })))
      .toEqual([403, "This change must come from the Relay Everything page."]);
    expect(await error(await relay("GET", "timeline", { token: fay, session: SESSION }))).toEqual([503, NO_SPACES]);
  });
};
