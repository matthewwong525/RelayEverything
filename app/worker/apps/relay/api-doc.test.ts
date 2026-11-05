import { readFileSync, writeFileSync } from "node:fs";
import { expect, test } from "vitest";
import { z } from "zod";
import { defineAction, type Route } from "../../api/contract.ts";
import { apiReference } from "./api-doc.ts";

const page = new URL("../../../../site/src/content/docs/api/reference.md", import.meta.url);
const bare = () => new Response("ok");

test("the website's route page is the one the routes make", () => {
  if (process.env.RELAY_API_DOC_WRITE) writeFileSync(page, apiReference());
  expect(readFileSync(page, "utf8"), "The routes changed: run `npm run relay:api-doc` in app/").toBe(apiReference());
});

test("the page shows each Relay route, and who can call it", () => {
  const reference = apiReference();
  expect(reference).toContain("`POST /apps/relay/api/notes` · `relay.notes-add` · writes · called by a phone or Pebble key");
  expect(reference).toContain("`GET /apps/relay/api/key` · `relay.key` · reads · called by any device key");
  expect(reference).toContain("`GET /apps/relay/api/summary` · `relay.summary` · reads · called by a signed-in person only");
  expect(reference).toContain("| `notes[].place.name` | string or null | yes |");
  expect(reference).toContain("- `POST /apps/relay/api/pebble`: [Take a ring note from the Pebble app](../pebble-webhook/)");
});

test("a described action shows its fields, errors and example, and a bare handler links to its page", () => {
  const one = defineAction({
    operationId: "test.one", summary: "Read one", description: "Reads one thing.", input: z.strictObject({}), output: z.string(),
    encoding: "none", effect: "read", agentAvailable: false, errors: { not_found: "No thing | none" },
    examples: [{ input: {}, output: "a thing" }], handler: bare,
  });
  const two = defineAction({
    operationId: "test.two", summary: "Send two", description: "Sends two things.",
    input: z.strictObject({ anything: z.unknown().describe("Any value."), tags: z.array(z.string()).optional().describe("Words.") }),
    output: z.strictObject({ ok: z.boolean(), z: z.array(z.strictObject({ a: z.string() })).nullable() }), encoding: "json", effect: "external", agentAvailable: false, errors: {}, examples: [],
    handler: bare,
  });
  const reference = apiReference(new Map<string, Route>([["GET one", one], ["POST two", two], ["GET raw", bare]]),
    { "GET raw": { summary: "Raw bytes", page: "../raw/" } });
  expect(reference).toContain("It takes no input.\n\n### Output\n\nA `string` value.");
  expect(reference).toContain("| `not_found` | No thing \\| none |");
  expect(reference).toContain('Output:\n\n```json\n"a thing"\n```');
  expect(reference).toContain("calls another service");
  expect(reference).toContain("| `anything` | any | yes | Any value. |");
  expect(reference).toContain("| `tags` | array of string | no | Words. |");
  expect(reference).toContain("| `ok` | boolean | yes |  |");
  expect(reference).toContain("| `z` | array of object or null | yes |  |\n| `z[].a` | string | yes |  |");
  expect(reference).toContain("- `GET /apps/relay/api/raw`: [Raw bytes](../raw/)");
});

test("a bare handler with no page stops the reference", () => {
  expect(() => apiReference(new Map<string, Route>([["GET raw", bare]]), {})).toThrow("Give GET raw a page in HAND_PAGES");
});
