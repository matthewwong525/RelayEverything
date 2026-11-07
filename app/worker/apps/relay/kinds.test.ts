import { existsSync, readdirSync, readFileSync } from "node:fs";
import { expect, it } from "vitest";
import { ROUTES } from "../../relay-mcp/api.ts";
import { TOOLS } from "../../relay-mcp/inputs.ts";
import { KINDS, WEBHOOK_KINDS, type DataKind } from "./kinds.ts";
import { message } from "./webhooks/format.ts";

const root = new URL("../../../../", import.meta.url);
const read = (path: string) => readFileSync(new URL(path, root), "utf8");
const database = read("site/src/content/docs/connections/your-database.md");
const receiver = read("site/public/webhooks/receiver.mjs");
const TYPES: string[] = message.options.map(option => option.shape.type.value);
/** The one message type every webhook gets, which no kind owns. */
const SHARED = ["webhook.test"];
const paths = new Set(ROUTES.map(route => route.path));
const docsPage = (slug: string) => [".md", ".mdx"].some(end => existsSync(new URL(`site/src/content/docs/${slug}${end}`, root)));

/** What a kind has of its webhook part: each problem names the kind and the part. */
function webhookProblems(kind: DataKind): string[] {
  if (kind.missing?.webhook) {
    return kind.log.length || kind.messages.length || kind.build ? [`${kind.id}: webhook is listed as missing, but it has messages`] : [];
  }
  return [
    ...!kind.label ? [`${kind.id}: no tick words`] : [],
    ...!kind.messages.length ? [`${kind.id}: no webhook message`] : [],
    ...kind.log.length && !kind.build ? [`${kind.id}: no body builder for its send log rows`] : [],
    ...kind.messages.flatMap(type => [
      ...!TYPES.includes(type) ? [`${kind.id}: ${type} is not in webhooks/format.ts`] : [],
      ...!database.includes(`### \`${type}\``) ? [`${kind.id}: ${type} has no heading in connections/your-database.md`] : [],
      ...!receiver.includes(`'${type}':`) ? [`${kind.id}: ${type} has no branch in receiver.mjs`] : [],
    ]),
  ];
}

/** Each part a kind lacks and does not list as missing, and each part listed as missing that it has. */
function problemsOf(kind: DataKind): string[] {
  const { id, missing = {} } = kind;
  const api = missing.api
    ? kind.api.length || [...paths].some(path => path.startsWith(`/v1/${id}`)) ? [`${id}: api is listed as missing, but a route exists`] : []
    : !kind.api.length ? [`${id}: no /v1/ route`] : kind.api.filter(path => !paths.has(path)).map(path => `${id}: no route ${path}`);
  const tool = missing.tool
    ? kind.tools.length || id in TOOLS ? [`${id}: tool is listed as missing, but a tool exists`] : []
    : !kind.tools.length ? [`${id}: no AI connector tool`] : kind.tools.filter(name => !(name in TOOLS)).map(name => `${id}: no tool ${name}`);
  const docs = missing.docs
    ? kind.docs ? [`${id}: docs is listed as missing, but it names a page`] : []
    : !kind.docs || !docsPage(kind.docs) ? [`${id}: no docs page ${kind.docs ?? ""}`.trim()] : [];
  return [...webhookProblems(kind), ...api, ...tool, ...docs];
}

/** Each value that is not owned by exactly one kind. */
const owners = (values: string[], owned: (kind: DataKind) => string[]) =>
  values.filter(value => KINDS.filter(kind => owned(kind).includes(value)).length !== 1);

it("has every part of every kind, or lists the part as missing", () => {
  expect(KINDS.flatMap(problemsOf)).toEqual([]);
  expect(WEBHOOK_KINDS.map(kind => kind.id)).toEqual(["notes", "health", "locations", "calendar"]);
  expect(KINDS.filter(kind => kind.missing).map(kind => [kind.id, Object.keys(kind.missing!)])).toEqual([
    ["files", ["webhook", "api", "tool"]], ["photos", ["webhook", "api"]], ["chats", ["webhook"]]]);
});

it("names the kind and the part a check finds missing", () => {
  const [notes, health] = KINDS;
  expect(problemsOf({ ...notes, docs: "app/nowhere" })).toEqual(["notes: no docs page app/nowhere"]);
  expect(problemsOf({ ...health, messages: ["health.kept"], tools: [], missing: { webhook: undefined } })).toEqual([
    "health: health.kept is not in webhooks/format.ts", "health: health.kept has no heading in connections/your-database.md",
    "health: health.kept has no branch in receiver.mjs", "health: no AI connector tool"]);
  expect(problemsOf({ ...health, missing: { api: "Not yet." } })).toEqual(["health: api is listed as missing, but a route exists"]);
  expect(problemsOf({ ...health, build: undefined, missing: { webhook: "Not yet." } }))
    .toEqual(["health: webhook is listed as missing, but it has messages"]);
});

it("gives each message type and each send log kind exactly one owner", () => {
  expect(owners(TYPES.filter(type => !SHARED.includes(type)), kind => kind.messages)).toEqual([]);
  expect(KINDS.flatMap(kind => kind.messages).filter(type => !TYPES.includes(type))).toEqual([]);
  const latest = readdirSync(new URL("schema/space-migrations/", root)).sort().reverse()
    .map(name => read(`schema/space-migrations/${name}`)).find(sql => sql.includes("CREATE TABLE relay_outbox"))!;
  const logged = /kind TEXT NOT NULL CHECK \(kind IN \(([^)]*)\)\)/.exec(latest)![1].split(",").map(item => item.trim().replaceAll("'", ""));
  expect(owners(logged, kind => kind.log)).toEqual([]);
  expect(KINDS.flatMap(kind => kind.log).sort()).toEqual(logged.sort());
});
