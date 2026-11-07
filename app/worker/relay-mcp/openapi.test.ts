/// <reference types="node" />
import { readFileSync, writeFileSync } from "node:fs";
import { Validator } from "@seriousme/openapi-schema-validator";
import { expect, test } from "vitest";
import { ROUTES } from "./api";
import { answerSchema, openApi, v1Reference } from "./openapi";

const site = new URL("../../../site/", import.meta.url);
const files = { document: new URL("public/api/v1.openapi.json", site), reference: new URL("src/content/docs/api/v1-reference.md", site) };
const siteCopy = () => `${JSON.stringify(openApi("https://<your-relay-server>"), null, 2)}\n`;

test("the website's OpenAPI file and reference page are the ones the routes make", () => {
  if (process.env.RELAY_API_DOC_WRITE) {
    writeFileSync(files.document, siteCopy());
    writeFileSync(files.reference, v1Reference());
  }
  const stale = "The web API changed: run `npm run relay:api-doc` in app/";
  expect(readFileSync(files.document, "utf8"), stale).toBe(siteCopy());
  expect(readFileSync(files.reference, "utf8"), stale).toBe(v1Reference());
});

test("every route is in the document with its method, and both copies pass an OpenAPI 3.1 validator", async () => {
  const live = openApi("https://relay-mcp.example.com");
  for (const route of ROUTES) expect(live.paths[route.path], route.path).toHaveProperty(route.method.toLowerCase());
  expect(live.servers).toEqual([{ url: "https://relay-mcp.example.com" }]);
  expect(live.components.securitySchemes.oauth2.flows.authorizationCode.tokenUrl).toBe("https://relay-mcp.example.com/token");
  // An OAuth address must be a URI, and the site's placeholder is not, so its copy is checked with a host in it.
  for (const document of [live, JSON.parse(siteCopy().replaceAll("<your-relay-server>", "your-relay-server.example"))]) {
    const { valid, errors } = await new Validator().validate(document);
    expect(errors, JSON.stringify(errors)).toBeUndefined();
    expect(valid).toBe(true);
  }
  expect(siteCopy()).toContain('"url": "https://<your-relay-server>"');
  expect(siteCopy()).not.toMatch(/workers\.dev|relayeverything\.com/);
});

test("no answer's oneOf holds two equal branches, which every answer would match and so fail", () => {
  const operations = Object.values(openApi("https://relay-mcp.example.com").paths).flatMap(methods => Object.values(methods as Record<string, {
    responses: Record<string, { content: { "application/json": { schema: { oneOf?: unknown[] } } } }> }>));
  const branches = operations.flatMap(op => Object.values(op.responses)).map(answer => answer.content["application/json"].schema.oneOf ?? []);
  for (const oneOf of branches) expect(new Set(oneOf.map(branch => JSON.stringify(branch))).size).toBe(oneOf.length);
  const notes = openApi("https://relay-mcp.example.com").paths["/v1/notes"] as { get: { responses: { 200: { content: { "application/json": {
    schema: Record<string, unknown> } } } } } };
  expect(notes.get.responses[200].content["application/json"].schema).not.toHaveProperty("oneOf");
  expect(answerSchema(["search", "timeline"])).toEqual(answerSchema(["search"]));
  expect(answerSchema(["search", "fetch", "timeline"])).toEqual({ oneOf: [answerSchema(["search"]), answerSchema(["fetch"])] });
});

test("the reference page shows each route's fields, with q for the query", () => {
  const page = v1Reference();
  expect(page).toContain("`GET /v1/notes` · `listNotes`");
  expect(page).toContain("| `q` | query | string | no |");
  expect(page).toContain("| `from` | query | string | no |");
  expect(page).toContain("| `id` | path | string | yes |");
  expect(page).toContain("| `clientId` | body | string | yes |");
  expect(page).toContain("| `source` | query | \"ring\" or \"typed\" | no |");
  expect(page).toContain("`GET /v1/me` · `getMe`\n\nThe caller's device name");
  expect(page).toContain("It takes no input.");
});
