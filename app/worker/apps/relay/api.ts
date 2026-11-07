// Relay Everything's server: notes, health and location from the phones, sent on to webhooks, and Claude Code chats,
// each in the caller's own space. A device key only adds data, and checks itself with GET key: caller.ts.
import type { Route } from "../../api/contract.ts";
import { account, accountDelete } from "./account.ts";
import { aiAppDisconnect, aiApps } from "./ai-apps.ts";
import { attachment, attachmentAdd } from "./attachments.ts";
import { audio } from "./audio.ts";
import { chatDelete, chatList, chatRead } from "./chat-read.ts";
import { chats, chatSaves } from "./chats.ts";
import { deviceAdd, deviceOff, devices } from "./device.ts";
import { key } from "./key.ts";
import { notes } from "./notes.ts";
import { pebble } from "./pebble.ts";
import { health, locations } from "./samples.ts";
import { summary } from "./summary.ts";
import { timeline } from "./timeline.ts";
import { add, list, remove, resend, retry, secret, sweepNow, test, update } from "./webhooks/routes.ts";
import { consume } from "./webhooks/send.ts";

export const routes = new Map<string, Route>([
  ["POST pebble", pebble],
  ["POST notes", notes],
  ["POST attachments", attachmentAdd],
  ["POST health", health],
  ["POST locations", locations],
  ["GET key", key],
  ["GET timeline", timeline],
  ["GET summary", summary],
  ["GET audio", audio],
  ["GET attachment", attachment],
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
  ["POST chats", chats],
  ["POST chat-saves", chatSaves],
  ["GET chats", chatList],
  ["GET chat", chatRead],
  ["DELETE chat", chatDelete],
  ["GET devices", devices],
  ["POST devices", deviceAdd],
  ["POST devices/off", deviceOff],
  ["GET account", account],
  ["POST account-delete", accountDelete],
]);

/** The webhooks' queue, keyed by its name without `-staging`. Each space's alarm catches a lost wake-up. */
export const queues = new Map([["relay-everything-webhooks", consume]]);
