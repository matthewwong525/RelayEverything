/// <reference types="node" />
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, it } from "vitest";
import { spaceOf, vouch, type Caller, type SpaceEnv } from "./space";

// The one door into a person's space: only space.ts opens a space or the file store, and only these files vouch for a
// caller, each after its own check. wiki/relay-spaces.md
const app = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const DOOR = "worker/apps/relay/space.ts";
const VOUCHERS = new Set(["worker/apps/relay/caller.ts", "worker/apps/relay/webhooks/send.ts", "worker/relay-mcp/asker.ts",
  "worker/apps/relay/sign-in/phone.ts"]);
const OPENS = /SPACES\.|idFromName|RELAY_BUCKET/g;
const VOUCH = /\bvouch\(/g;
/** The inbox's live line is another Durable Object, which holds no person's space. */
const OTHER_OBJECTS: Record<string, string> = { "worker/apps/inbox/wake.ts": "env.LIVE_LINE.idFromName(" };

/** What a file names that it may not: each name once, in the order found. */
function flagged(path: string, text: string): string[] {
  const allowed = OTHER_OBJECTS[path];
  const checked = allowed ? text.replaceAll(allowed, "") : text;
  const opens = path === DOOR ? [] : checked.match(OPENS) ?? [];
  const vouches = VOUCHERS.has(path) ? [] : checked.match(VOUCH) ?? [];
  return [...new Set([...opens, ...vouches])];
}

const sources = readdirSync(join(app, "worker"), { recursive: true, encoding: "utf8" })
  .filter(file => file.endsWith(".ts") && !file.endsWith(".test.ts"))
  .map(file => `worker/${file.replaceAll("\\", "/")}`);
const read = (path: string) => readFileSync(join(app, path), "utf8");

it("lets no file but space.ts open a space or the file store, and no file outside the list vouch for a caller", () => {
  expect(sources).toContain(DOOR);
  const found = Object.fromEntries(sources.map(path => [path, flagged(path, read(path))]).filter(([, names]) => names.length));
  expect(found).toEqual({});
});

it("checks the spaces Worker too: it runs a space's SQL by RPC, and needs no binding name, so it gets no exception", () => {
  expect(sources).toContain("worker/spaces-worker.ts");
  expect(flagged("worker/spaces-worker.ts", read("worker/spaces-worker.ts"))).toEqual([]);
});

it("keeps each allowed file needed: each one really vouches, and space.ts really opens the space", () => {
  for (const path of VOUCHERS) expect(read(path), path).toMatch(VOUCH);
  expect(read(DOOR)).toMatch(/SPACES\.idFromName/);
  expect(read(DOOR)).toMatch(/RELAY_BUCKET/);
  for (const [path, allowed] of Object.entries(OTHER_OBJECTS)) expect(read(path), path).toContain(allowed);
});

it("flags a made-up owner screen that opens another person's space, and a vouch outside the list", () => {
  const screen = `const stub = env.SPACES.get(env.SPACES.idFromName(id));\nconst files = env.RELAY_BUCKET;\nvouch("session", id);`;
  expect(flagged("worker/apps/relay/owner-screen.ts", screen)).toEqual(["SPACES.", "idFromName", "RELAY_BUCKET", "vouch("]);
  expect(flagged(DOOR, screen)).toEqual(["vouch("]);
  expect(flagged("worker/apps/relay/caller.ts", screen)).toEqual(["SPACES.", "idFromName", "RELAY_BUCKET"]);
  expect(flagged("worker/apps/inbox/wake.ts", "env.LIVE_LINE.idFromName(a); env.SPACES.idFromName(b);")).toEqual(["SPACES.", "idFromName"]);
});

it("opens a space only for a caller that vouch made, never for one written by hand", () => {
  const opened: string[] = [];
  const env = { SPACES: { idFromName: (name: string) => opened.push(name), get: () => ({}) } } as unknown as SpaceEnv;
  const forged = { kind: "session", personId: "someone-else" } as unknown as Caller;
  expect(() => spaceOf(env, forged)).toThrow("A space opens only for a checked caller.");
  expect(opened).toEqual([]);
  expect(spaceOf(env, vouch("session", "ana")).personId).toBe("ana");
  expect(opened).toEqual(["ana"]);
});
