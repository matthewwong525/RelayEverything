// The Email card's routes, for the signed-in person only: their secret notes address and the shared one, and a new
// address in place of a leaked one. A staging-only route runs the kept mail's daily sweep by hand.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../../api/contract.ts";
import { asPerson } from "../caller.ts";
import { refused, type Env } from "../store.ts";
import { sweep } from "./held.ts";
import { addressOf, inboxOf, newAddress, SHARED, type InboxEnv } from "./links.ts";

const mailEnv = (env: Env) => env as Env & InboxEnv;
const emailView = z.strictObject({
  on: z.boolean().describe("True when this server takes email: its owner set a mail domain."),
  address: z.string().nullable().describe("Your secret notes address: any mail to it becomes a note. Null when email is off."),
  shared: z.string().nullable().describe("The shared address: mail to it from your sign-in email becomes a note. Null when email is off."),
}).describe("Email notes: whether this server takes email, and your addresses.");

const viewOf = (env: Env, address: string | null) => {
  const inbox = inboxOf(mailEnv(env));
  return { email: { on: !!inbox, address, shared: inbox && `${SHARED}@${inbox.domain}` } };
};

export const inbox = defineAction({
  operationId: "relay.inbox", summary: "Read your notes addresses",
  description: "Answer your secret notes address, made on first read, and the shared address for your sign-in email.",
  input: z.strictObject({}), output: z.strictObject({ email: emailView }),
  encoding: "none", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ caller, env }) => Response.json(viewOf(env, await addressOf(mailEnv(env), caller.personId)))),
});

export const inboxAddress = defineAction({
  operationId: "relay.inbox-address", summary: "Make a new notes address",
  description: "Replace your secret notes address with a new one. Mail to the old address makes no note from now on.",
  input: z.strictObject({}), output: z.strictObject({ email: emailView }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ caller, env }) => {
    const address = await newAddress(mailEnv(env), caller.personId);
    return address ? Response.json(viewOf(env, address)) : refused(503, "This server takes no email.");
  }),
});

export const inboxSweep = defineAction({
  operationId: "relay.inbox-sweep", summary: "Run the kept mail's sweep (previews only)",
  description: "Run what the server runs each day: delete mail kept for emails with no account that is older than 30 days.",
  input: z.strictObject({}), output: z.strictObject({ deleted: z.number().int().describe("How many kept messages it deleted.") }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ env }) => env.WONG_ENVIRONMENT === "production"
    ? refused(403, "On the live server, the sweep runs each day.") : Response.json({ deleted: await sweep(env) })),
});
