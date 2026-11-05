// Relay's server side: ring notes from the Pebble app, typed notes, health and location from the phones, read back by
// the phones and the site page, and Claude Code chats from a chat key. Which key reaches which route: device.ts.
import type { Route } from "../../api/contract.ts";
import { aiAppDisconnect, aiApps } from "./ai-apps.ts";
import { audio } from "./audio.ts";
import { chatDelete, chatList, chatRead } from "./chat-read.ts";
import { chats, chatSaves } from "./chats.ts";
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
  ["GET ai-apps", aiApps],
  ["POST ai-apps-disconnect", aiAppDisconnect],
  ["POST chats", chats],
  ["POST chat-saves", chatSaves],
  ["GET chats", chatList],
  ["GET chat", chatRead],
  ["DELETE chat", chatDelete],
]);
