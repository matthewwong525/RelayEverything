// Each connector question's answer, shared by the MCP tools and the web API so one input answers the same through
// either. Reads are capped; a note is added only through add-note.ts. No answer holds a key or a device's id.
import { addNote, type TypedNote } from "../apps/relay/add-note.ts";
import { chatById, chatLines, chatMessages, chatPage, daySummary, healthBuckets, noteById, notePage, placeVisits, type Chat, type HealthType,
  type Note, type Span } from "../apps/relay/queries.ts";
import type { Db, PersonSpace } from "../apps/relay/space.ts";
import type { McpEnv } from "./env.ts";
import { LINES, MAX_BUCKETS, PART, type Input, type ToolName } from "./inputs.ts";
import { dayOf, HOUR, instant, local, nextDay, startOfDay, ZONE } from "./time.ts";

const NEAR = HOUR / 2;
const LINE_CHARACTERS = 300;
export const RECONNECT = "Connect this app to Relay Everything again to let it add notes. Its reads still work.";

/** A question the caller can fix: the tool answers it as an error the AI reads, the web API with this status. */
export class Refusal extends Error {
  readonly status: 400 | 403 | 404;
  constructor(message: string, status: 400 | 403 | 404 = 400) {
    super(message);
    this.status = status;
  }
}

/** A range from the caller's text, refused unless both ends read as times and `from` comes first. */
function range(from: string, to: string, timezone: string): Span {
  const [start, end] = [instant(from, timezone), instant(to, timezone)];
  if (Number.isNaN(start) || Number.isNaN(end)) throw new Refusal("Give `from` and `to` as a day or an ISO time.");
  if (start >= end) throw new Refusal("`from` must come before `to`.");
  return [start, end];
}

/** A page's end as one cursor, or the page it names. */
const nextCursor = (page: { next: number | null; nextId: string | null }) => page.next === null ? null : `${page.next}.${page.nextId}`;
/** Where a page starts: the cursor's note, but never past the range's end, so a cursor from a wider range can't
 *  bring back a note after `to`. */
function pageBefore(text: string | undefined, end: number): { before: number; beforeId?: string } {
  if (text === undefined) return { before: end };
  const [, before, beforeId] = /^(\d{13})\.([0-9a-f-]{36})$/.exec(text) ?? [];
  if (!before) throw new Refusal("That cursor is not one this connector gave.");
  return Number(before) < end ? { before: Number(before), beforeId } : { before: end };
}

/** A note as the caller reads it: a title, as ChatGPT's search looks for, and the time in the zone. */
const shown = (note: Note, timezone: string) =>
  ({ ...note, title: note.text.slice(0, 80) || "A ring note with no words", recordedAt: local(note.recordedAt, timezone) });

async function notes(db: Db, page: Parameters<typeof notePage>[1], timezone: string) {
  const found = await notePage(db, page);
  return { notes: found.notes.map(note => shown(note, timezone)), nextCursor: nextCursor(found) };
}

/** Whole days, or hours, covering the range, refused past MAX_BUCKETS. */
function buckets(from: number, to: number, size: "hour" | "day", timezone: string): Span[] {
  const spans: Span[] = [];
  let date = dayOf(from, timezone);
  for (let start = size === "day" ? startOfDay(date, timezone) : Math.floor(from / HOUR) * HOUR; start < to && spans.length <= MAX_BUCKETS;) {
    const end = size === "day" ? startOfDay(date = nextDay(date), timezone) : start + HOUR;
    spans.push([start, end]);
    start = end;
  }
  if (spans.length > MAX_BUCKETS) throw new Refusal(`That is more than ${MAX_BUCKETS} ${size}s: ask for a shorter range or a larger bucket.`);
  return spans;
}

async function summary(db: Db, date: string, timezone: string) {
  const { places, ...totals } = await daySummary(db, startOfDay(date, timezone), startOfDay(nextDay(date), timezone));
  return { day: date, timezone, ...totals, places: places.map(place => ({ ...place, from: local(place.from, timezone), to: local(place.to, timezone) })) };
}

async function visits(db: Db, from: number, to: number, limit: number, timezone: string) {
  const found = await placeVisits(db, from, to, limit);
  return { visits: found.visits.map(visit => ({ ...visit, arrived: local(visit.arrived, timezone), left: local(visit.left, timezone) })),
    next: found.next === null ? null : local(found.next, timezone) };
}

/** A chat as the caller reads it: its times in the zone. */
const chatShown = (chat: Chat, timezone: string) => ({ ...chat, startedAt: local(chat.startedAt, timezone), lastAt: local(chat.lastAt, timezone) });

/** A message cut to LINE_CHARACTERS around its first matching word. */
function line(text: string, words: string[]): string {
  const lower = text.toLowerCase();
  const at = Math.min(...words.map(word => lower.indexOf(word.toLowerCase())).filter(index => index >= 0));
  const start = Math.max(0, Math.min(at - 60, text.length - LINE_CHARACTERS));
  return `${start ? "…" : ""}${text.slice(start, start + LINE_CHARACTERS)}${start + LINE_CHARACTERS < text.length ? "…" : ""}`;
}

async function chatsFound(db: Db, words: string[], page: Parameters<typeof chatPage>[1], timezone: string) {
  const found = await chatPage(db, { ...page, words });
  const chats = await Promise.all(found.chats.map(async chat => ({ ...chatShown(chat, timezone),
    lines: (await chatLines(db, chat.id, words, LINES)).map(({ role, text }) => ({ role, text: line(text, words) })) })));
  return { chats, nextCursor: nextCursor(found) };
}

/** Where a chat's next part starts: the last answer's cursor, a message's place in the chat. */
function partAfter(text: string | undefined): number {
  if (text === undefined) return -1;
  if (!/^\d{1,8}$/.test(text)) throw new Refusal("That cursor is not one this connector gave.");
  return Number(text);
}

/** Who adds a note: an API key's own device, or a connected app's, made on its first note. Null for an app connected
 *  before the consent page said it can add. */
type Adder = { deviceId: string; name: string; kind: "api" | "app" } | null;

/** The caller's own space and what it may do: every caller reads; `adder` says whether and as whom it adds. */
export type Asker = { space: PersonSpace; adder: Adder; env: Pick<McpEnv, "RELAY_WEBHOOKS"> };

const READS = {
  search: async (db, { query, from = "2001-01-01", to = "2286-01-01", source, limit, cursor: text, timezone = ZONE }) => {
    const [after, end] = range(from, to, timezone);
    return notes(db, { after, source, words: query.split(/\s+/).slice(0, 10), limit, ...pageBefore(text, end) }, timezone);
  },
  fetch: async (db, { id, timezone = ZONE }) => {
    const note = await noteById(db, id);
    if (!note) throw new Refusal("No note has this id.", 404);
    const [nearby, { day: date, steps, sleepMinutes, heartRate, workouts }] = await Promise.all([
      visits(db, note.recordedAt - NEAR, note.recordedAt + NEAR, 20, timezone), summary(db, dayOf(note.recordedAt, timezone), timezone)]);
    return { ...shown(note, timezone), placesNearby: nearby.visits, day: { day: date, steps, sleepMinutes, heartRate, workouts } };
  },
  timeline: async (db, { from, to, limit, cursor: text, timezone = ZONE }) => {
    const [after, end] = range(from, to, timezone);
    return notes(db, { after, limit, ...pageBefore(text, end) }, timezone);
  },
  day_summary: async (db, { day: date, timezone = ZONE }) => summary(db, date, timezone),
  health: async (db, { type, from, to, bucket, timezone = ZONE }) => {
    const values = await healthBuckets(db, type as HealthType, buckets(...range(from, to, timezone), bucket, timezone));
    return { type, bucket, timezone, values: values.map(value => ({ ...value, from: local(value.from, timezone), to: local(value.to, timezone) })) };
  },
  places: async (db, { from, to, limit, timezone = ZONE }) => visits(db, ...range(from, to, timezone), limit, timezone),
  search_chats: async (db, { query, from = "2001-01-01", to = "2286-01-01", limit, cursor: text, timezone = ZONE }) => {
    const [after, end] = range(from, to, timezone);
    return chatsFound(db, query.split(/\s+/).slice(0, 10), { after, limit, ...pageBefore(text, end) }, timezone);
  },
  read_chat: async (db, { id, cursor: text, timezone = ZONE }) => {
    const chat = await chatById(db, id);
    if (!chat) throw new Refusal("No chat has this id.", 404);
    const { messages, next } = await chatMessages(db, id, partAfter(text), PART);
    return { ...chatShown(chat, timezone), saves: chat.saves.map(save => ({ ...save, createdAt: local(save.createdAt, timezone) })),
      messages: messages.map(message => ({ ...message, at: local(message.at, timezone) })), nextCursor: next === null ? null : String(next) };
  },
} satisfies { [Name in Exclude<ToolName, "add_note">]: (db: Db, input: Input<Name>) => Promise<unknown> };

/** A connected app's device row: its notes name the app, and a disconnect turns it off. */
export const APP_DEVICE = "INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches) " +
  "VALUES (?, ?, ?, '', ?, NULL, 'app') ON CONFLICT DO NOTHING";

/** Adds a typed note as the caller's own device: an app's row is made on its first note, with the app's name. */
async function add({ space, adder, env }: Asker, { timezone = ZONE, createdAt, ...note }: Input<"add_note">) {
  if (!adder) throw new Refusal(RECONNECT, 403);
  if ((note.lat === undefined) !== (note.lon === undefined)) throw new Refusal("Send lat and lon together.");
  const at = createdAt === undefined ? Date.now() : instant(createdAt, timezone);
  if (Number.isNaN(at)) throw new Refusal("Give `createdAt` as a day or an ISO time.");
  if (adder.kind === "app") {
    await space.db.prepare(APP_DEVICE).bind(adder.deviceId, adder.name, `app:${adder.deviceId}`, Date.now()).run();
  }
  return addNote(env, space, adder.deviceId, { ...note, createdAt: at } satisfies TypedNote);
}

/** The answer to one question, for the caller's own space. */
export function answer<Name extends ToolName>(name: Name, asker: Asker, input: Input<Name>): Promise<unknown> {
  if (name === "add_note") return add(asker, input as Input<"add_note">);
  const read = READS[name as Exclude<ToolName, "add_note">] as (db: Db, input: unknown) => Promise<unknown>;
  return read(asker.space.db, input);
}
