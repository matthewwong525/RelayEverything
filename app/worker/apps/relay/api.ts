// Relay's server side: ring notes from the Pebble app, typed notes, health and location from the phones, read back by
// the phones and the site page. A device key reaches only these routes but summary: device.ts.
import type { Route } from "../../api/contract.ts";
import { audio } from "./audio.ts";
import { notes } from "./notes.ts";
import { pebble } from "./pebble.ts";
import { health, locations } from "./samples.ts";
import { summary } from "./summary.ts";
import { timeline } from "./timeline.ts";

export const routes = new Map<string, Route>([
  ["POST pebble", pebble],
  ["POST notes", notes],
  ["POST health", health],
  ["POST locations", locations],
  ["GET timeline", timeline],
  ["GET summary", summary],
  ["GET audio", audio],
]);
