// Relay's server side: ring notes from the Pebble app, typed notes, health and location from the phones, read back by
// the phones and the site page, and sent on to the owner's webhooks. A device key reaches neither summary nor webhooks.
import type { Route } from "../../api/contract.ts";
import { audio } from "./audio.ts";
import { notes } from "./notes.ts";
import { pebble } from "./pebble.ts";
import { health, locations } from "./samples.ts";
import { summary } from "./summary.ts";
import { timeline } from "./timeline.ts";
import { add, list, remove, resend, retry, secret, sweepNow, test, update } from "./webhooks/routes.ts";
import { consume } from "./webhooks/send.ts";
import { sweep } from "./webhooks/sweep.ts";

export const routes = new Map<string, Route>([
  ["POST pebble", pebble],
  ["POST notes", notes],
  ["POST health", health],
  ["POST locations", locations],
  ["GET timeline", timeline],
  ["GET summary", summary],
  ["GET audio", audio],
  ["GET webhooks", list],
  ["POST webhooks", add],
  ["POST webhooks/update", update],
  ["POST webhooks/remove", remove],
  ["POST webhooks/secret", secret],
  ["POST webhooks/test", test],
  ["POST webhooks/resend", resend],
  ["POST webhooks/retry", retry],
  ["POST webhooks/sweep", sweepNow],
]);

/** The webhooks' queue, keyed by its name without `-staging`, and the sweep production runs every 15 minutes. */
export const queues = new Map([["relay-webhooks", consume]]);
export const scheduled = async (env: Parameters<typeof sweep>[0]) => { await sweep(env); };
