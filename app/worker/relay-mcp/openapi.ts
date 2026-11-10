// The web API's OpenAPI 3.1 document, made from the tools' inputs, the routes and the answers here, so it can't go
// stale. /v1/openapi.json serves it; `npm run relay:api-doc` writes the website's copy and reference page.
import { z } from "zod";
import { TYPES } from "../apps/relay/memory.ts";
import { CODES, ROUTES, type V1Route, type WebTool } from "./api.ts";
import { INPUTS } from "./inputs.ts";

const at = z.string().describe("A time in the asked zone, with its offset: 2026-11-04T09:01:00-05:00.");
const nextCursor = z.string().nullable().describe("Send it as `cursor` to read the next page; null on the last one.");
const note = z.strictObject({
  id: z.string(), title: z.string().describe("The first 80 characters of the text."), source: z.enum(["ring", "typed"]), text: z.string(),
  recordedAt: at, device: z.string().describe("The name of the device that sent it."), audio: z.boolean().describe("Whether it has a recording."),
  place: z.strictObject({ lat: z.number(), lon: z.number(), accuracy: z.number().nullable(), name: z.string().nullable(),
    from: z.enum(["phone", "history"]).describe("phone: the phone's place at the time; history: matched from the location history.") }).nullable(),
  attachments: z.array(z.strictObject({ id: z.string(), name: z.string(), type: z.string(), size: z.number().describe("In bytes."),
    ready: z.boolean().describe("Whether the file's bytes have arrived.") })).describe("The note's files: names, types and sizes, never the bytes."),
});
const stayId = z.number().int().describe("The stay's or trip's id: give it to `GET /v1/points` for its points.");
const visit = z.strictObject({ id: stayId.optional(), name: z.string().describe("The best name the phone found: a calendar event's place, a place on the map, the street, or the coordinates."),
  lat: z.number(), lon: z.number(), arrived: at, left: at, minutes: z.number(),
  address: z.string().optional().describe("The street, when the name came from the calendar or the map."),
  event: z.string().optional().describe("The calendar event that named the stay."),
  ongoing: z.literal(true).optional().describe("You are still there.") }).describe("A stay: a time in one place.");
const trip = z.strictObject({ id: stayId, left: at, arrived: at, mode: z.string().describe("walking, running, cycling, driving, flying or unknown."),
  km: z.number(), minutes: z.number(), from: z.string().nullable().describe("The name of the stay it left."),
  to: z.string().nullable().describe("The name of the stay it reached.") }).describe("A trip between two stays.");
const totals = { steps: z.number(), sleepMinutes: z.number(), heartRate: z.strictObject({ min: z.number(), max: z.number(), average: z.number() }).nullable(),
  workouts: z.strictObject({ count: z.number(), minutes: z.number() }) };
const minutes = z.strictObject({ asleep: z.number().describe("Asleep in any stage."), core: z.number().describe("Core, or light, sleep."),
  deep: z.number(), rem: z.number(), awake: z.number().describe("Awake in the night.") }).describe("Minutes in each stage.");
const night = z.strictObject({ start: at.describe("The first reading, such as going to bed."), end: at.describe("The last reading."),
  asleepAt: at.nullable().describe("When the person fell asleep; null for a night with only a bedtime."),
  wokeAt: at.nullable().describe("When the person last woke; null for a night with only a bedtime."), minutes,
  source: z.string().describe("The app or watch that tracked it."), device: z.string().describe("The name of the phone that sent it.") })
  .describe("A night or a nap.");
const step = z.strictObject({ stage: z.string().describe("asleep (no stage known), core, deep, rem or awake."), start: at, end: at });
const workout = z.strictObject({ kind: z.string().nullable().describe("Such as running or traditional_strength_training; null for a workout from before the phone sent it."),
  start: at, end: at, minutes: z.number(), km: z.number().nullable(),
  calories: z.number().nullable().describe("In kcal: active calories from an iPhone, total calories from Android."),
  source: z.string().describe("The app or watch that recorded it."), device: z.string().describe("The name of the phone that sent it.") });
/** The day's other health values: each is there only when the day has some. */
const more = { weightKg: z.number().optional().describe("The latest weight, in kg."), restingHeartRate: z.number().optional(),
  hrvSdnn: z.number().optional().describe("Heart rate variability from iPhone, in ms."),
  hrvRmssd: z.number().optional().describe("Heart rate variability from Android, in ms."),
  bloodOxygen: z.strictObject({ min: z.number(), average: z.number() }).optional().describe("In %."),
  bloodPressure: z.array(z.strictObject({ at, upper: z.number(), lower: z.number() })).optional().describe("Each reading, in mmHg, up to 20."),
  cycleFlow: z.number().optional().describe("The day's highest flow: 0 none, 1 light, 2 medium, 3 heavy."),
  mindfulMinutes: z.number().optional(), waterMl: z.number().optional() };
const person = z.strictObject({ name: z.string().optional(), email: z.string().optional(), organizer: z.boolean().optional() });
const event = z.strictObject({ id: z.string(), title: z.string(), calendar: z.string().describe("The calendar's name."), start: at, end: at,
  allDay: z.boolean(), location: z.string().nullable(), notes: z.string().nullable(), url: z.string().nullable(), people: z.array(person),
  device: z.string().describe("The name of the phone that sent it.") });
const chat = { id: z.string(), title: z.string(), project: z.string().describe("The project's folder name."), app: z.enum(["claude-code", "codex"]).describe("The app the chat came from."),
  startedAt: at, lastAt: at, messages: z.number(), savedByAi: z.boolean() };
const role = z.enum(["you", "ai", "step"]);
const photo = z.strictObject({ id: z.string(), takenAt: at, lat: z.number().nullable(), lon: z.number().nullable(), width: z.number(), height: z.number() });
const fact = z.strictObject({ id: z.string().describe("The fact's id, such as fk3x9."),
  fields: z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.array(z.string())]))
    .describe("The fact's value for each column, such as kind and text; a removed column's value stays."),
  tags: z.array(z.string()).describe("The topics it is about."), sources: z.array(z.string()).describe("The records it came from, as relay: links."),
  replaces: z.array(z.string()).describe("The ids of the facts it replaced."),
  replacedBy: z.string().nullable().describe("The id of the fact that replaced it; null for a live fact."),
  device: z.string().describe("The name of the computer that added it."), createdAt: at });
const column = z.strictObject({ name: z.string(), type: z.enum(TYPES), required: z.boolean().describe("Whether each new fact needs it."),
  note: z.string().describe("What it holds, for the AIs that fill it.") });
const columns = { columns: z.array(column).describe("The live columns."),
  removed: z.array(z.strictObject({ name: z.string(), type: z.enum(TYPES), removedAt: z.number().describe("Unix time in milliseconds.") }))
    .describe("The removed columns: a name comes back only with its old type.") };
const topics = z.strictObject({ id: z.string(), tags: z.array(z.string()).describe("Its topics now.") });

/** What each tool answers, and `me`: api.test.ts checks every answer against these. */
export const ANSWERS = {
  search: z.strictObject({ notes: z.array(note), nextCursor }),
  timeline: z.strictObject({ notes: z.array(note), nextCursor }),
  fetch: note.extend({ placesNearby: z.array(visit), day: z.strictObject({ day: z.string(), ...totals }) }),
  day_summary: z.strictObject({ day: z.string(), timezone: z.string(), notes: z.number(), ...totals, ...more,
    nights: z.array(night).describe("The nights and naps that ended in the day, oldest first, without their timelines. Of nights that overlap, the one with the most sleep."),
    workouts: totals.workouts.extend({ items: z.array(workout).describe("The day's workouts, oldest first; one that two sources kept is given once.") }),
    places: z.array(z.strictObject({ id: stayId.optional(), name: z.string(), lat: z.number(), lon: z.number(), from: at, to: at, address: z.string().optional(),
      event: z.string().optional(), ongoing: z.literal(true).optional() }))
      .describe("One row per stay, in order. Points with no stay, as on a day before the phone made stays, give each place once."),
    trips: z.array(trip).describe("The trips between the day's stays, in order."),
    events: z.array(z.strictObject({ title: z.string(), start: at, end: at, allDay: z.boolean(), people: z.array(z.string()).describe("Their names.") }))
      .describe("The day's calendar events, in start order, up to 50.") }),
  health: z.strictObject({ type: z.string(), bucket: z.enum(["hour", "day"]), timezone: z.string(),
    values: z.array(z.object({ from: at, to: at }).catchall(z.number().nullable())
      .describe("Each type's own values, as the health tool says: such as `total` for steps, `min`, `max` and `average` for heart rate.")) }),
  places: z.strictObject({ visits: z.array(visit).describe("The stays, oldest first. Points with no stay or trip, as before the phone made stays, give each run of points at one place."),
    trips: z.array(trip).describe("The trips between the stays, before `next`."),
    next: at.nullable().describe("The first visit left out: read on from it.") }),
  nights: z.strictObject({ nights: z.array(night.extend({ stages: z.array(step).optional().describe("The stage timeline, in time order: only with `stages`.") })),
    nextCursor }),
  workouts: z.strictObject({ workouts: z.array(workout), nextCursor }),
  points: z.strictObject({ id: z.number().int().optional().describe("The stay's or trip's id, when asked by id."),
    kind: z.enum(["stay", "trip"]).optional(), from: at, to: at.describe("A stay or trip still going on reads to now."), timezone: z.string(),
    total: z.number().int().describe("How many points there were in all: more than `points` holds when they were thinned."),
    points: z.array(z.strictObject({ at, lat: z.number(), lon: z.number(), accuracy: z.number().describe("How sure the phone was, in meters."),
      place: z.string().optional().describe("The street, when the phone named one.") }))
      .describe("Oldest first, at most 500, spread evenly with the first and the last.") }),
  calendar: z.strictObject({ events: z.array(event), nextCursor }),
  search_chats: z.strictObject({ chats: z.array(z.strictObject({ ...chat, lines: z.array(z.strictObject({ role, text: z.string() })) })), nextCursor }),
  read_chat: z.strictObject({ ...chat, saves: z.array(z.strictObject({ id: z.string(), title: z.string(), text: z.string(), createdAt: at })),
    messages: z.array(z.strictObject({ seq: z.number(), role, text: z.string(), at })), nextCursor }),
  photos: z.strictObject({ photos: z.array(photo), nextCursor }),
  add_note: z.strictObject({ id: z.string().describe("The note's id."), added: z.boolean().describe("False when this clientId was added before.") }),
  memory: z.strictObject({ facts: z.array(fact), columns: columns.columns, nextCursor }),
  read_fact: fact.extend({ replacedFacts: z.array(fact).describe("The facts it replaced."),
    replacedByFact: fact.nullable().describe("The fact that replaced it.") }),
  add_facts: z.strictObject({ facts: z.array(z.strictObject({ clientId: z.string(), id: z.string().describe("The fact's id."),
    added: z.boolean().describe("False when this clientId was added before.") })) }),
  columns: z.strictObject({ ...columns, changes: z.array(z.strictObject({ name: z.string(), change: z.enum(["add", "change", "remove"]),
    column: z.strictObject({ name: z.string(), type: z.enum(TYPES), required: z.boolean().optional(), note: z.string().optional() })
      .describe("The column as the change left it."),
    device: z.string().describe("The name of the computer that changed it."), at: z.number().describe("Unix time in milliseconds.") }))
    .optional().describe("The last 100 changes, newest first: only with `changes`.") }),
  change_columns: z.strictObject(columns),
  tag_fact: topics,
  tag_note: topics,
  knowledge_access: z.strictObject({ remote: z.string().describe("The web's git address."),
    token: z.string().describe("The pass: send it to git as `Authorization: Bearer …`, never in the address or a file."),
    expiresAt: z.string().describe("When the pass ends, at most one hour on, as an ISO time.") }),
  me: z.strictObject({ device: z.string().describe("The key's device name, or the app's name."), adds: z.boolean().describe("Whether it may add notes.") }),
} satisfies Record<WebTool | "me", z.ZodType>;

type Json = Record<string, unknown>;
const json = (schema: z.ZodType, io: "input" | "output" = "output") => {
  const { $schema: _, ...rest } = z.toJSONSchema(schema, { io, unrepresentable: "throw" }) as Json;
  return rest;
};
const ERROR = { $ref: "#/components/schemas/Error" };
const refusal = (description: string) => ({ description, content: { "application/json": { schema: ERROR } } });

type Fields = { properties: Record<string, Json>; required?: string[] };
const inputOf = (name: WebTool) => json(z.object(INPUTS[name].input), "input") as Fields;
const inPath = (route: V1Route, key: string) => route.path.includes(`{${key}}`);

/** A route's query or path fields from its tools' inputs: `query` is sent as `q`. A field the tools share takes the
 *  last tool's limits, and is required only when every tool needs it. A POST's other fields are its body. */
function parameters(route: V1Route) {
  const inputs = route.tools.map(inputOf);
  const fields = new Map(inputs.flatMap(({ properties }) => Object.entries(properties)));
  return [...fields].filter(([key]) => route.method === "GET" || inPath(route, key)).map(([key, { description, ...schema }]) => {
    const where = inPath(route, key) ? "path" : "query";
    const required = where === "path" || inputs.every(input => input.required?.includes(key));
    // A record, as a memory column's value, is sent as one field for each key.
    const spread = schema.type === "object" ? { style: "form", explode: true } : {};
    return { name: key === "query" && route.q ? "q" : key, in: where, required, description, schema, ...spread };
  });
}

/** A POST's JSON body: its question's fields but those in the path; none when it takes no input. */
function requestBody(route: V1Route) {
  const { properties, required = [] } = inputOf(route.tools[0]);
  const own = Object.entries(properties).filter(([key]) => !inPath(route, key));
  if (!own.length) return {};
  const schema = { type: "object", additionalProperties: false, properties: Object.fromEntries(own),
    required: required.filter(key => !inPath(route, key)) };
  return { requestBody: { required: true, content: { "application/json": { schema } } } };
}

/** The answer schema of a route that runs `names`. Equal answers give one schema: two equal oneOf branches match
 *  every answer, so oneOf fails. */
export function answerSchema(names: readonly (keyof typeof ANSWERS)[]) {
  const answers = [...new Set(names.map(name => JSON.stringify(json(ANSWERS[name]))))].map(text => JSON.parse(text) as Json);
  return answers.length === 1 ? answers[0] : { oneOf: answers };
}

function operation(route: V1Route) {
  const schema = answerSchema(route.tools.length ? route.tools : ["me"]);
  const ok = { description: "The answer.", content: { "application/json": { schema } } };
  const path = parameters(route);
  return {
    operationId: route.id, summary: route.summary, description: route.description,
    ...route.method === "GET" || path.length ? { parameters: path } : {},
    ...route.method === "POST" && requestBody(route),
    responses: route.adds ? { 201: { ...ok, description: "Added." }, 200: { ...ok, description: "Added before: the same one." } } : { 200: ok },
    ...route.tools.includes("knowledge_access") && { more: { 501: refusal("The knowledge web is not set up on this server."),
      503: refusal("The knowledge web is still being made: try again in a minute.") } },
  };
}

const errors = {
  400: refusal("The input can't be read: `error_description` says which field."),
  401: refusal("No token, or one that is not valid: an expired token or a disconnected app."),
  403: refusal("This caller may not do it: an unknown key, a phone or chat key, a turned-off key, an app connected before it could add notes, " +
    "or a caller that is not a computer, for a change to the memory, a topic or the knowledge web."),
  404: refusal("No such note, fact, chat, stay, trip or route in the caller's own space."),
};

/** The whole document, for a server at `origin`. */
export function openApi(origin: string) {
  const paths: Record<string, Json> = {};
  for (const route of ROUTES) {
    const { responses, more, ...rest } = operation(route);
    paths[route.path] = { ...paths[route.path], [route.method.toLowerCase()]: { ...rest, responses: { ...responses, ...errors, ...more } } };
  }
  return {
    openapi: "3.1.0",
    info: { title: "Relay Everything API", version: "1.0.0",
      description: "Read one person's Relay Everything notes, health, sleep, workouts, places, calendar, saved chats and memory, and add notes. " +
        "A computer's key also adds facts, changes the memory's columns and the topics of facts and notes, and opens the knowledge web. " +
        "It deletes nothing. Each caller reaches only the space of the person who connected it or made its key." },
    servers: [{ url: origin }],
    security: [{ oauth2: [] }, { apiKey: [] }],
    paths,
    components: {
      securitySchemes: {
        oauth2: { type: "oauth2", description: "Connect an app with the person's own sign-in: register the app at `/register` (OAuth dynamic client " +
          "registration), then the authorization code flow with PKCE (S256). Leave out `resource`, or send this server's `/mcp` address: the " +
          "same token works on `/mcp` and here. An app connected before adding notes reads only; connect it again to add.",
        flows: { authorizationCode: { authorizationUrl: `${origin}/authorize`, tokenUrl: `${origin}/token`, refreshUrl: `${origin}/token`, scopes: {} } } },
        apiKey: { type: "http", scheme: "bearer", bearerFormat: "rek_…", description: "An API key, made on the person's Relay Everything page with " +
          "*Add an API key*, or a computer's key from the Relay Everything plugin: send it as `Authorization: Bearer rek_…`. A phone's or a chat " +
          "key is refused here." },
      },
      schemas: { Error: { type: "object", required: ["error", "error_description"], additionalProperties: false,
        properties: { error: { type: "string", enum: Object.values(CODES) },
          error_description: { type: "string", description: "What went wrong, in words to show a person." } } } },
    },
  };
}

type Operation = { operationId: string; summary: string; description: string; parameters?: { name: string; in: string; required: boolean;
  description?: string; schema: Json }[]; requestBody?: { content: { "application/json": { schema: { properties: Record<string, Json>; required?: string[] } } } } };

const cell = (text = "") => text.replaceAll("|", "\\|").replaceAll("\n", " ");
const typeOf = (schema: Json): string => schema.enum ? (schema.enum as unknown[]).map(value => JSON.stringify(value)).join(" or ") : String(schema.type);
const HEAD = "| Field | In | Type | Required | What it holds |\n|---|---|---|---|---|";

/** The website's reference page for the web API, made from the document. */
export function v1Reference(document = openApi("https://<your-relay-server>")): string {
  const sections = Object.entries(document.paths).flatMap(([path, methods]) => Object.entries(methods as Record<string, Operation>).map(([method, op]) => {
    const sent = op.requestBody?.content["application/json"].schema;
    const fields = [...(op.parameters ?? []).map(field => `| \`${field.name}\` | ${field.in} | ${cell(typeOf(field.schema))} | ${
      field.required ? "yes" : "no"} | ${cell(field.description)} |`),
    ...Object.entries(sent?.properties ?? {}).map(([name, field]) => `| \`${name}\` | body | ${
      cell(typeOf(field))} | ${sent!.required?.includes(name) ? "yes" : "no"} | ${cell(field.description as string)} |`)];
    return [`## ${op.summary}`, `\`${method.toUpperCase()} ${path}\` · \`${op.operationId}\``, op.description,
      fields.length ? `${HEAD}\n${fields.join("\n")}` : "It takes no input."].join("\n\n");
  }));
  return `---
title: Web API reference
description: Every route of the Relay Everything web API, with its fields, made from its OpenAPI file.
---

<!-- Made by \`npm run relay:api-doc\` in app/ from app/worker/relay-mcp/. Do not edit it by hand. -->

Each route sits under \`https://<your-relay-server>/v1/\`, on your AI connector's address. Send a connected app's token or an
API key as \`Authorization: Bearer …\`, as [Connect a service](../connect-a-service/) shows. The answers' fields are in the
[OpenAPI file](/api/v1.openapi.json). A refused call answers \`{ "error": "...", "error_description": "..." }\`.

${sections.join("\n\n")}
`;
}
