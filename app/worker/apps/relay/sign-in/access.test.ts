// Task 3.3: a self-hosted server signs in with Access. An Access email gets a person only while the server may take it.
import { beforeEach, expect, it } from "vitest";
import type { AccessIdentity } from "../../../access-slots";
import { database } from "../../../../tests/employee-access/connections";
import { callerOf, type CallerEnv } from "../caller";

let db: ReturnType<typeof database>;
const user = (email: string): AccessIdentity => ({ kind: "user", id: email, claims: { email, sub: email, iss: "i", aud: "a", exp: 9e9 } });
const ask = (email: string, more: object = {}) =>
  callerOf(new Request("https://relay.example.com/apps/relay/api/timeline"), { DB: db.DB, WONG_OWNER_EMAIL: "owner@example.com", ...more } as CallerEnv, user(email));
const people = () => db.sql.prepare("SELECT email FROM relay_people").all();

beforeEach(() => { db = database(); });

it("admits the owner, and makes their person once", async () => {
  const first = await ask("Owner@example.com");
  expect(first).toMatchObject({ kind: "access", email: "owner@example.com" });
  expect(await ask("owner@example.com")).toMatchObject({ personId: (first as { personId: string }).personId });
  expect(people()).toEqual([{ email: "owner@example.com" }]);
});

it("refuses a stranger while sign-up is not open, and admits them once it is", async () => {
  const refused = await ask("stranger@example.com");
  expect(refused).toBeInstanceOf(Response);
  expect((refused as Response).status).toBe(403);
  expect(people()).toEqual([]);
  expect(await ask("stranger@example.com", { RELAY_SIGN_UP: "open" })).toMatchObject({ kind: "access", email: "stranger@example.com" });
});
