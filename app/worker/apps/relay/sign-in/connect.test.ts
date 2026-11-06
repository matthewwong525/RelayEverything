import { beforeEach, expect, it } from "vitest";
import type { AccessIdentity } from "../../../access";
import { body } from "../../../../tests/body";
import { database } from "../../../../tests/employee-access/connections";
import { hashToken } from "../people";
import { signIn, type SignInEnv } from "./index";

const ORIGIN = "https://app.example.com";
const CALLBACK = "https://mcp.example.com/callback";
const KEY = `rek_${"a".repeat(43)}`;
let db: ReturnType<typeof database>;
const env = (more: object = {}) => ({ DB: db.DB, RELAY_MCP_CALLBACK: CALLBACK, ...more }) as unknown as SignInEnv;
const connect = async (query: string, headers: Record<string, string> = {}, more?: object, identity: AccessIdentity | null = null) =>
  (await signIn(new Request(`${ORIGIN}/apps/relay/sign-in/connect${query}`, { headers }), env(more), identity))!;

beforeEach(async () => {
  db = database();
  db.sql.prepare("INSERT INTO relay_people VALUES ('p-ana', 'ana@example.com', 1)").run();
  db.sql.prepare("INSERT INTO relay_sessions VALUES (?, 'p-ana', 1, ?)").run(await hashToken("ana-session"), Date.now() + 60_000);
  db.sql.prepare("INSERT INTO relay_keys VALUES (?, 'p-ana', 'd-1', 'phone', 1, NULL)").run(await hashToken(KEY));
});

it("hands the signed-in person's AI app a single-use code, only at the connector's own callback", async () => {
  const response = await connect("?state=s-1&redirect=https://evil.example.com", { Cookie: "__Host-relay_session=ana-session" });
  expect(response.status).toBe(302);
  const location = new URL(response.headers.get("Location")!);
  expect(location.origin + location.pathname).toBe(CALLBACK);
  expect(location.searchParams.get("state")).toBe("s-1");
  const code = location.searchParams.get("code")!;
  const row = db.sql.prepare("SELECT * FROM relay_connect_codes").get() as { code_sha256: string; person_id: string; expires_at: number };
  expect(row.code_sha256).toBe(await hashToken(code));
  expect(row.person_id).toBe("p-ana");
  expect(row.expires_at - Date.now()).toBeLessThanOrEqual(5 * 60_000);
});

it("admits the owner Access signed in on a self-hosted server", async () => {
  const owner: AccessIdentity = { kind: "user", id: "owner@example.com", claims: { email: "owner@example.com", sub: "o", iss: "i", aud: "a", exp: 9e9 } };
  const response = await connect("?state=s-1", {}, { WONG_OWNER_EMAIL: "owner@example.com" }, owner);
  expect(new URL(response.headers.get("Location")!).searchParams.has("code")).toBe(true);
});

it("sends a person who is not signed in to sign in first, and back here after", async () => {
  const response = await connect("?state=s-1");
  expect(response.headers.get("Location")).toBe(`/apps/relay/?next=${encodeURIComponent("/apps/relay/sign-in/connect?state=s-1")}`);
});

it("refuses a device key, a turned-off key, no state, a long state, and a server with no connector", async () => {
  expect((await connect("?state=s-1", { Authorization: `Bearer ${KEY}` })).status).toBe(403);
  db.sql.prepare("UPDATE relay_keys SET revoked_at = 2").run();
  const off = await connect("?state=s-1", { Authorization: `Bearer ${KEY}` });
  expect((await body(off)).error.message).toBe("This device key is turned off.");
  expect((await connect("")).status).toBe(400);
  expect((await connect(`?state=${"s".repeat(513)}`)).status).toBe(400);
  expect((await connect("?state=s-1", {}, { RELAY_MCP_CALLBACK: undefined })).status).toBe(503);
  expect(db.sql.prepare("SELECT count(*) AS n FROM relay_connect_codes").get()).toEqual({ n: 0 });
});
