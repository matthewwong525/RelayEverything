// The public website's route reference, made from Relay's own routes, so a route change that leaves the page old
// fails api-doc.test.ts. `npm run relay:api-doc` writes it to site/src/content/docs/api/reference.md.
import { registrations, schemas, type Action, type Route } from "../../api/contract.ts";
import { routes as relayRoutes } from "./api.ts";
import { reaches } from "./caller.ts";

type Schema = { type?: string; enum?: unknown[]; items?: Schema; anyOf?: Schema[]; properties?: Record<string, Schema>;
  required?: string[]; description?: string };
/** A route with no description in the contract: its own page on the website says what it does. */
type HandPage = { summary: string; page: string };

const HAND_PAGES: Record<string, HandPage> = {
  "POST pebble": { summary: "Take a ring note from the Pebble app", page: "../pebble-webhook/" },
  "GET audio": { summary: "Play a note's recording", page: "../recordings/" },
  "POST attachments": { summary: "Send a note's file, after its note", page: "../files/#send-a-file" },
  "GET attachment": { summary: "Open a note's file", page: "../files/#open-a-file" },
  "POST chats": { summary: "Send a Claude Code chat's new messages, with a chat key", page: "../../connections/claude-code/#what-the-server-receives" },
};
const ENCODING: Record<Action["encoding"], string> = {
  none: "It takes no input.", query: "Send the input as query parameters.", json: "Send the input as a JSON body.",
};
const EFFECT: Record<Action["effect"], string> = { read: "reads", write: "writes", external: "calls another service" };
const HEAD = "| Field | Type | Required | What it holds |\n|---|---|---|---|";

const cell = (text: string) => text.replaceAll("|", "\\|").replaceAll("\n", " ");

const typeOf = (schema: Schema): string =>
  schema.anyOf ? schema.anyOf.map(typeOf).join(" or ")
    : schema.enum ? schema.enum.map(value => JSON.stringify(value)).join(" or ")
      : schema.type === "array" ? `array of ${typeOf(schema.items!)}`
        : schema.type ?? "any";

/** The object inside a field, whose fields get rows too: the field itself, an array's item, or a nullable's. */
const inner = (schema: Schema): { object: Schema; list: boolean } | undefined =>
  schema.properties ? { object: schema, list: false }
    : schema.items?.properties ? { object: schema.items, list: true }
      : schema.anyOf?.map(inner).find(Boolean);

function rows(schema: Schema, prefix = ""): string[] {
  const required = new Set(schema.required);
  return Object.entries(schema.properties ?? {}).flatMap(([name, field]) => {
    const path = prefix + name;
    const nested = inner(field);
    return [`| \`${path}\` | ${cell(typeOf(field))} | ${required.has(name) ? "yes" : "no"} | ${cell(field.description ?? "")} |`,
      ...(nested ? rows(nested.object, `${path}${nested.list ? "[]" : ""}.`) : [])];
  });
}

const table = (lines: string[]) => [HEAD, ...lines].join("\n");
const json = (value: unknown) => `\`\`\`json\n${JSON.stringify(value, null, 2)}\n\`\`\``;
const caller = (method: string, path: string) => reaches("chats", method, path)
  ? reaches("phone", method, path) ? "any device key" : "a Claude Code chat key only"
  : reaches("phone", method, path) ? "a phone or Pebble key" : "a signed-in person only, not a device key";

function described({ method, path, action }: { method: string; path: string; action: Action }): string {
  const { inputSchema, outputSchema } = schemas(action) as { inputSchema: Schema; outputSchema: Schema };
  const input = rows(inputSchema);
  const output = rows(outputSchema);
  const errors = Object.entries(action.errors);
  const example = action.examples[0];
  return [`## ${action.summary}`, `\`${method} ${path}\` · \`${action.operationId}\` · ${EFFECT[action.effect]} · called by ${caller(method, path)}`,
    action.description, "### Input", input.length ? `${ENCODING[action.encoding]}\n\n${table(input)}` : ENCODING[action.encoding],
    "### Output", output.length ? table(output) : `A \`${typeOf(outputSchema)}\` value.`,
    ...(errors.length ? ["### Errors", `| Code | When |\n|---|---|\n${errors.map(([code, when]) => `| \`${code}\` | ${cell(when)} |`).join("\n")}`] : []),
    ...(example ? ["### Example", `Input:\n\n${json(example.input)}\n\nOutput:\n\n${json(example.output)}`] : []),
  ].join("\n\n");
}

function bare(key: string, pages: Record<string, HandPage>): string {
  const hand = pages[key];
  if (!hand) throw new Error(`Give ${key} a page in HAND_PAGES (api-doc.ts): it has no description in the contract.`);
  const [method, route] = key.split(" ");
  return `- \`${method} /apps/relay/api/${route}\`: [${hand.summary}](${hand.page})`;
}

/** The whole reference page, front matter included. */
export function apiReference(routes: Map<string, Route> = relayRoutes, pages: Record<string, HandPage> = HAND_PAGES): string {
  const handlers = [...routes].filter(([, route]) => typeof route === "function").map(([key]) => bare(key, pages));
  return `---
title: Routes
description: Every route of the Relay Everything server, with its fields, made from the server's own route list.
---

<!-- Made by \`npm run relay:api-doc\` in app/ from app/worker/apps/relay/. Do not edit it by hand. -->

Each route sits under \`https://<your-relay-server>/apps/relay/api/\`. A device sends its key as
\`Authorization: Bearer rek_…\`, as [Keys](../keys/) shows; a person signs in on the page. A refused call answers \`{ "error": { "code": "...", "message": "..." } }\`; [Keys](../keys/#errors)
lists the codes.

${registrations(routes, "relay").map(described).join("\n\n")}

## Routes with their own page

${handlers.join("\n")}
`;
}
