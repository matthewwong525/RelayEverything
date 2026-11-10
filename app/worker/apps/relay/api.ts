// Relay Everything's server: notes, health, location, calendar and photos from the phones, all but photos sent on to
// webhooks, and AI chats, each in the caller's own space. A device key only adds data: caller.ts.
import type { Route } from "../../api/contract.ts";
import { account, accountDelete } from "./account.ts";
import { aiAppDisconnect, aiApps } from "./ai-apps.ts";
import { attachment, attachmentAdd } from "./attachments.ts";
import { audio } from "./audio.ts";
import { calendar } from "./calendar.ts";
import { chatDelete, chatList, chatRead } from "./chat-read.ts";
import { chats, chatSaves } from "./chats.ts";
import { connections } from "./connections.ts";
import { noteDelete } from "./delete-note.ts";
import { deviceAdd, deviceOff, devices } from "./device.ts";
import { noteEdit } from "./edit-note.ts";
import { inbox, inboxAddress, inboxSweep } from "./inbox/routes.ts";
import { key } from "./key.ts";
import { nights } from "./nights.ts";
import { notes } from "./notes.ts";
import { noteSync } from "./note-sync.ts";
import { photoAdd, photoCount, photoDelete } from "./photos.ts";
import { health, locations } from "./samples.ts";
import { stays } from "./stays.ts";
import { summary } from "./summary.ts";
import { timeline } from "./timeline.ts";
import { add, list, remove, resend, retry, secret, sweepNow, test, update } from "./webhooks/routes.ts";
import { consume } from "./webhooks/send.ts";

export const routes = new Map<string, Route>([
  ["POST notes", notes],
  ["PATCH notes", noteEdit],
  ["DELETE notes", noteDelete],
  ["GET notes", noteSync],
  ["POST attachments", attachmentAdd],
  ["POST health", health],
  ["POST locations", locations],
  ["POST stays", stays],
  ["POST nights", nights],
  ["POST calendar", calendar],
  ["POST photos", photoAdd],
  ["GET photos", photoCount],
  ["POST photos/delete", photoDelete],
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
  ["GET connections", connections],
  ["POST chats", chats],
  ["POST chat-saves", chatSaves],
  ["GET chats", chatList],
  ["GET chat", chatRead],
  ["DELETE chat", chatDelete],
  ["GET devices", devices],
  ["POST devices", deviceAdd],
  ["POST devices/off", deviceOff],
  ["GET inbox", inbox],
  ["POST inbox/address", inboxAddress],
  ["POST inbox/sweep", inboxSweep],
  ["GET account", account],
  ["POST account-delete", accountDelete],
]);

/** The webhooks' queue, keyed by its name without `-staging`. Each space's alarm catches a lost wake-up. */
export const queues = new Map([["relay-everything-webhooks", consume]]);
