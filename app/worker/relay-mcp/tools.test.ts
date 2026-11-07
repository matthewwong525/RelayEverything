import { readdirSync, readFileSync } from "node:fs";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { beforeAll, expect, it } from "vitest";
import { ANA, BEN, fakeSpaces, NOW, queue } from "../../tests/relay";
import { APP_DEVICE, RECONNECT } from "./answers";
import { APP_DEVICE_OFF } from "./asker";
import type { GrantProps } from "./env";
import { mcpHandler } from "./tools";

const spaceRows = readFileSync(new URL("../../tests/relay-space-rows.sql", import.meta.url), "utf8");

/** Ana's space with the made-up rows, and Ben's with a note of his own that holds the same words. */
function seeded() {
  const made = fakeSpaces();
  const sql = made.sql(ANA);
  sql.exec(spaceRows);
  made.sql(BEN).exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-ben', 'Phone', 'rek:d-ben', '', 0, 'phone');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at)
    VALUES ('${ID(7)}', 'd-ben', 'typed', 'ben-1', 'Ben: buy milk and the ring.', 1793811000000, 0)`);
  return { sql, SPACES: made.SPACES };
}

/** A grant as /callback makes it now: Ana's space, and adding notes as the app's own device. */
const GRANT: GrantProps = { personId: ANA, adds: true, deviceId: "e0000000-0000-4000-8000-000000000001", name: "Claude" };

/** An MCP client that reaches the connector with this grant. */
async function connect(SPACES: DurableObjectNamespace, props: GrantProps = GRANT) {
  const connected = new Client({ name: "test", version: "1.0.0" });
  await connected.connect(new StreamableHTTPClientTransport(new URL("https://relay-mcp.example.com/mcp"),
    { fetch: (url, init) => mcpHandler.fetch(new Request(url, init), { SPACES, RELAY_WEBHOOKS: queue as never }, { props }) }));
  return connected;
}

let client: Client;
beforeAll(async () => { client = await connect(seeded().SPACES); });

/** A tool's answer as JSON, or its refusal's text. */
async function ask(name: string, args: Record<string, unknown>) {
  const { content, isError } = await client.callTool({ name, arguments: args }) as { content: { text: string }[]; isError?: boolean };
  return isError ? { refused: content[0].text } : JSON.parse(content[0].text);
}

const ID = (n: number) => `a0000000-0000-4000-8000-00000000000${n}`;
const ids = (answer: { notes: { id: string }[] }) => answer.notes.map(note => note.id);
const harbord = { name: "Harbord St", lat: 43.6629, lon: -79.3957, arrived: "2026-11-04T08:00:00-05:00", left: "2026-11-04T08:00:00-05:00" };
const day = { steps: 8690, sleepMinutes: 450, heartRate: { min: 68, max: 121, average: 95 }, workouts: { count: 1, minutes: 40 } };

it("names itself Relay Everything to the AI app", () => {
  expect(client.getServerVersion()).toMatchObject({ name: "relay", title: "Relay Everything" });
  expect(client.getInstructions()).toMatch(/^Relay Everything /);
});

it("lists the nine Relay Everything tools, read-only but add_note, then the fourteen Google tools, marked by what they change", async () => {
  const { tools } = await client.listTools();
  expect(tools.map(tool => tool.name)).toEqual(["search", "fetch", "timeline", "day_summary", "health", "places", "search_chats", "read_chat", "add_note",
    "search_email", "read_email", "send_email", "draft_email", "change_email", "list_events", "add_event", "change_event", "delete_event",
    "search_files", "read_file", "save_file", "change_file", "find_contact"]);
  for (const tool of tools.slice(0, 8)) expect(tool.annotations).toMatchObject({ readOnlyHint: true, destructiveHint: false, openWorldHint: false });
  expect(tools[8].annotations).toMatchObject({ readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false });
  const google = Object.fromEntries(tools.slice(9).map(tool => [tool.name, tool.annotations]));
  for (const name of ["search_email", "read_email", "list_events", "search_files", "read_file", "find_contact"]) {
    expect(google[name], name).toEqual({ readOnlyHint: true, destructiveHint: false, openWorldHint: true });
  }
  for (const name of ["send_email", "delete_event"]) expect(google[name], name).toEqual({ readOnlyHint: false, destructiveHint: true, openWorldHint: true });
  for (const name of ["draft_email", "change_email", "add_event", "change_event", "save_file", "change_file"]) {
    expect(google[name], name).toEqual({ readOnlyHint: false, destructiveHint: false, openWorldHint: true });
  }
});

it("finds notes holding every word, in any case, with a title and the time in the zone", async () => {
  expect(await ask("search", { query: "milk" })).toEqual({ nextCursor: null, notes: [{ id: ID(3), source: "ring",
    text: "Buy milk and batteries.", title: "Buy milk and batteries.", recordedAt: "2026-11-04T16:58:20-05:00", device: "Pebble app",
    audio: false, place: null, attachments: [] }] });
  expect(ids(await ask("search", { query: "the" }))).toEqual([ID(2), ID(1)]);
  expect(ids(await ask("search", { query: "THE ring" }))).toEqual([ID(2)]);
  expect(ids(await ask("search", { query: "the", source: "ring" }))).toEqual([ID(1)]);
  expect(ids(await ask("search", { query: "the", from: "2026-11-04T12:00" }))).toEqual([ID(2)]);
  expect(ids(await ask("search", { query: "the", to: "2026-11-04T12:00" }))).toEqual([ID(1)]);
  expect(ids(await ask("search", { query: "100%" }))).toEqual([]);
  const first = await ask("search", { query: "the", limit: 1, timezone: "Europe/London" });
  expect(first.notes[0].recordedAt).toBe("2026-11-04T17:01:40+00:00");
  expect(ids(await ask("search", { query: "the", cursor: first.nextCursor }))).toEqual([ID(1)]);
  expect(await ask("search", { query: "the", cursor: "page-2" })).toEqual({ refused: "That cursor is not one this connector gave." });
});

it("reads a time range a page at a time, and refuses a range it can't read", async () => {
  const first = await ask("timeline", { from: "2026-11-04", to: "2026-11-05", limit: 2 });
  expect([ids(first), first.nextCursor]).toEqual([[ID(3), ID(2)], `1793811700000.${ID(2)}`]);
  expect(await ask("timeline", { from: "2026-11-04", to: "2026-11-05", cursor: first.nextCursor })).toMatchObject({ notes: [{ id: ID(1) }], nextCursor: null });
  expect(ids(await ask("timeline", { from: "2026-11-04T13:00:00Z", to: "2026-11-04T17:01:40Z" }))).toEqual([ID(1)]);
  expect(await ask("timeline", { from: "yesterday", to: "2026-11-05" })).toEqual({ refused: "Give `from` and `to` as a day or an ISO time." });
  expect(await ask("timeline", { from: "2026-11-05", to: "2026-11-04" })).toEqual({ refused: "`from` must come before `to`." });
  expect((await ask("timeline", { from: "2026-11-04", to: "2026-11-05", timezone: "Mars/Olympus" })).refused).toContain("Not a time zone.");
  expect((await ask("timeline", { from: "2026-11-04", to: "2026-11-05", limit: 101 })).refused).toBeDefined();
});

it("never reads past `to`, even with a cursor from a later page", async () => {
  const later = (await ask("timeline", { from: "2026-11-04", to: "2026-11-05", limit: 1 })).nextCursor;
  expect(later).toBe(`1793829500000.${ID(3)}`);
  // ID(2) is at 12:01:40, after `to`, but before the cursor.
  expect(ids(await ask("timeline", { from: "2026-11-04", to: "2026-11-04T12:00", cursor: later }))).toEqual([ID(1)]);
  expect(ids(await ask("search", { query: "the", to: "2026-11-04T12:00", cursor: later }))).toEqual([ID(1)]);
});

it("reads one note with the places near it and its day's health", async () => {
  expect(await ask("fetch", { id: ID(1) })).toMatchObject({ id: ID(1), title: "Call the PCB fab about the second batch.",
    place: { name: "Harbord St", from: "history" }, placesNearby: [harbord], day: { day: "2026-11-04", ...day } });
  expect(await ask("fetch", { id: ID(9) })).toEqual({ refused: "No note has this id." });
});

it("sums up a day, and an empty one", async () => {
  expect(await ask("day_summary", { day: "2026-11-04" })).toEqual({ day: "2026-11-04", timezone: "America/Toronto", notes: 3, ...day, places: [
    { name: "Harbord St", lat: 43.6629, lon: -79.3957, from: "2026-11-04T08:00:00-05:00", to: "2026-11-04T08:00:00-05:00" },
    { name: "King St W", lat: 43.6487, lon: -79.3817, from: "2026-11-04T12:00:00-05:00", to: "2026-11-04T12:00:00-05:00" },
    { name: "Kensington Ave", lat: 43.6544, lon: -79.4006, from: "2026-11-04T17:00:00-05:00", to: "2026-11-04T17:30:00-05:00" }] });
  expect(await ask("day_summary", { day: "2026-11-05" })).toMatchObject({ notes: 0, steps: 0, sleepMinutes: 0, heartRate: null,
    workouts: { count: 0, minutes: 0 }, places: [] });
  expect((await ask("day_summary", { day: "2026-13-45" })).refused).toContain("Not a day.");
});

it("reads health by the hour or the day, and refuses too many values", async () => {
  const steps = await ask("health", { type: "steps", from: "2026-11-04T07:00", to: "2026-11-04T10:00", bucket: "hour" });
  expect(steps.values).toEqual([{ from: "2026-11-04T07:00:00-05:00", to: "2026-11-04T08:00:00-05:00", total: 0 },
    { from: "2026-11-04T08:00:00-05:00", to: "2026-11-04T09:00:00-05:00", total: 5210 },
    { from: "2026-11-04T09:00:00-05:00", to: "2026-11-04T10:00:00-05:00", total: 0 }]);
  const heart = await ask("health", { type: "heart_rate", from: "2026-11-03", to: "2026-11-05" });
  expect(heart).toMatchObject({ type: "heart_rate", bucket: "day", timezone: "America/Toronto" });
  expect(heart.values.map(({ min, max, average }: Record<string, number | null>) => [min, max, average])).toEqual([[null, null, null], [68, 121, 95]]);
  expect((await ask("health", { type: "sleep", from: "2026-11-04", to: "2026-11-05" })).values[0].total).toBe(450);
  expect((await ask("health", { type: "workout", from: "2026-11-04", to: "2026-11-05" })).values[0]).toMatchObject({ count: 1, minutes: 40 });
  // Toronto's clocks went back on 1 November, so that day bucket is 25 hours long.
  expect((await ask("health", { type: "steps", from: "2026-10-31", to: "2026-11-03" })).values.map((value: { from: string }) => value.from))
    .toEqual(["2026-10-31T00:00:00-04:00", "2026-11-01T00:00:00-04:00", "2026-11-02T00:00:00-05:00"]);
  expect(await ask("health", { type: "steps", from: "2026-01-01", to: "2026-03-01", bucket: "hour" }))
    .toEqual({ refused: "That is more than 400 hours: ask for a shorter range or a larger bucket." });
});

it("lists visits in order, one per stay at a place, and says where to read on", async () => {
  const all = await ask("places", { from: "2026-11-04", to: "2026-11-05" });
  expect(all).toEqual({ next: null, visits: [harbord,
    { name: "King St W", lat: 43.6487, lon: -79.3817, arrived: "2026-11-04T12:00:00-05:00", left: "2026-11-04T12:00:00-05:00" },
    { name: "Kensington Ave", lat: 43.6544, lon: -79.4006, arrived: "2026-11-04T17:00:00-05:00", left: "2026-11-04T17:30:00-05:00" }] });
  expect(await ask("places", { from: "2026-11-04", to: "2026-11-05", limit: 2 })).toMatchObject({ next: "2026-11-04T17:00:00-05:00" });
});

const CHAT = (n: number) => `c0000000-0000-4000-8000-00000000000${n}`;

it("finds saved chats holding every word, with the matching lines and no device or session id", async () => {
  const found = await ask("search_chats", { query: "stiffener" });
  expect(found).toEqual({ nextCursor: null, chats: [{ id: CHAT(1), title: "Stiffener plan", project: "relay-ring", app: "claude-code",
    startedAt: "2026-11-04T09:00:00-05:00", lastAt: "2026-11-04T09:10:00-05:00", messages: 4, savedByAi: true,
    lines: [{ role: "you", text: "How thick should the stiffener be?" }, { role: "you", text: "Save the plan for the stiffener to Relay" }] }] });
  expect(JSON.stringify(found)).not.toMatch(/seed-session|d0000000|device/);
  // A word in the AI's summary alone finds the chat too; every word must match.
  expect((await ask("search_chats", { query: "soldered" })).chats.map((chat: { id: string }) => chat.id)).toEqual([CHAT(1)]);
  expect((await ask("search_chats", { query: "stiffener webhook" })).chats).toEqual([]);
  const first = await ask("search_chats", { query: "the", limit: 1 });
  expect([first.chats[0].id, first.nextCursor]).toEqual([CHAT(2), `1793816100000.${CHAT(2)}`]);
  expect((await ask("search_chats", { query: "the", cursor: first.nextCursor })).chats.map((chat: { id: string }) => chat.id)).toEqual([CHAT(1)]);
  expect((await ask("search_chats", { query: "the", to: "2026-11-04T12:00" })).chats.map((chat: { id: string }) => chat.id)).toEqual([CHAT(1)]);
});

it("cuts a long matching line around the word", async () => {
  const { sql, SPACES } = seeded();
  sql.exec(`INSERT INTO relay_chat_messages (chat_id, seq, role, text, at) VALUES ('${CHAT(2)}', 3, 'ai', '${"a".repeat(500)} needle ${"b".repeat(500)}', 1793816200000)`);
  client = await connect(SPACES);
  const [{ lines }] = (await ask("search_chats", { query: "needle" })).chats;
  expect(lines[0].text).toMatch(/^…a+ needle b+…$/);
  expect(lines[0].text.length).toBe(302);
  client = await connect(seeded().SPACES);
});

it("reads one chat with its saves and messages, a part at a time", async () => {
  const chat = await ask("read_chat", { id: CHAT(1) });
  expect(chat).toMatchObject({ id: CHAT(1), title: "Stiffener plan", nextCursor: null,
    saves: [{ title: "Stiffener plan", text: "Use a 0.2 mm steel stiffener under the battery, glued, not soldered.", createdAt: "2026-11-04T09:11:00-05:00" }] });
  expect(chat.messages.map((message: { role: string; text: string }) => [message.role, message.text])).toEqual([
    ["you", "How thick should the stiffener be?"], ["step", "Read pcb/relay.kicad_pcb"],
    ["ai", "0.2 mm steel is enough for a ring this size. Glue it under the battery."], ["you", "Save the plan for the stiffener to Relay"]]);
  expect(JSON.stringify(chat)).not.toMatch(/seed-session|d0000000/);
  const { sql, SPACES } = seeded();
  const insert = sql.prepare(`INSERT INTO relay_chat_messages (chat_id, seq, role, text, at) VALUES ('${CHAT(2)}', ?, 'you', 'More', 1793816200000)`);
  for (let seq = 3; seq < 250; seq++) insert.run(seq);
  client = await connect(SPACES);
  const first = await ask("read_chat", { id: CHAT(2) });
  expect([first.messages.length, first.nextCursor]).toEqual([200, "199"]);
  const rest = await ask("read_chat", { id: CHAT(2), cursor: first.nextCursor });
  expect([rest.messages.length, rest.messages[0].text, rest.nextCursor]).toEqual([50, "More", null]);
  expect(await ask("read_chat", { id: CHAT(2), cursor: "page-2" })).toEqual({ refused: "That cursor is not one this connector gave." });
  expect(await ask("read_chat", { id: CHAT(9) })).toEqual({ refused: "No chat has this id." });
  client = await connect(seeded().SPACES);
});

it("titles a note with no words, and lets a database fault through as an error, not as an answer", async () => {
  const { sql, SPACES } = seeded();
  sql.exec(`INSERT INTO relay_notes (id, device_id, source, delivery_id, text, recorded_at, created_at) VALUES
    ('${ID(8)}', 'd0000000-0000-4000-8000-000000000002', 'ring', 'empty-delivery', '', 1793900000000, 0)`);
  client = await connect(SPACES);
  expect((await ask("fetch", { id: ID(8) })).title).toBe("A ring note with no words");
  client = await connect({ idFromName: () => ({}), get: () => ({ query: async () => { throw new Error("The space is down"); } }) } as never);
  const { content, isError } = await client.callTool({ name: "fetch", arguments: { id: ID(1) } }) as { content: { text: string }[]; isError?: boolean };
  expect([isError, content[0].text]).toEqual([true, expect.stringContaining("The space is down")]);
  client = await connect(seeded().SPACES);
});

it("reads only the grant's own person's space, and asks an app from before spaces to connect again", async () => {
  const { SPACES } = seeded();
  const ben = await connect(SPACES, { personId: BEN });
  const found = JSON.parse((await ben.callTool({ name: "search", arguments: { query: "milk" } }) as { content: { text: string }[] }).content[0].text);
  expect(found.notes.map((note: { id: string }) => note.id)).toEqual([ID(7)]);
  expect(ids(await ask("search", { query: "ring" }))).not.toContain(ID(7));
  const old = await mcpHandler.fetch(new Request("https://relay-mcp.example.com/mcp", { method: "POST" }), { SPACES, RELAY_WEBHOOKS: queue as never }, { props: {} });
  expect([old.status, await old.json()]).toEqual([401, { error: "invalid_token", error_description: "Connect this AI app again." }]);
});

it("adds a note as the app's own device, once on a resend, and wakes the webhooks that take notes", async () => {
  const { sql, SPACES } = seeded();
  sql.exec(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, sent_seq, created_at)
    VALUES ('w-notes', 'Example database', 'https://db.example.com/relay', 'whsec_AAAA', '["notes"]', 0, 0)`);
  client = await connect(SPACES);
  const note = { clientId: "claude-note-0001", text: "Order the second PCB batch.", createdAt: "2026-11-04T18:00" };
  const first = await ask("add_note", note);
  expect(first).toEqual({ id: expect.stringMatching(/^[0-9a-f-]{36}$/), added: true });
  expect(await ask("add_note", { ...note, text: "Changed on the resend." })).toEqual({ id: first.id, added: false });
  expect(queue.sent).toEqual([{ webhook: "w-notes", person: ANA }]);
  expect(sql.prepare("SELECT name, token_client_id, reaches, created_at, revoked_at FROM relay_devices WHERE id = ?").get(GRANT.deviceId!))
    .toEqual({ name: "Claude", token_client_id: `app:${GRANT.deviceId}`, reaches: "app", created_at: NOW, revoked_at: null });
  expect(await ask("fetch", { id: first.id })).toMatchObject({ text: "Order the second PCB batch.", source: "typed", device: "Claude",
    recordedAt: "2026-11-04T18:00:00-05:00", place: null });
  const placed = await ask("add_note", { clientId: "claude-note-0002", text: "At the fab.", lat: 43.65, lon: -79.38, place: "King St W" });
  expect(await ask("fetch", { id: placed.id })).toMatchObject({ recordedAt: "2026-11-05T09:00:00-05:00", place: { name: "King St W", from: "phone" } });
  expect(await ask("add_note", { clientId: "claude-note-0003", text: "Where?", lat: 43.65 })).toEqual({ refused: "Send lat and lon together." });
  expect(await ask("add_note", { clientId: "claude-note-0003", text: "When?", createdAt: "yesterday" }))
    .toEqual({ refused: "Give `createdAt` as a day or an ISO time." });
  expect((await ask("add_note", { clientId: "short", text: "Hi" })).refused).toContain("clientId");
  client = await connect(seeded().SPACES);
});

it("lets an app connected before adding read, but asks it to connect again to add", async () => {
  const { sql, SPACES } = seeded();
  client = await connect(SPACES, { personId: ANA });
  expect(ids(await ask("search", { query: "milk" }))).toEqual([ID(3)]);
  expect(await ask("add_note", { clientId: "claude-note-0001", text: "Hi" })).toEqual({ refused: RECONNECT });
  expect(sql.prepare("SELECT count(*) AS count FROM relay_notes").get()).toEqual({ count: 3 });
  client = await connect(seeded().SPACES);
});

// Only SELECT reaches a space from the connector, but for these writes: a used sign-in code, an app's device row and
// its turning off. A note is added only through add-note.ts; the one DELETE to Google takes an event off a calendar.
const WRITES = /\b(?:INSERT|UPDATE|DELETE|REPLACE|UPSERT|CREATE|DROP|ALTER|PRAGMA|ATTACH|VACUUM)\b|\b(?:db|DB)\.exec\(|\.(?:batch|run)\(/;
const writes = (source: string) => WRITES.test(source);

it("holds no statement but SELECT in the connector or its queries", () => {
  const folder = new URL(".", import.meta.url);
  const files = [...readdirSync(folder).filter(name => name.endsWith(".ts") && !name.endsWith(".test.ts")).map(name => new URL(name, folder)),
    new URL("../apps/relay/queries.ts", import.meta.url)];
  expect(files.length).toBeGreaterThan(5);
  const CODE_TAKEN = "DELETE FROM relay_connect_codes WHERE code_sha256 = ? AND expires_at > ? RETURNING person_id";
  const ALLOWED: Record<string, string[]> = { "auth.ts": [CODE_TAKEN],
    "answers.ts": [APP_DEVICE.slice(0, APP_DEVICE.indexOf("VALUES")), ".bind(adder.deviceId, adder.name, `app:${adder.deviceId}`, Date.now()).run()"],
    "asker.ts": [JSON.stringify(APP_DEVICE_OFF), "db.prepare(APP_DEVICE_OFF).bind(Date.now(), deviceId).run()"],
    "google-tools.ts": ['{ method: "DELETE", query: { sendUpdates: "all" } }'] };
  for (const file of files) {
    let source = readFileSync(file, "utf8");
    for (const allowed of ALLOWED[file.pathname.split("/").pop()!] ?? []) {
      expect(source, file.pathname).toContain(allowed);
      source = source.replace(allowed, "");
    }
    expect(writes(source), file.pathname).toBe(false);
  }
  for (const bad of ["INSERT INTO relay_notes", "db.exec('x')", "db.batch([])", "statement.run()"]) expect(writes(bad), bad).toBe(true);
});
