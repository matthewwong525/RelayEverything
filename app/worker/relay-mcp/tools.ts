// The connector's eight tools, all read-only, over one person's notes, health, places and chats. Each answer is
// capped, and none holds a recording's key, a device's id or a chat's session id. Every read goes through queries.ts.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { z } from "zod";
import { chatById, chatLines, chatMessages, chatPage, daySummary, healthBuckets, noteById, notePage, placeVisits, type Chat, type HealthType,
  type Note, type Span } from "../apps/relay/queries.ts";
import { spaceOf, vouch, type Db, type SpaceEnv } from "../apps/relay/space.ts";
import type { GrantProps, McpEnv } from "./env.ts";
import { dayOf, HOUR, instant, knownZone, local, nextDay, startOfDay, ZONE } from "./time.ts";

const MAX_BUCKETS = 400;
const NEAR = HOUR / 2;

const zone = z.string().refine(knownZone, "Not a time zone.").optional()
  .describe(`An IANA time zone, such as Europe/London, for days and the times in the answer; ${ZONE} when left out.`);
const when = (what: string) => z.string().max(40)
  .describe(`${what}: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset.`);
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(text => !Number.isNaN(Date.parse(text)), "Not a day.")
  .describe("The day, as YYYY-MM-DD.");
const cursor = z.string().max(100).optional().describe("The last answer's `nextCursor`, to read the next page.");

class Refusal extends Error {}
type Answer = { content: { type: "text"; text: string }[]; isError?: boolean };

/** Runs a tool, and answers a refusal as a tool error the AI can read and correct. */
const tool = <Input>(run: (input: Input) => Promise<unknown>) => async (input: Input): Promise<Answer> => {
  try {
    return { content: [{ type: "text", text: JSON.stringify(await run(input)) }] };
  } catch (error) {
    if (!(error instanceof Refusal)) throw error;
    return { content: [{ type: "text", text: error.message }], isError: true };
  }
};

/** A range from the AI's text, refused unless both ends read as times and `from` comes first. */
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

/** A note as the AI reads it: a title, as ChatGPT's search looks for, and the time in the zone. */
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

const LINES = 3;
const LINE_CHARACTERS = 300;
const PART = 200;

/** A chat as the AI reads it: its times in the zone. */
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

const readOnly = { readOnlyHint: true, destructiveHint: false, openWorldHint: false };

/** A fresh server per request: the connector keeps no session between calls. */
function relayServer(db: Db): McpServer {
  const server = new McpServer({ name: "relay", title: "Relay Everything", version: "1.0.0" }, {
    instructions: "Relay Everything holds one person's notes from a smart ring and their phone, with health and places, and the Claude Code chats " +
      "they saved. Every tool only reads. " +
      `Days and times are ${ZONE} unless you pass a timezone.`,
  });
  server.registerTool("search", {
    title: "Search notes", annotations: readOnly,
    description: "Find notes whose text holds every word of the query, in any case, newest first, with each note's time and place.",
    inputSchema: { query: z.string().trim().min(1).max(200).describe("The words to find."), from: when("Only notes from this time").optional(),
      to: when("Only notes before this time").optional(), source: z.enum(["ring", "typed"]).optional().describe("Only ring notes, or only typed ones."),
      limit: z.number().int().min(1).max(50).default(20).describe("How many notes, at most 50."), cursor, timezone: zone },
  }, tool(async ({ query, from = "2001-01-01", to = "2286-01-01", source, limit, cursor: text, timezone = ZONE }) => {
    const [after, end] = range(from, to, timezone);
    return notes(db, { after, source, words: query.split(/\s+/).slice(0, 10), limit, ...pageBefore(text, end) }, timezone);
  }));
  server.registerTool("fetch", {
    title: "Read one note", annotations: readOnly,
    description: "Read one note by its id, with the places visited within 30 minutes of it and the health totals of its day.",
    inputSchema: { id: z.string().max(64).describe("The note's id, from search or timeline."), timezone: zone },
  }, tool(async ({ id, timezone = ZONE }) => {
    const note = await noteById(db, id);
    if (!note) throw new Refusal("No note has this id.");
    const [nearby, { day: date, steps, sleepMinutes, heartRate, workouts }] = await Promise.all([
      visits(db, note.recordedAt - NEAR, note.recordedAt + NEAR, 20, timezone), summary(db, dayOf(note.recordedAt, timezone), timezone)]);
    return { ...shown(note, timezone), placesNearby: nearby.visits, day: { day: date, steps, sleepMinutes, heartRate, workouts } };
  }));
  server.registerTool("timeline", {
    title: "Read notes in a time range", annotations: readOnly,
    description: "Read every note from one time to another, newest first, a page at a time, with each note's time and place.",
    inputSchema: { from: when("The first time"), to: when("The time to stop before"),
      limit: z.number().int().min(1).max(100).default(50).describe("How many notes, at most 100."), cursor, timezone: zone },
  }, tool(async ({ from, to, limit, cursor: text, timezone = ZONE }) => {
    const [after, end] = range(from, to, timezone);
    return notes(db, { after, limit, ...pageBefore(text, end) }, timezone);
  }));
  server.registerTool("day_summary", {
    title: "Sum up a day", annotations: readOnly,
    description: "One day: how many notes, steps, sleep minutes, heart rate, workouts, and each place visited.",
    inputSchema: { day, timezone: zone },
  }, tool(async ({ day: date, timezone = ZONE }) => summary(db, date, timezone)));
  server.registerTool("health", {
    title: "Read health over time", annotations: readOnly,
    description: "One value per hour or day for one kind of health data: steps and sleep minutes as `total`, heart rate as min, max " +
      "and average, workouts as a count and minutes. Sleep counts on the day it ends.",
    inputSchema: { type: z.enum(["steps", "heart_rate", "sleep", "workout"]).describe("Which health data."), from: when("The first time"),
      to: when("The time to stop before"), bucket: z.enum(["hour", "day"]).default("day").describe(`One value per hour or per day, at most ${MAX_BUCKETS}.`),
      timezone: zone },
  }, tool(async ({ type, from, to, bucket, timezone = ZONE }) => {
    const values = await healthBuckets(db, type as HealthType, buckets(...range(from, to, timezone), bucket, timezone));
    return { type, bucket, timezone, values: values.map(value => ({ ...value, from: local(value.from, timezone), to: local(value.to, timezone) })) };
  }));
  server.registerTool("places", {
    title: "Read places visited", annotations: readOnly,
    description: "The places visited from one time to another, oldest first: each place's name, where it is, and when you arrived and left.",
    inputSchema: { from: when("The first time"), to: when("The time to stop before"),
      limit: z.number().int().min(1).max(200).default(100).describe("How many visits, at most 200. Read on from `next`."), timezone: zone },
  }, tool(async ({ from, to, limit, timezone = ZONE }) => visits(db, ...range(from, to, timezone), limit, timezone)));
  server.registerTool("search_chats", {
    title: "Search saved chats", annotations: readOnly,
    description: "Find saved Claude Code chats whose messages or AI summaries hold every word of the query, newest first, with up to " +
      `${LINES} matching lines each.`,
    inputSchema: { query: z.string().trim().min(1).max(200).describe("The words to find."), from: when("Only chats active from this time").optional(),
      to: when("Only chats last active before this time").optional(),
      limit: z.number().int().min(1).max(20).default(10).describe("How many chats, at most 20."), cursor, timezone: zone },
  }, tool(async ({ query, from = "2001-01-01", to = "2286-01-01", limit, cursor: text, timezone = ZONE }) => {
    const [after, end] = range(from, to, timezone);
    return chatsFound(db, query.split(/\s+/).slice(0, 10), { after, limit, ...pageBefore(text, end) }, timezone);
  }));
  server.registerTool("read_chat", {
    title: "Read one saved chat", annotations: readOnly,
    description: `Read one saved chat by its id: the AI's saved summaries, then its messages in order, ${PART} at a time. Each message ` +
      "is yours (`you`), the AI's (`ai`), or one line for a step the AI took (`step`).",
    inputSchema: { id: z.string().max(64).describe("The chat's id, from search_chats."), cursor: z.string().max(20).optional()
      .describe("The last answer's `nextCursor`, to read the next part."), timezone: zone },
  }, tool(async ({ id, cursor: text, timezone = ZONE }) => {
    const chat = await chatById(db, id);
    if (!chat) throw new Refusal("No chat has this id.");
    const { messages, next } = await chatMessages(db, id, partAfter(text), PART);
    return { ...chatShown(chat, timezone), saves: chat.saves.map(save => ({ ...save, createdAt: local(save.createdAt, timezone) })),
      messages: messages.map(message => ({ ...message, at: local(message.at, timezone) })), nextCursor: next === null ? null : String(next) };
  }));
  return server;
}

/** The connector's /mcp: Streamable HTTP, answered as JSON, with no session. Each token reads only its grant's person's
 *  space; a grant from before spaces names no person, so its app must connect again. */
export const mcpHandler = {
  async fetch(request: Request, env: Pick<McpEnv, "SPACES">, ctx: Pick<ExecutionContext, "props">): Promise<Response> {
    const personId = (ctx.props as GrantProps | undefined)?.personId;
    if (!personId) return Response.json({ error: "invalid_token", error_description: "Connect this AI app again." }, { status: 401 });
    // The tools read no recording, so the connector binds no file store.
    const space = spaceOf({ SPACES: env.SPACES } as SpaceEnv, vouch("grant", personId));
    const transport = new WebStandardStreamableHTTPServerTransport({ enableJsonResponse: true });
    await relayServer(space.db).connect(transport);
    return transport.handleRequest(request);
  },
};
