// What each connector tool takes, shared by the MCP tools (tools.ts) and the web API (api.ts), so the two can't drift
// apart: one schema per question, with the same limits. openapi.ts describes the web API from these too.
import { z } from "zod";
import { MAX_COLUMNS, MAX_FACTS, TYPES } from "../apps/relay/memory.ts";
import { MAX_POINTS } from "../apps/relay/points.ts";
import { HEALTH_TYPES } from "../apps/relay/queries.ts";
import { accuracy, latitude, longitude, placeName } from "../apps/relay/store.ts";
import { knownZone, ZONE } from "./time.ts";

export const MAX_BUCKETS = 400;
export const LINES = 3;
export const PART = 200;
export const POINTS_DAYS = 7;

const zone = z.string().refine(knownZone, "Not a time zone.").optional()
  .describe(`An IANA time zone, such as Europe/London, for days and the times in the answer; ${ZONE} when left out.`);
const when = (what: string) => z.string().max(40)
  .describe(`${what}: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset.`);
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(text => !Number.isNaN(Date.parse(text)), "Not a day.")
  .describe("The day, as YYYY-MM-DD.");
const cursor = z.string().max(100).optional().describe("The last answer's `nextCursor`, to read the next page.");
const query = z.string().trim().min(1).max(200).describe("The words to find.");
const tag = z.string().trim().min(1).max(81)
  .describe("A topic, such as battery or bike/charging: it finds its parts too, so bike finds bike/charging.");
const tags = z.array(z.string().max(81)).max(10);
const factId = z.string().regex(/^f[a-z2-7]{4,6}$/, "Not a fact id.").describe("The fact's id, such as fk3x9.");
const tagChange = { add: tags.default([]).describe("Topics to add."), remove: tags.default([]).describe("Topics to remove.") };

/** Each tool's name, title, words for the AI, and input. A tool that adds is the only one not read-only. */
export const TOOLS = {
  search: {
    title: "Search notes",
    description: "Find notes whose text holds every word of the query, in any case, or that carry a topic, newest first, with each " +
      "note's time and place. Give `query`, `tag` or both.",
    input: { query: query.optional(), tag: tag.optional(), from: when("Only notes from this time").optional(), to: when("Only notes before this time").optional(),
      source: z.enum(["ring", "typed"]).optional().describe("Only older recorded notes, or only typed ones."),
      limit: z.number().int().min(1).max(50).default(20).describe("How many notes, at most 50."), cursor, timezone: zone },
  },
  fetch: {
    title: "Read one note",
    description: "Read one note by its id, with the places you stayed within 30 minutes of it and the health totals of its day.",
    input: { id: z.string().max(64).describe("The note's id, from search or timeline."), timezone: zone },
  },
  timeline: {
    title: "Read notes in a time range",
    description: "Read every note from one time to another, newest first, a page at a time, with each note's time and place.",
    input: { from: when("The first time"), to: when("The time to stop before"),
      limit: z.number().int().min(1).max(100).default(50).describe("How many notes, at most 100."), cursor, timezone: zone },
  },
  day_summary: {
    title: "Sum up a day",
    description: "One day: how many notes, steps, sleep minutes, heart rate, workouts, the other health values it has, the nights " +
      "or naps that ended that day with their stage minutes, each workout with its kind, km and calories, each stay with its name and " +
      "times, each trip with its mode, km and minutes, and the calendar's events with the people in each. Each stay and trip from " +
      "the phone has an `id`: give it to points for its route.",
    input: { day, timezone: zone },
  },
  health: {
    title: "Read health over time",
    description: "One value per hour or day for one kind of health data: steps, sleep, mindful minutes and water (ml) as `total`; heart " +
      "rate and blood pressure (mmHg) as min, max and average; workouts as a count and minutes; weight (kg) as `latest`; resting heart " +
      "rate, heart rate variability (ms; hrv_sdnn from iPhone, hrv_rmssd from Android) as `average`; blood oxygen (%) as min and average; " +
      "cycle flow as the highest `flow`, 0 none to 3 heavy. Sleep counts on the day it ends.",
    input: { type: z.enum(HEALTH_TYPES).describe("Which health data."), from: when("The first time"),
      to: when("The time to stop before"), bucket: z.enum(["hour", "day"]).default("day").describe(`One value per hour or per day, at most ${MAX_BUCKETS}.`),
      timezone: zone },
  },
  nights: {
    title: "Read nights of sleep",
    description: "The nights, and naps, that end from one time to another, newest first: when the person went to bed, fell asleep and " +
      "woke, and the minutes asleep, in core (light), deep and REM sleep, and awake. Of nights that overlap, as from a watch and the " +
      "phone's bedtime, the one with the most sleep. Give `stages` to add each night's stage timeline, such as to see when deep sleep came.",
    input: { from: when("The first time"), to: when("The time to stop before"),
      stages: z.boolean().default(false).describe("Add each night's stage timeline, in time order."),
      limit: z.number().int().min(1).max(100).default(31).describe("How many nights, at most 100."), cursor, timezone: zone },
  },
  workouts: {
    title: "Read workouts",
    description: "The workouts that start from one time to another, newest first, each with its kind (such as running or " +
      "traditional_strength_training), minutes, km and calories when the phone has them. A workout from before the phone sent its " +
      "kind has `kind` null. Calories are active calories from an iPhone and total calories from Android.",
    input: { from: when("The first time"), to: when("The time to stop before"),
      limit: z.number().int().min(1).max(100).default(50).describe("How many workouts, at most 100."), cursor, timezone: zone },
  },
  places: {
    title: "Read places visited",
    description: "The stays and trips from one time to another, oldest first: each stay's name, street, where it is, and when you " +
      "arrived and left; each trip's mode (walking, running, cycling, driving, flying or unknown), km, minutes, and the stays it went between. " +
      "Each stay and trip from the phone has an `id`: give it to points for its route.",
    input: { from: when("The first time"), to: when("The time to stop before"),
      limit: z.number().int().min(1).max(200).default(100).describe("How many stays, at most 200. Read on from `next`."), timezone: zone },
  },
  points: {
    title: "Read location points",
    description: "The location points of one stay or trip, by its `id` from places or day_summary, from the phone that made it; or " +
      `every phone's points from \`from\` to \`to\`, at most ${POINTS_DAYS} days. Each point has its time, lat, lon, accuracy (m) and ` +
      `street. Oldest first, at most ${MAX_POINTS}, spread evenly with the first and the last; \`total\` says how many there were. ` +
      "No points means the person keeps only stays and trips, or the phone sent none: do not ask again.",
    input: { id: z.number().int().positive().optional().describe("The id of a stay or trip, from places or day_summary."),
      from: when("The first time").optional(), to: when("The time to stop before").optional(), timezone: zone },
  },
  calendar: {
    title: "Read calendar events",
    description: "The events from the phone's calendars that overlap one time to another, with each one's calendar, title, time, place, " +
      "notes and people. With `query`, only events whose title, place, notes or people hold every word, newest first; without, in start order.",
    input: { from: when("The first time"), to: when("The time to stop before"), query: query.optional(),
      limit: z.number().int().min(1).max(100).default(50).describe("How many events, at most 100."), cursor, timezone: zone },
  },
  search_chats: {
    title: "Search saved chats",
    description: "Find saved AI chats from Claude Code and Codex whose messages or AI summaries hold every word of the query, newest first, with up to " +
      `${LINES} matching lines each.`,
    input: { query, from: when("Only chats active from this time").optional(), to: when("Only chats last active before this time").optional(),
      limit: z.number().int().min(1).max(20).default(10).describe("How many chats, at most 20."), cursor, timezone: zone },
  },
  read_chat: {
    title: "Read one saved chat",
    description: `Read one saved chat by its id: the AI's saved summaries, then its messages in order, ${PART} at a time. Each message ` +
      "is yours (`you`), the AI's (`ai`), or one line for a step the AI took (`step`).",
    input: { id: z.string().max(64).describe("The chat's id, from search_chats."), cursor: z.string().max(20).optional()
      .describe("The last answer's `nextCursor`, to read the next part."), timezone: zone },
  },
  photos: {
    title: "List photos",
    description: "List the photos the phone sent from one time to another, newest first, with when and where each was taken and its size. " +
      "Give `near` to keep only photos taken within some kilometres of a point, such as one from `places`. Look at one with read_photo.",
    input: { from: when("The first time"), to: when("The time to stop before"),
      near: z.strictObject({ lat: latitude, lon: longitude, km: z.number().positive().max(500).describe("How far from the point, at most 500 km.") })
        .optional().describe("Only photos taken near this point."),
      limit: z.number().int().min(1).max(50).default(50).describe("How many photos, at most 50."), cursor, timezone: zone },
  },
  read_photo: {
    title: "Look at one photo",
    description: "Look at one photo by its id, from `photos`: the photo itself, at most 1,600 pixels on its long side, and when and where it was taken.",
    input: { id: z.string().max(64).describe("The photo's id, from photos."), timezone: zone },
  },
  memory: {
    title: "Search the memory",
    description: "Search the person's memory: short facts, decisions, preferences, plans and open questions their AIs kept, newest first. " +
      "Look here first for what the person decided, likes or plans. Words search the text columns; `tag` a topic and its parts; `source` the " +
      "record a fact came from, such as relay:chat/<id>; `where` a value of any column. Only live facts, unless `all`: a replaced fact " +
      "names the fact that replaced it in `replacedBy`. The answer lists the memory's columns.",
    input: { query: query.optional(), tag: tag.optional(),
      source: z.string().max(100).optional().describe("A record's link, such as relay:chat/<id> or relay:note/<id>: it finds its messages too."),
      from: when("Only facts added from this time").optional(), to: when("Only facts added before this time").optional(),
      all: z.boolean().default(false).describe("Add the facts that were replaced."),
      where: z.record(z.string().max(30), z.union([z.string().max(400), z.number(), z.boolean()])).optional()
        .describe("A value for each of the person's columns, such as { \"kind\": \"decision\" }. In the web API, send each as its own field."),
      limit: z.number().int().min(1).max(50).default(20).describe("How many facts, at most 50."), cursor, timezone: zone },
  },
  read_fact: {
    title: "Read one fact",
    description: "Read one fact of the memory by its id, with the facts it replaced and the fact that replaced it.",
    input: { id: factId, timezone: zone },
  },
  add_note: {
    title: "Add a note",
    description: "Add a typed note to the person's notes, with this app's name as its device. Only when the person asks to save something. " +
      "Send the same clientId again after a lost answer, and the note is stored once. It can't change or delete a note.",
    input: { clientId: z.string().regex(/^[A-Za-z0-9-]{8,64}$/)
      .describe("Your own id for this note, 8 to 64 letters, digits or dashes, such as a new UUID, so a resend is stored once."),
    text: z.string().min(1).max(20_000).describe("What the note says."), createdAt: when("When it was written; now when left out").optional(),
    lat: latitude.optional().describe("Where it was written: latitude. Send it with lon."),
    lon: longitude.optional().describe("Where it was written: longitude. Send it with lat."),
    accuracy: accuracy.optional().describe("How sure you are of the place, in meters."),
    place: placeName.optional().describe("The place's name, such as a street."), timezone: zone },
  },
} satisfies Record<string, { title: string; description: string; input: z.ZodRawShape }>;

const sqlValue = z.union([z.string(), z.number(), z.null()]);
const statement = { sql: z.string().min(1).describe("One SQLite command, such as CREATE TABLE, INSERT or SELECT."),
  params: z.array(sqlValue).max(100).default([]).describe("The values for its `?` marks, in order.") };

const column = z.string().max(30).describe("The column's name: a lower-case letter, then letters, digits or _.");
const note = z.string().max(200).describe("What the column holds, for the AIs that fill it.");

/** The web API's own questions, for a computer's key: the connector has no tool for them. */
export const WEB = {
  add_facts: {
    title: "Add facts",
    description: `Add up to ${MAX_FACTS} facts to the memory, all or none, as this computer. Each fact needs a tag, a source and every ` +
      "required column, and each value must fit its column's type. A fact can't be changed or deleted: name the facts it replaces " +
      "instead. Send the same `clientId` again after a lost answer, and the fact is stored once. Only a computer's key adds. 201 when any was added.",
    input: { facts: z.array(z.strictObject({
      clientId: z.string().regex(/^[A-Za-z0-9-]{8,64}$/).describe("Your own id for this fact, such as a new UUID, so a resend is stored once."),
      tags: tags.min(1).describe("The topics it is about, such as battery or bike/charging: at least one."),
      sources: z.array(z.string().max(100)).min(1).max(10).describe("The records it came from, such as relay:chat/<id>#<message>: at least one."),
      replaces: z.array(factId).max(10).optional().describe("The ids of the live facts this one replaces."),
      fields: z.record(z.string().max(30), z.unknown()).describe("A value for each of the memory's columns, such as kind and text."),
    })).min(1).max(MAX_FACTS).describe("The facts to add.") },
  },
  columns: {
    title: "Read the memory's columns",
    description: "The memory's live columns, each with its type, whether it is required, and its note; the removed ones; and, with " +
      "`changes`, each column change with its device and time.",
    input: { changes: z.boolean().default(false).describe("Add the last 100 column changes.") },
  },
  change_columns: {
    title: "Change the memory's columns",
    description: `Add, change and remove the memory's columns, all or none, at most ${MAX_COLUMNS} live. A column's type never ` +
      "changes; a removed column's values stay in the facts that have them. Only a computer's key changes columns.",
    input: {
      add: z.array(z.strictObject({ name: column, type: z.enum(TYPES).describe("text (up to 400 characters), number, date (YYYY-MM-DD), " +
        "yes_no (true or false), or words (up to 20 short words)."), required: z.boolean().default(false)
        .describe("Whether each new fact needs it."), note: note.optional() })).max(MAX_COLUMNS).default([]).describe("Columns to add."),
      change: z.array(z.strictObject({ name: column, required: z.boolean().optional(), note: note.optional() })).max(MAX_COLUMNS).default([])
        .describe("Columns whose note or `required` changes."),
      remove: z.array(column).max(MAX_COLUMNS).default([]).describe("Columns to remove."),
    },
  },
  tag_fact: {
    title: "Change a fact's topics",
    description: "Add and remove a fact's topics, as this computer: its words and sources stay as they are, and it keeps at least one topic.",
    input: { id: factId, ...tagChange },
  },
  tag_note: {
    title: "Change a note's topics",
    description: "Add and remove a note's topics, as this computer: the note's words stay as the person wrote them.",
    input: { id: z.string().max(64).describe("The note's id."), ...tagChange },
  },
  db: {
    title: "Run commands in the agents' database",
    description: "Run SQLite commands in the person's agents' database, as this computer: a database only their computers' agents " +
      "use, where any table can be made. Relay Everything's own tables are not in it. Send `sql`, or `batch` for up to 50 commands " +
      "in one step, all or none. A command is at most 100 KB, an answer at most 5,000 rows and 5 MB, and the database at most 1 GB. " +
      "A blob reads as `{ \"base64\": … }`. Only a computer's key runs commands.",
    input: { sql: statement.sql.optional(), params: statement.params.optional(),
      batch: z.array(z.strictObject(statement)).min(1).optional().describe("Several commands, run in order in one step: all or none.") },
  },
  db_tables: {
    title: "List the agents' database's tables",
    description: "Each table in the person's agents' database, with its columns and how many rows it holds. Only a computer's key reads it.",
    input: {},
  },
  knowledge_access: {
    title: "Open the knowledge web",
    description: "A pass to the person's knowledge web, a git repository of topic pages, for at most one hour: its git address, " +
      "the pass to send as `Authorization: Bearer`, and when it ends. The first ask makes the web. Only a computer's key gets one.",
    input: {},
  },
} satisfies Record<string, { title: string; description: string; input: z.ZodRawShape }>;

export type ToolName = keyof typeof TOOLS;
export type WebName = keyof typeof WEB;
export const INPUTS = { ...TOOLS, ...WEB };
/** A question's input once parsed: defaults filled in. */
export type Input<Name extends ToolName | WebName> = z.output<z.ZodObject<(typeof INPUTS)[Name]["input"]>>;
