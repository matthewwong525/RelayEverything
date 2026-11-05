// Relay's server: ring notes, typed notes, health and location from the phones, read back and sent on to webhooks.
// A device key reaches only these routes but summary, the AI apps and the webhooks: device.ts.
import type { Route } from "../../api/contract.ts";
import { aiAppDisconnect, aiApps } from "./ai-apps.ts";
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
  ["GET ai-apps", aiApps],
  ["POST ai-apps-disconnect", aiAppDisconnect],
]);

/** The webhooks' queue, keyed by its name without `-staging`, and the sweep production runs every 15 minutes. */
export const queues = new Map([["relay-everything-webhooks", consume]]);
export const scheduled = async (env: Parameters<typeof sweep>[0]) => { await sweep(env); };
