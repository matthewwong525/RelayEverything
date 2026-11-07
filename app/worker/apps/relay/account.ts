// GET account and POST account-delete: who is signed in, and *Delete my account*, which removes the person's keys,
// sign-ins and AI apps, then recordings, photos and space, then their row. It can't be undone.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asPerson } from "./caller.ts";
import { directory, normalEmail } from "./people.ts";
import { refused, type Env } from "./store.ts";

const CONFIRM = "Type your account's email to confirm.";
type Grants = { list(personId: string): Promise<{ apps: { id: string }[] }>; revoke(id: string, personId: string): Promise<boolean> };

export const account = defineAction({
  operationId: "relay.account", summary: "Read the account", description: "Answer the signed-in person's email.",
  input: z.strictObject({}), output: z.strictObject({ email: z.string() }),
  encoding: "none", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ caller }) => Response.json({ email: caller.email ?? "" })),
});

/** Ends each AI app the person connected, so no grant outlives the account. */
async function endGrants(env: Env, personId: string) {
  const connector = (env as Env & { RELAY_MCP?: Grants }).RELAY_MCP;
  if (!connector) return;
  for (const app of (await connector.list(personId)).apps) await connector.revoke(app.id, personId);
}

export const accountDelete = defineAction({
  operationId: "relay.account-delete", summary: "Delete my account",
  description: "Delete your account: your notes, recordings, photos, health, places, chats, devices, webhooks and AI apps. It can't be undone.",
  input: z.strictObject({ email: z.string().max(320).describe("Your account's email, typed to confirm.") }),
  output: z.strictObject({ deleted: z.literal(true) }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: { invalid_input: CONFIRM }, examples: [],
  handler: asPerson<ActionCall>(async ({ space, caller, env, call }) => {
    if (!caller.email || normalEmail((call.input as { email: string }).email) !== caller.email) {
      return refused(400, CONFIRM);
    }
    // The ways in go first and the space last: a step that fails leaves no way into a half-deleted account, and the
    // person row stays, so signing in again and deleting again finishes it.
    const db = directory(env);
    await db.batch(["relay_keys", "relay_sessions", "relay_logins", "relay_connect_codes"]
      .map(table => db.prepare(`DELETE FROM ${table} WHERE person_id = ?`).bind(caller.personId)));
    await endGrants(env, caller.personId);
    await space.files.removeAll();
    await space.deleteEverything();
    await db.batch([db.prepare("DELETE FROM relay_sign_in_codes WHERE email = ?").bind(caller.email),
      db.prepare("DELETE FROM relay_people WHERE id = ?").bind(caller.personId)]);
    return Response.json({ deleted: true });
  }),
});
