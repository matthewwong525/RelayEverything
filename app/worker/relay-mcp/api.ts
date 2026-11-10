// The web API under /v1/: the connector's tools as plain HTTP, each route parsing its tool's own input, so a route and
// its tool can't differ. It reads; it adds notes, and a computer's facts and topics. wiki/stack/relay-ai-connector.md
import { z } from "zod";
import { answer, Refusal, type Asker } from "./answers.ts";
import { INPUTS, TOOLS, WEB, type ToolName, type WebName } from "./inputs.ts";

/** One route: its tools, the path fields it fills, and whether `q` is the query. `GET /v1/notes` searches with `q`
 *  or `tag` (its `picks`) and reads a time range without. `rest` gathers the other query fields, as columns. */
export type V1Route = { method: "GET" | "POST"; path: string; id: string; summary: string; description: string; tools: WebTool[]; q?: true;
  picks?: string[]; rest?: "where"; adds?: true };
/** A question whose answer is JSON: read_photo answers an image, which the web API does not send. */
export type WebTool = Exclude<ToolName, "read_photo"> | WebName;

export const ROUTES: readonly V1Route[] = [
  { method: "GET", path: "/v1/notes", id: "listNotes", summary: "Search notes, or read a time range", tools: ["search", "timeline"], q: true,
    picks: ["q", "tag"],
    description: "With `q`, the notes whose text holds every word, as the `search` tool; with `tag`, the notes on that topic and its parts: " +
      "`source` picks older recorded or typed notes, and `limit` is at most 50. Without `q` or `tag`, every note from `from` to `to`, as " +
      "the `timeline` tool: both are needed, and `limit` is at most 100. Newest first; read on with `cursor`." },
  { method: "POST", path: "/v1/notes", id: "addNote", summary: TOOLS.add_note.title, tools: ["add_note"], adds: true,
    description: "Add a typed note, with this key's or app's name as its device, and send it on to the person's webhooks. Send the same " +
      "`clientId` again after a lost answer: the note is stored once, and `added` is false. 201 when added." },
  { method: "GET", path: "/v1/notes/{id}", id: "getNote", summary: TOOLS.fetch.title, tools: ["fetch"], description: TOOLS.fetch.description },
  { method: "GET", path: "/v1/days/{day}", id: "getDay", summary: TOOLS.day_summary.title, tools: ["day_summary"], description: TOOLS.day_summary.description },
  { method: "GET", path: "/v1/health", id: "getHealth", summary: TOOLS.health.title, tools: ["health"], description: TOOLS.health.description },
  { method: "GET", path: "/v1/nights", id: "listNights", summary: TOOLS.nights.title, tools: ["nights"], description: TOOLS.nights.description },
  { method: "GET", path: "/v1/workouts", id: "listWorkouts", summary: TOOLS.workouts.title, tools: ["workouts"], description: TOOLS.workouts.description },
  { method: "GET", path: "/v1/places", id: "listPlaces", summary: TOOLS.places.title, tools: ["places"], description: TOOLS.places.description },
  { method: "GET", path: "/v1/points", id: "listPoints", summary: TOOLS.points.title, tools: ["points"], description: TOOLS.points.description },
  { method: "GET", path: "/v1/calendar", id: "listEvents", summary: TOOLS.calendar.title, tools: ["calendar"], q: true,
    description: TOOLS.calendar.description.replace("`query`", "`q`") },
  { method: "GET", path: "/v1/chats", id: "searchChats", summary: TOOLS.search_chats.title, tools: ["search_chats"], q: true,
    description: TOOLS.search_chats.description.replace("`query`", "`q`") },
  { method: "GET", path: "/v1/chats/{id}", id: "getChat", summary: TOOLS.read_chat.title, tools: ["read_chat"], description: TOOLS.read_chat.description },
  { method: "POST", path: "/v1/notes/{id}/tags", id: "tagNote", summary: WEB.tag_note.title, tools: ["tag_note"],
    description: `${WEB.tag_note.description} Only a computer's key; it answers the note's topics.` },
  { method: "GET", path: "/v1/memory", id: "searchMemory", summary: TOOLS.memory.title, tools: ["memory"], q: true, rest: "where",
    description: "The memory's facts, newest first, as the `memory` tool: `q` finds every word in the text columns, `tag` a topic and its " +
      "parts, `source` the facts from one record, such as relay:chat/<id>, and any column its value as its own field, such as " +
      "`kind=decision`. Only live facts, unless `all=true`. The answer lists the memory's columns." },
  { method: "POST", path: "/v1/memory", id: "addFacts", summary: WEB.add_facts.title, tools: ["add_facts"], adds: true,
    description: WEB.add_facts.description },
  { method: "GET", path: "/v1/memory/columns", id: "getColumns", summary: WEB.columns.title, tools: ["columns"], description: WEB.columns.description },
  { method: "POST", path: "/v1/memory/columns", id: "changeColumns", summary: WEB.change_columns.title, tools: ["change_columns"],
    description: `${WEB.change_columns.description} It answers the columns.` },
  { method: "GET", path: "/v1/memory/{id}", id: "getFact", summary: TOOLS.read_fact.title, tools: ["read_fact"], description: TOOLS.read_fact.description },
  { method: "POST", path: "/v1/memory/{id}/tags", id: "tagFact", summary: WEB.tag_fact.title, tools: ["tag_fact"],
    description: `${WEB.tag_fact.description} Only a computer's key; it answers the fact's topics.` },
  { method: "POST", path: "/v1/knowledge/access", id: "openKnowledge", summary: WEB.knowledge_access.title, tools: ["knowledge_access"],
    description: `${WEB.knowledge_access.description} A server whose Cloudflare account has no Artifacts answers 501 \`not_set_up\`.` },
  { method: "GET", path: "/v1/me", id: "getMe", summary: "Check the caller", tools: [],
    description: "The caller's device name, as the phone's key check answers, and whether it may add notes. It reads no data." },
];

export const CODES = { 400: "invalid_request", 401: "invalid_token", 403: "forbidden", 404: "not_found", 405: "method_not_allowed",
  501: "not_set_up", 503: "try_again" } as const;
export type Status = keyof typeof CODES;

/** A refusal as OAuth's error shape, which every /v1/ refusal shares. */
export const problem = (status: Status, description: string, headers: Record<string, string> = {}) =>
  Response.json({ error: CODES[status], error_description: description }, { status, headers: { "Cache-Control": "no-store", ...headers } });

const patterns = new Map(ROUTES.map(route => [route, new RegExp(`^${route.path.replace(/\{(\w+)\}/g, "(?<$1>[^/]+)")}$`)]));

/** The tool's fields that take a number or a boolean: a query parameter is text until it is read as one. */
const typed = (name: WebTool) => new Map(Object.entries(z.toJSONSchema(z.object(INPUTS[name].input), { io: "input" }).properties!)
  .flatMap(([key, field]) => typeof field === "object" && ["number", "integer", "boolean"].includes(String(field.type))
    ? [[key, field.type === "boolean" ? "boolean" : "number"] as const] : []));

/** A query parameter as its field's type; text that is not one stays text, so the field's check refuses it. */
const read = (text: string, type: "number" | "boolean") =>
  type === "number" ? Number(text) : text === "true" ? true : text === "false" ? false : text;

/** The JSON body of a POST, or null when it is not a JSON object. */
async function body(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const value: unknown = await request.json();
    return typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

/** Zod's complaints in one line, each named by its field as the caller sent it. */
const complaints = (error: z.ZodError, q: boolean) => error.issues.map(issue => {
  const path = issue.path.join(".");
  return path ? `\`${q && path === "query" ? "q" : path}\`: ${issue.message}` : issue.message;
}).join("; ");

/** A path field as sent, decoded when it decodes: a bad escape stays as written, and finds nothing. */
function decoded(text: string): string {
  try { return decodeURIComponent(text); } catch { return text; }
}

/** A POST's fields: its JSON body, which a question that takes no input may leave out. */
async function postFields(request: Request, name: WebTool) {
  return await body(request) ?? (Object.keys(INPUTS[name].input).length ? null : {});
}

/** Moves each query field the question does not name into one record, such as a column's value into `where`. */
function gather(fields: Record<string, unknown>, name: WebTool, into: "where") {
  const own = new Set(Object.keys(INPUTS[name].input));
  const rest = Object.entries(fields).filter(([key]) => !own.has(key));
  for (const [key] of rest) delete fields[key];
  if (rest.length) fields[into] = Object.fromEntries(rest);
}

/** Whether an add stored something new: a note, or any of the facts. */
const added = (answered: unknown) => {
  const { added: one, facts } = answered as { added?: boolean; facts?: { added: boolean }[] };
  return one === true || (facts ?? []).some(fact => fact.added);
};

async function me({ space, adder }: Asker) {
  if (!adder || adder.kind === "app") return { device: adder?.name ?? "", adds: adder !== null };
  const row = await space.db.prepare("SELECT name FROM relay_devices WHERE id = ?").bind(adder.deviceId).first<{ name: string }>();
  return { device: row?.name ?? "", adds: true };
}

/** One /v1/ request from a caller the connector already checked. */
export async function v1(request: Request, asker: Asker): Promise<Response> {
  const url = new URL(request.url);
  const found = ROUTES.map(route => ({ route, match: patterns.get(route)!.exec(url.pathname) })).filter(({ match }) => match);
  if (!found.length) return problem(404, "No such route. Every route is in /v1/openapi.json.");
  const chosen = found.find(({ route }) => route.method === request.method);
  // The API never changes or deletes, so no other method has a route.
  if (!chosen) return problem(405, "This route only reads or adds.", { Allow: found.map(({ route }) => route.method).join(", ") });
  const { route, match } = chosen;
  if (!route.tools.length) return Response.json(await me(asker), { headers: { "Cache-Control": "no-store" } });
  const fields = route.method === "POST" ? await postFields(request, route.tools[0]) : Object.fromEntries(url.searchParams);
  if (!fields) return problem(400, "Send a JSON object.");
  const q = route.q === true && "q" in fields;
  const name = route.tools[route.tools.length === 1 || route.picks!.some(key => key in fields) ? 0 : 1];
  if (q) { fields.query = fields.q; delete fields.q; }
  for (const [key, type] of route.method === "GET" ? typed(name) : []) if (typeof fields[key] === "string") fields[key] = read(fields[key], type);
  if (route.rest) gather(fields, name, route.rest);
  Object.assign(fields, Object.fromEntries(Object.entries(match!.groups ?? {}).map(([key, value]) => [key, decoded(value)])));
  const parsed = z.strictObject(INPUTS[name].input).safeParse(fields);
  if (!parsed.success) return problem(400, complaints(parsed.error, route.q === true));
  try {
    const answered = await answer(name, asker, parsed.data as never);
    const status = route.adds && added(answered) ? 201 : 200;
    return Response.json(answered, { status, headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    if (error instanceof Refusal) return problem(error.status, error.message);
    throw error;
  }
}
