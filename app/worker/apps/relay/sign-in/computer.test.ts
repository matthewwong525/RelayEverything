import { expect, it, vi } from "vitest";
import { ANA, call, directoryDb, env, matthew, NOW, phone, request, rows, type Who } from "../../../../tests/relay";
import { body } from "../../../../tests/body";
import { relayGate } from "../caller";
import { signIn } from "./index";

const ORIGIN = "https://relay.example.com";
const VERIFIER = "v".repeat(43);
const CHALLENGE = "7w_YNF9DSfIdPf_pRjSq646_kPr-2-o9NAl16JGghdM";
const LINK = `${ORIGIN}/apps/relay/sign-in/computer?c=${CHALLENGE}`;
const identityOf = (who: Who) => who && "kind" in who ? who : null;

async function send(who: Who, method: string, path: string, init: RequestInit = {}, more: object = {}) {
  return (await signIn(request(who, method, `${ORIGIN}/apps/relay/sign-in/${path}`, init), env(more), identityOf(who)))!;
}
const json = (input: object) => ({ headers: { "content-type": "application/json", Origin: "null" }, body: JSON.stringify(input) });
const start = (input: object = { challenge: CHALLENGE, name: "Ana's laptop" }, more?: object) => send(null, "POST", "computer/start", json(input), more);
const open = (who: Who, query = `?c=${CHALLENGE}`) => send(who, "GET", `computer${query}`);
const confirm = (who: Who, fields: Record<string, string>, headers: Record<string, string> = {}) =>
  send(who, "POST", "computer", { body: new URLSearchParams(fields), headers });
const ask = (verifier = VERIFIER, more?: object) => send(null, "POST", "computer/key", json({ verifier }), more);
const keys = () => directoryDb.sql.prepare("SELECT count(*) AS n FROM relay_keys WHERE person_id = ?").get(ANA);

it("gives the computer a link and a code, and asks the signed-in person to connect it by that code", async () => {
  const started = await start();
  expect(started.status).toBe(200);
  const { link, words } = await started.json() as { link: string; words: string };
  expect([link, words]).toEqual([LINK, expect.stringMatching(/^[A-Z]{4}-\d{4}$/)]);
  const page = await open(matthew);
  expect(page.status).toBe(200);
  const html = await page.text();
  for (const text of ["Connect this computer?", words, "Connect only a computer you just started this on", 'value="Ana&#39;s laptop"',
    "reads all your Relay Everything data", "disconnect it in Connect your AI"]) expect(html).toContain(text);
  expect(html).not.toContain("Devices");
  const out = await open(null);
  expect(out.headers.get("Location")).toBe(`/?next=${encodeURIComponent(`/apps/relay/sign-in/computer?c=${CHALLENGE}`)}`);
  expect((await open(phone)).status).toBe(403);
  expect((await open(matthew, "?c=short")).status).toBe(400);
  // The same secret starts once only.
  expect((await start()).status).toBe(400);
});

it("makes the computer its own key after Connect, once, and the key sends chats and reads only through the web API", async () => {
  await start();
  expect(await (await ask()).json()).toEqual({ waiting: true });
  const done = await confirm(matthew, { c: CHALLENGE, name: "Work laptop", choice: "connect" });
  expect(await done.text()).toContain("Work laptop is connected to Relay Everything");
  expect((await open(matthew)).status).toBe(400);
  const answer = await ask(VERIFIER, { RELAY_MCP_CALLBACK: "https://mcp.example.com/callback" });
  expect(answer.status).toBe(200);
  const { key, ...rest } = await answer.json() as { key: string };
  expect(rest).toEqual({ server: ORIGIN, api: "https://mcp.example.com/v1", name: "Work laptop" });
  expect(key).toMatch(/^rek_[A-Za-z0-9_-]{43}$/);
  expect((await call(matthew, "GET", "devices")).json.devices.find(device => String(device.name) === "Work laptop")).toMatchObject({ reaches: "agent" });
  const chat = { sessionId: "codex-session-0001", app: "codex", project: "trip", startedAt: NOW, messages: [{ seq: 0, role: "you", text: "Hello", at: NOW }] };
  expect((await call({ bearer: key }, "POST", "chats", chat)).json).toEqual({ stored: 1 });
  expect(rows("relay_chats").map(row => row.app)).toEqual(["codex"]);
  const timeline = await relayGate(request({ bearer: key }, "GET", `${ORIGIN}/apps/relay/api/timeline`), env(), null, "/apps/relay/api/timeline");
  expect(timeline?.status).toBe(403);
  // Once: a second ask makes no key.
  expect((await body(await ask())).error.message).toMatch(/used already, or is too old/);
  expect(keys()).toEqual({ n: 5 });
});

it("makes no key for a wrong secret, an old link, a Cancel, or a server with no spaces", async () => {
  await start();
  await confirm(matthew, { c: CHALLENGE, choice: "connect" });
  expect((await ask("w".repeat(43))).status).toBe(400);
  expect((await ask("short")).status).toBe(400);
  expect((await ask(VERIFIER, { SPACES: undefined })).status).toBe(503);
  vi.setSystemTime(NOW + 10 * 60_000 + 1);
  expect((await ask()).status).toBe(400);
  // An old row goes at the next start, so the same secret starts again; Cancel ends it.
  expect((await start()).status).toBe(200);
  expect(await (await confirm(matthew, { c: CHALLENGE, choice: "cancel" })).text()).toContain("Cancelled");
  expect((await ask()).status).toBe(400);
  expect((await confirm(matthew, { c: CHALLENGE, choice: "connect" })).status).toBe(400);
  expect(keys()).toEqual({ n: 4 });
});

it("takes Connect only from the Relay Everything page and a person, and limits starts by address", async () => {
  await start();
  const fields = { c: CHALLENGE, choice: "connect" };
  expect((await confirm(matthew, fields, { Origin: "https://evil.example" })).status).toBe(403);
  expect((await confirm(null, fields)).status).toBe(403);
  expect((await confirm(phone, fields)).status).toBe(403);
  expect((await confirm(matthew, { ...fields, c: "short" })).status).toBe(400);
  expect(await (await ask()).json()).toEqual({ waiting: true });
  const limit = { limit: vi.fn(async () => ({ success: false })) };
  expect((await start({ challenge: CHALLENGE }, { RELAY_SIGN_IN_LIMIT: limit })).status).toBe(429);
  expect((await start({ challenge: "short" })).status).toBe(400);
  // A name the computer leaves out is a plain one.
  await send(null, "POST", "computer/start", json({ challenge: "A".repeat(43) }));
  expect(directoryDb.sql.prepare("SELECT name FROM relay_computer_codes WHERE challenge = ?").get("A".repeat(43))).toEqual({ name: "Computer" });
});

it("refuses a start, a page, a Connect or an ask with nothing to read, or with a key it doesn't know", async () => {
  await start();
  expect((await send(null, "POST", "computer/start", { headers: { "content-type": "application/json" }, body: "not json" })).status).toBe(400);
  expect((await start({ challenge: 7 })).status).toBe(400);
  expect((await open(matthew, "")).status).toBe(400);
  const stranger = { bearer: `rek_${"x".repeat(43)}` };
  expect((await open(stranger)).status).toBe(403);
  expect((await confirm(stranger, { c: CHALLENGE, choice: "connect" })).status).toBe(403);
  expect((await send(matthew, "POST", "computer", { body: "c=" })).status).toBe(400);
  expect((await send(matthew, "POST", "computer", { body: "x", headers: { "content-type": "text/plain" } })).status).toBe(400);
  expect((await send(null, "POST", "computer/key", json({ verifier: 7 }))).status).toBe(400);
  expect(await (await ask()).json()).toEqual({ waiting: true });
});
