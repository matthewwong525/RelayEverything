import { expect, it, vi } from "vitest";
import { ANA, BEN } from "../../../tests/relay";
import { keyedConnector, V1_KEYS } from "../../../tests/relay-v1";
import { COMPUTER_ONLY } from "../../relay-mcp/answers";
import { knowledgeAccess, NOT_SET_UP } from "./knowledge";

const at = Date.UTC(2026, 10, 10, 12);

/** A stand-in Artifacts namespace: `start` when asked, and a forked repo answers FORK_IN_PROGRESS `forking` times. */
function fakeArtifacts({ start = true, forking = 0 } = {}) {
  const repos = new Map<string, { forking: number }>(start ? [["start", { forking: 0 }]] : []);
  const forks: unknown[][] = [];
  const passes: unknown[][] = [];
  const failure = (code: string) => Object.assign(new Error(code), { name: "ArtifactsError", code });
  const handle = (name: string) => ({
    name, remote: `https://account.artifacts.cloudflare.net/git/relay-everything-knowledge/${name}.git`,
    createToken: async (scope: string, ttl: number) => {
      passes.push([name, scope, ttl]);
      return { id: "t-1", plaintext: `art_v1_${name}`, scope, expiresAt: new Date(at + ttl * 1000).toISOString() };
    },
    fork: async (target: string, options: object) => {
      if (repos.has(target)) throw failure("ALREADY_EXISTS");
      repos.set(target, { forking });
      forks.push([name, target, options]);
    },
  });
  const KNOWLEDGE = {
    get: vi.fn(async (name: string) => {
      const repo = repos.get(name);
      if (!repo) throw failure("NOT_FOUND");
      if (repo.forking-- > 0) throw failure("FORK_IN_PROGRESS");
      return handle(name);
    }),
    delete: async (name: string) => repos.delete(name),
  };
  return { KNOWLEDGE: KNOWLEDGE as unknown as Artifacts, repos, forks, passes };
}

const open = (connector: Awaited<ReturnType<typeof keyedConnector>>, key?: string) => connector.v1("knowledge/access", key, {});

it("makes Ana's web by a fork on her computer's first ask, and gives a write pass to it alone for one hour", async () => {
  const artifacts = fakeArtifacts();
  const connector = await keyedConnector({ KNOWLEDGE: artifacts.KNOWLEDGE });
  const remote = `https://account.artifacts.cloudflare.net/git/relay-everything-knowledge/p-${ANA}.git`;
  const pass = { remote, token: `art_v1_p-${ANA}`, expiresAt: "2026-11-10T13:00:00.000Z" };
  expect(await open(connector)).toEqual({ status: 200, json: pass });
  expect(artifacts.forks).toEqual([["start", `p-${ANA}`, { defaultBranchOnly: true, description: "A Relay Everything knowledge web." }]]);
  expect(await open(connector)).toEqual({ status: 200, json: pass });
  expect([artifacts.forks.length, artifacts.passes]).toEqual([1, [[`p-${ANA}`, "write", 3600], [`p-${ANA}`, "write", 3600]]]);
  // A caller can't name a repo: Ben's computer gets Ben's web, and Ana's gets hers.
  expect((await open(connector, V1_KEYS.ben)).json.remote).toContain(`/p-${BEN}.git`);
  expect((await connector.v1("knowledge/access", undefined, { repo: `p-${BEN}` })).status).toBe(400);
  expect((await connector.v1("knowledge/access")).status).toBe(405);
  // A POST with no body is fine: the ask takes no input.
  expect((await connector.v1("knowledge/access", undefined, null)).status).toBe(200);
});

it("refuses a phone, a turned-off key, an old chat key and an API key, and gives no pass", async () => {
  const artifacts = fakeArtifacts();
  const connector = await keyedConnector({ KNOWLEDGE: artifacts.KNOWLEDGE });
  for (const key of [V1_KEYS.phone, V1_KEYS.off, V1_KEYS.chats, V1_KEYS.api]) {
    expect((await open(connector, key)).status, key).toBe(403);
  }
  expect((await open(connector, V1_KEYS.api)).json.error_description).toBe(COMPUTER_ONLY);
  expect([artifacts.passes, artifacts.forks]).toEqual([[], []]);
});

it("says the web is not set up on a server with no Artifacts, or no start repo, and every other route still works", async () => {
  const bare = await keyedConnector();
  expect(await open(bare)).toEqual({ status: 501, json: { error: "not_set_up", error_description: NOT_SET_UP } });
  expect((await bare.v1("memory?tag=battery")).status).toBe(200);
  const unset = await keyedConnector({ KNOWLEDGE: fakeArtifacts({ start: false }).KNOWLEDGE });
  expect(await open(unset)).toEqual({ status: 501, json: { error: "not_set_up", error_description: NOT_SET_UP } });
});

it("waits for a fork that is still running, and asks to try again when it runs long", async () => {
  const wait = vi.fn(async () => {});
  expect(await knowledgeAccess(fakeArtifacts({ forking: 1 }).KNOWLEDGE, ANA, wait)).toMatchObject({ token: `art_v1_p-${ANA}` });
  expect(wait).toHaveBeenCalledTimes(1);
  await expect(knowledgeAccess(fakeArtifacts({ forking: 9 }).KNOWLEDGE, ANA, wait)).rejects
    .toMatchObject({ status: 503, message: "Your knowledge web is still being made. Try again in a minute." });
  const broken = { get: async () => { throw Object.assign(new Error("down"), { code: "INTERNAL_ERROR" }); } } as unknown as Artifacts;
  await expect(knowledgeAccess(broken, ANA, wait)).rejects.toThrow("down");
});

it("passes on any other Artifacts failure, takes a fork another ask began, and waits a second by default", async () => {
  const failure = (code: string) => Object.assign(new Error(code), { code });
  const namespace = (start: () => Promise<unknown>) => ({ get: async (name: string) => {
    if (name === "start") return start();
    throw failure("NOT_FOUND");
  } }) as unknown as Artifacts;
  await expect(knowledgeAccess(namespace(async () => { throw failure("INTERNAL_ERROR"); }), ANA)).rejects.toThrow("INTERNAL_ERROR");
  await expect(knowledgeAccess(namespace(async () => { throw "down"; }), ANA)).rejects.toBe("down");
  const forking = (error: Error) => namespace(async () => ({ fork: async () => { throw error; } }));
  await expect(knowledgeAccess(forking(failure("QUOTA_EXCEEDED")), ANA)).rejects.toThrow("QUOTA_EXCEEDED");
  // Another ask's fork is no failure: this ask waits for that fork, here until it gives up.
  await expect(knowledgeAccess(forking(failure("ALREADY_EXISTS")), ANA, async () => {})).rejects.toMatchObject({ status: 503 });
  vi.useFakeTimers();
  const waited = knowledgeAccess(fakeArtifacts({ forking: 1 }).KNOWLEDGE, ANA);
  await vi.advanceTimersByTimeAsync(1000);
  expect(await waited).toMatchObject({ token: `art_v1_p-${ANA}` });
  vi.useRealTimers();
});
