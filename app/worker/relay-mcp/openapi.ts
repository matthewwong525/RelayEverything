// The web API's OpenAPI 3.1 document, made from the tools' inputs, the routes and the answers here, so it can't go
// stale. /v1/openapi.json serves it; `npm run relay:api-doc` writes the website's copy and reference page.
import { z } from "zod";
import { ROUTES, type V1Route } from "./api.ts";
import { TOOLS, type ToolName } from "./inputs.ts";

const at = z.string().describe("A time in the asked zone, with its offset: 2026-11-04T09:01:00-05:00.");
const nextCursor = z.string().nullable().describe("Send it as `cursor` to read the next page; null on the last one.");
const note = z.strictObject({
  id: z.string(), title: z.string().describe("The first 80 characters of the text."), source: z.enum(["ring", "typed"]), text: z.string(),
  recordedAt: at, device: z.string().describe("The name of the device that sent it."), audio: z.boolean().describe("Whether it has a recording."),
  place: z.strictObject({ lat: z.number(), lon: z.number(), accuracy: z.number().nullable(), name: z.string().nullable(),
    from: z.enum(["phone", "history"]).describe("phone: the phone's place at the time; history: matched from the location history.") }).nullable(),
});
const visit = z.strictObject({ name: z.string(), lat: z.number(), lon: z.number(), arrived: at, left: at });
const totals = { steps: z.number(), sleepMinutes: z.number(), heartRate: z.strictObject({ min: z.number(), max: z.number(), average: z.number() }).nullable(),
  workouts: z.strictObject({ count: z.number(), minutes: z.number() }) };
const chat = { id: z.string(), title: z.string(), project: z.string().describe("The project's folder name."), app: z.literal("claude-code"),
  startedAt: at, lastAt: at, messages: z.number(), savedByAi: z.boolean() };
const role = z.enum(["you", "ai", "step"]);

/** What each tool answers, and `me`: api.test.ts checks every answer against these. */
export const ANSWERS = {
  search: z.strictObject({ notes: z.array(note), nextCursor }),
  timeline: z.strictObject({ notes: z.array(note), nextCursor }),
  fetch: note.extend({ placesNearby: z.array(visit), day: z.strictObject({ day: z.string(), ...totals }) }),
  day_summary: z.strictObject({ day: z.string(), timezone: z.string(), notes: z.number(), ...totals,
    places: z.array(z.strictObject({ name: z.string(), lat: z.number(), lon: z.number(), from: at, to: at })) }),
  health: z.strictObject({ type: z.string(), bucket: z.enum(["hour", "day"]), timezone: z.string(),
    values: z.array(z.object({ from: at, to: at }).catchall(z.number().nullable())
      .describe("`total` for steps and sleep minutes; `min`, `max` and `average` for heart rate; `count` and `minutes` for workouts.")) }),
  places: z.strictObject({ visits: z.array(visit), next: at.nullable().describe("The first visit left out: read on from it.") }),
  search_chats: z.strictObject({ chats: z.array(z.strictObject({ ...chat, lines: z.array(z.strictObject({ role, text: z.string() })) })), nextCursor }),
  read_chat: z.strictObject({ ...chat, saves: z.array(z.strictObject({ id: z.string(), title: z.string(), text: z.string(), createdAt: at })),
    messages: z.array(z.strictObject({ seq: z.number(), role, text: z.string(), at })), nextCursor }),
  add_note: z.strictObject({ id: z.string().describe("The note's id."), added: z.boolean().describe("False when this clientId was added before.") }),
  me: z.strictObject({ device: z.string().describe("The key's device name, or the app's name."), adds: z.boolean().describe("Whether it may add notes.") }),
} satisfies Record<ToolName | "me", z.ZodType>;

type Json = Record<string, unknown>;
const json = (schema: z.ZodType, io: "input" | "output" = "output") => {
  const { $schema: _, ...rest } = z.toJSONSchema(schema, { io, unrepresentable: "throw" }) as Json;
  return rest;
};
const ERROR = { $ref: "#/components/schemas/Error" };
const refusal = (description: string) => ({ description, content: { "application/json": { schema: ERROR } } });

/** A route's query or path fields from its tools' inputs: `query` is sent as `q`. A field the tools share takes the
 *  last tool's limits, and is required only when every tool needs it. */
function parameters(route: V1Route) {
  const inputs = route.tools.map(name => json(z.object(TOOLS[name].input), "input") as { properties: Record<string, Json>; required?: string[] });
  const fields = new Map(inputs.flatMap(({ properties }) => Object.entries(properties)));
  return [...fields].map(([key, { description, ...schema }]) => {
    const where = route.path.includes(`{${key}}`) ? "path" : "query";
    const required = where === "path" || inputs.every(input => input.required?.includes(key));
    return { name: key === "query" && route.q ? "q" : key, in: where, required, description, schema };
  });
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
  return {
    operationId: route.id, summary: route.summary, description: route.description,
    ...(route.method === "POST"
      ? { requestBody: { required: true, content: { "application/json": { schema: json(z.object(TOOLS.add_note.input), "input") } } },
        responses: { 201: { ...ok, description: "Added." }, 200: { ...ok, description: "Added before: the same note." } } }
      : { parameters: parameters(route), responses: { 200: ok } }),
  };
}

const errors = {
  400: refusal("The input can't be read: `error_description` says which field."),
  401: refusal("No token, or one that is not valid: an expired token or a disconnected app."),
  403: refusal("This caller may not do it: an unknown key, a phone or chat key, a turned-off key, or an app connected before it could add notes."),
  404: refusal("No such note, chat or route in the caller's own space."),
};

/** The whole document, for a server at `origin`. */
export function openApi(origin: string) {
  const paths: Record<string, Json> = {};
  for (const route of ROUTES) {
    const { responses, ...rest } = operation(route);
    paths[route.path] = { ...paths[route.path], [route.method.toLowerCase()]: { ...rest, responses: { ...responses, ...errors } } };
  }
  return {
    openapi: "3.1.0",
    info: { title: "Relay Everything API", version: "1.0.0",
      description: "Read one person's Relay Everything notes, health, places and saved chats, and add notes. It changes and deletes nothing. " +
        "Each caller reaches only the space of the person who connected it or made its key." },
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
          "*Add a device*: send it as `Authorization: Bearer rek_…`. A phone's or a chat key is refused here." },
      },
      schemas: { Error: { type: "object", required: ["error", "error_description"], additionalProperties: false,
        properties: { error: { type: "string", enum: ["invalid_request", "invalid_token", "forbidden", "not_found", "method_not_allowed"] },
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
    const fields = op.parameters?.map(field => `| \`${field.name}\` | ${field.in} | ${cell(typeOf(field.schema))} | ${field.required ? "yes" : "no"} | ${cell(field.description)} |`)
      ?? Object.entries(op.requestBody!.content["application/json"].schema.properties).map(([name, field]) => `| \`${name}\` | body | ${
        cell(typeOf(field))} | ${op.requestBody!.content["application/json"].schema.required?.includes(name) ? "yes" : "no"} | ${cell(field.description as string)} |`);
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
