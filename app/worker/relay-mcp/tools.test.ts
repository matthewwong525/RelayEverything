import { readdirSync, readFileSync } from "node:fs";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { beforeAll, expect, it } from "vitest";
import { ANA, BEN, bucket, fakeSpaces, jpeg, NOW, queue } from "../../tests/relay";
import { spaceOf, vouch } from "../apps/relay/space";
import { APP_DEVICE, RECONNECT } from "./answers";
import { APP_DEVICE_OFF } from "./asker";
import type { GrantProps, McpEnv } from "./env";
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

/** The connector's spaces, file store and webhooks' queue, as its Worker binds them. */
const bindings = (SPACES: DurableObjectNamespace) => ({ SPACES, RELAY_BUCKET: bucket, RELAY_WEBHOOKS: queue } as unknown as McpEnv);

/** A grant as /callback makes it now: Ana's space, and adding notes as the app's own device. */
const GRANT: GrantProps = { personId: ANA, adds: true, deviceId: "e0000000-0000-4000-8000-000000000001", name: "Claude" };

/** An MCP client that reaches the connector with this grant. */
async function connect(SPACES: DurableObjectNamespace, props: GrantProps = GRANT) {
  const connected = new Client({ name: "test", version: "1.0.0" });
  await connected.connect(new StreamableHTTPClientTransport(new URL("https://relay-mcp.example.com/mcp"),
    { fetch: (url, init) => mcpHandler.fetch(new Request(url, init), bindings(SPACES), { props }) }));
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
const harbord = { name: "Harbord St", lat: 43.6629, lon: -79.3957, arrived: "2026-11-04T08:00:00-05:00", left: "2026-11-04T08:00:00-05:00", minutes: 0 };
const day = { steps: 8690, sleepMinutes: 450, heartRate: { min: 68, max: 121, average: 95 }, workouts: { count: 1, minutes: 40 } };
const run = { kind: "running", start: "2026-11-04T13:00:00-05:00", end: "2026-11-04T13:40:00-05:00", minutes: 40, km: 5.1, calories: 410,
  source: "com.google.android.apps.fitness", device: "Android phone" };
const night = { start: "2026-11-03T23:40:00-05:00", end: "2026-11-04T07:30:00-05:00", asleepAt: "2026-11-04T00:00:00-05:00",
  wokeAt: "2026-11-04T07:25:00-05:00", minutes: { asleep: 425, core: 250, deep: 80, rem: 95, awake: 25 },
  source: "com.google.android.apps.fitness", device: "Android phone" };

it("names itself Relay Everything to the AI app", () => {
  expect(client.getServerVersion()).toMatchObject({ name: "relay", title: "Relay Everything" });
  expect(client.getInstructions()).toMatch(/^Relay Everything /);
});

it("lists seventeen tools, each read-only but add_note, which changes and deletes nothing", async () => {
  const { tools } = await client.listTools();
  expect(tools.map(tool => tool.name)).toEqual(["search", "fetch", "timeline", "day_summary", "health", "nights", "workouts", "places",
    "points", "calendar", "search_chats", "read_chat", "photos", "read_photo", "memory", "read_fact", "add_note"]);
  for (const tool of tools.slice(0, 16)) expect(tool.annotations).toMatchObject({ readOnlyHint: true, destructiveHint: false });
  expect(tools[16].annotations).toMatchObject({ readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false });
  expect(client.getInstructions()).toContain("search the memory first");
});

it("answers what the person decided from the live facts, reads a replaced one, and changes no fact", async () => {
  const { sql, SPACES } = seeded();
  client = await connect(SPACES);
  const before = sql.prepare("SELECT * FROM relay_memory ORDER BY id").all();
  const found = await ask("memory", { query: "battery" });
  expect(found.facts).toEqual([{ id: "fc5kk", fields: { kind: "decision", text: "The battery is now 50 mAh, for a full day." },
    tags: ["battery", "ring/charging"], sources: [`relay:chat/${CHAT(2)}#2`], replaces: ["fb4tt"], replacedBy: null, device: "Laptop",
    createdAt: "2026-11-04T13:16:40-05:00" }]);
  expect(found.columns.map((column: { name: string }) => column.name)).toEqual(["kind", "text"]);
  expect((await ask("memory", { tag: "battery", all: true })).facts.map((fact: { id: string }) => fact.id)).toEqual(["fc5kk", "fb4tt"]);
  expect((await ask("memory", { where: { kind: "fact" } })).facts.map((fact: { id: string }) => fact.id)).toEqual(["fd7mm"]);
  expect(await ask("read_fact", { id: "fb4tt" })).toMatchObject({ replacedBy: "fc5kk", replacedByFact: { id: "fc5kk" }, replacedFacts: [] });
  expect(await ask("read_fact", { id: "fzzzz" })).toEqual({ refused: "No fact has this id." });
  expect(ids(await ask("search", { tag: "ring/charging" }))).toEqual([ID(3)]);
  expect(await ask("search", {})).toEqual({ refused: "Give the words to find, a tag, or both." });
  expect(sql.prepare("SELECT * FROM relay_memory ORDER BY id").all()).toEqual(before);
  client = await connect(seeded().SPACES);
});

it("finds notes holding every word, in any case, with a title and the time in the zone", async () => {
  expect(await ask("search", { query: "milk" })).toEqual({ nextCursor: null, notes: [{ id: ID(3), source: "ring",
    text: "Buy milk and batteries.", title: "Buy milk and batteries.", recordedAt: "2026-11-04T16:58:20-05:00", device: "iPad",
    audio: false, attachments: [] }] });
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

it("reads one note with no place of its own, the places near it by time and its day's health", async () => {
  const note = await ask("fetch", { id: ID(1) });
  expect(note).toMatchObject({ id: ID(1), title: "Call the PCB fab about the second batch.", placesNearby: [harbord],
    day: { day: "2026-11-04", ...day } });
  expect(note).not.toHaveProperty("place");
  expect(await ask("fetch", { id: ID(9) })).toEqual({ refused: "No note has this id." });
});

it("sums up a day, and an empty one", async () => {
  expect(await ask("day_summary", { day: "2026-11-04" })).toEqual({ day: "2026-11-04", timezone: "America/Toronto", notes: 3, ...day,
    workouts: { ...day.workouts, items: [run] }, nights: [night], places: [
    { name: "Harbord St", lat: 43.6629, lon: -79.3957, from: "2026-11-04T08:00:00-05:00", to: "2026-11-04T08:00:00-05:00" },
    { name: "King St W", lat: 43.6487, lon: -79.3817, from: "2026-11-04T12:00:00-05:00", to: "2026-11-04T12:00:00-05:00" },
    { name: "Kensington Ave", lat: 43.6544, lon: -79.4006, from: "2026-11-04T17:00:00-05:00", to: "2026-11-04T17:30:00-05:00" }],
    weightKg: 71.4, bloodPressure: [{ at: "2026-11-04T08:30:00-05:00", upper: 118, lower: 76 }], events: [
      { title: "Board meeting", start: "2026-11-04T10:00:00-05:00", end: "2026-11-04T11:00:00-05:00", allDay: false, people: ["Sam Lee", "Ana"] },
      { title: "Lunch with Sam", start: "2026-11-04T12:00:00-05:00", end: "2026-11-04T13:00:00-05:00", allDay: false, people: ["Sam Lee"] }],
    trips: [] });
  expect(await ask("day_summary", { day: "2026-11-05" })).toMatchObject({ notes: 0, steps: 0, sleepMinutes: 0, heartRate: null,
    workouts: { count: 0, minutes: 0, items: [] }, nights: [], places: [], trips: [] });
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

it("reads the new health types: the day's latest weight and blood pressure's range", async () => {
  expect((await ask("health", { type: "weight", from: "2026-11-03", to: "2026-11-05" })).values.map((value: { latest: number | null }) => value.latest))
    .toEqual([null, 71.4]);
  expect((await ask("health", { type: "blood_pressure_systolic", from: "2026-11-04", to: "2026-11-05" })).values[0])
    .toMatchObject({ min: 118, max: 118, average: 118 });
  expect((await ask("health", { type: "water", from: "2026-11-04", to: "2026-11-05" })).values[0].total).toBe(0);
});

it("reads nights newest first, the one with the most sleep of two that overlap, with stages only when asked", async () => {
  const first = await ask("nights", { from: "2026-11-01", to: "2026-11-05", limit: 1 });
  expect(first).toEqual({ nights: [night], nextCursor: "1793767200001" });
  expect((await ask("nights", { from: "2026-11-01", to: "2026-11-05", cursor: first.nextCursor })).nights).toEqual([{
    start: "2026-11-02T23:30:00-05:00", end: "2026-11-03T07:00:00-05:00", asleepAt: null, wokeAt: null,
    minutes: { asleep: 0, core: 0, deep: 0, rem: 0, awake: 0 }, source: "com.urbandroid.sleep", device: "Android phone" }]);
  expect((await ask("nights", { from: "2026-11-04", to: "2026-11-05", stages: true })).nights[0].stages).toEqual([
    { stage: "awake", start: "2026-11-03T23:40:00-05:00", end: "2026-11-04T00:00:00-05:00" },
    { stage: "core", start: "2026-11-04T00:00:00-05:00", end: "2026-11-04T02:00:00-05:00" },
    { stage: "deep", start: "2026-11-04T02:00:00-05:00", end: "2026-11-04T03:20:00-05:00" }]);
  expect(await ask("nights", { from: "2026-11-01", to: "2026-11-05", cursor: "page-2" })).toEqual({ refused: "That cursor is not one this connector gave." });
  expect((await ask("nights", { from: "2026-11-01", to: "2026-11-05", limit: 101 })).refused).toBeDefined();
});

it("reads workouts newest first, with their kind, km and calories", async () => {
  const walk = { kind: null, start: "2026-11-07T10:20:00-05:00", end: "2026-11-07T10:40:00-05:00", minutes: 20, km: null, calories: null,
    source: "com.google.android.apps.fitness", device: "Android phone" };
  expect(await ask("workouts", { from: "2026-11-01", to: "2026-11-08" })).toEqual({ workouts: [walk, run], nextCursor: null });
  const first = await ask("workouts", { from: "2026-11-01", to: "2026-11-08", limit: 1 });
  expect(first).toEqual({ workouts: [walk], nextCursor: "1794064740001" });
  expect(await ask("workouts", { from: "2026-11-01", to: "2026-11-08", cursor: first.nextCursor })).toEqual({ workouts: [run], nextCursor: null });
  expect(await ask("workouts", { from: "2026-11-05", to: "2026-11-07" })).toEqual({ workouts: [], nextCursor: null });
});

it("reads calendar events by time or words, never a removed one, a page at a time", async () => {
  const titles = (answer: { events: { title: string }[] }) => answer.events.map(event => event.title);
  const day = await ask("calendar", { from: "2026-11-04", to: "2026-11-05" });
  expect(titles(day)).toEqual(["Board meeting", "Lunch with Sam"]);
  expect(day.events[0]).toEqual({ id: expect.any(String), title: "Board meeting", calendar: "Work", start: "2026-11-04T10:00:00-05:00",
    end: "2026-11-04T11:00:00-05:00", allDay: false, location: "Office, room 2", notes: "Bring the ring samples.", url: null,
    people: [{ name: "Sam Lee", email: "sam@example.com", organizer: true }, { name: "Ana" }], device: "Android phone" });
  expect(titles(await ask("calendar", { from: "2026-11-01", to: "2026-12-01", query: "sam" }))).toEqual(["Design review with Sam", "Lunch with Sam", "Board meeting"]);
  expect(titles(await ask("calendar", { from: "2026-11-04T10:30", to: "2026-11-04T10:45" }))).toEqual(["Board meeting"]);
  const newest = await ask("calendar", { from: "2026-11-01", to: "2026-12-01", query: "sam", limit: 2 });
  expect(titles(await ask("calendar", { from: "2026-11-01", to: "2026-12-01", query: "sam", cursor: newest.nextCursor }))).toEqual(["Board meeting"]);
  const first = await ask("calendar", { from: "2026-11-01", to: "2026-12-01", limit: 1 });
  expect(titles(first)).toEqual(["Board meeting"]);
  expect(titles(await ask("calendar", { from: "2026-11-01", to: "2026-12-01", cursor: first.nextCursor }))).toEqual(["Lunch with Sam", "Design review with Sam"]);
  expect((await ask("calendar", { from: "2026-11-01", to: "2026-12-01", limit: 101 })).refused).toBeDefined();
  expect(await ask("calendar", { from: "2026-11-01", to: "2026-12-01", cursor: "page-2" })).toEqual({ refused: "That cursor is not one this connector gave." });
});

it("lists visits in order, one per stay at a place, and says where to read on", async () => {
  const all = await ask("places", { from: "2026-11-04", to: "2026-11-05" });
  expect(all).toEqual({ next: null, trips: [], visits: [harbord,
    { name: "King St W", lat: 43.6487, lon: -79.3817, arrived: "2026-11-04T12:00:00-05:00", left: "2026-11-04T12:00:00-05:00", minutes: 0 },
    { name: "Kensington Ave", lat: 43.6544, lon: -79.4006, arrived: "2026-11-04T17:00:00-05:00", left: "2026-11-04T17:30:00-05:00", minutes: 30 }] });
  expect(await ask("places", { from: "2026-11-04", to: "2026-11-05", limit: 2 })).toMatchObject({ next: "2026-11-04T17:00:00-05:00" });
});

it("answers where you went on a Saturday with its stays, by name, and the trips between them", async () => {
  const places = await ask("places", { from: "2026-11-07", to: "2026-11-08" });
  expect(places.visits.map((visit: { name: string; arrived: string }) => [visit.name, visit.arrived])).toEqual([
    ["12 Maple Street", "2026-11-07T07:00:00-05:00"], ["Corner Café", "2026-11-07T09:15:00-05:00"], ["Smile Dental", "2026-11-07T10:40:00-05:00"]]);
  expect(places.visits[2]).toEqual({ id: 5, name: "Smile Dental", lat: 43.67, lon: -79.4, arrived: "2026-11-07T10:40:00-05:00",
    left: "2026-11-07T11:30:00-05:00", minutes: 50, address: "Park Lane", event: "Dentist", ongoing: true });
  expect(places.trips).toEqual([
    { id: 2, left: "2026-11-07T09:00:00-05:00", arrived: "2026-11-07T09:15:00-05:00", mode: "driving", km: 6.2, minutes: 15, from: "12 Maple Street", to: "Corner Café" },
    { id: 4, left: "2026-11-07T10:20:00-05:00", arrived: "2026-11-07T10:40:00-05:00", mode: "walking", km: 1.4, minutes: 20, from: "Corner Café", to: "Smile Dental" }]);
  const day = await ask("day_summary", { day: "2026-11-07" });
  expect(day.places.map((place: { name: string; from: string; to: string }) => [place.name, place.from, place.to])).toEqual([
    ["12 Maple Street", "2026-11-07T07:00:00-05:00", "2026-11-07T09:00:00-05:00"], ["Corner Café", "2026-11-07T09:15:00-05:00", "2026-11-07T10:20:00-05:00"],
    ["Smile Dental", "2026-11-07T10:40:00-05:00", "2026-11-07T11:30:00-05:00"]]);
  expect(day.trips.map((trip: { mode: string }) => trip.mode)).toEqual(["driving", "walking"]);
  expect([day.places.map((place: { id: number }) => place.id), day.trips.map((trip: { id: number }) => trip.id)]).toEqual([[1, 3, 5], [2, 4]]);
});

const times = (answer: { points: { at: string }[] }) => answer.points.map(point => point.at.slice(11, 16));

it("reads a trip's route by its id, a stay's points from its own phone only, and every phone's points in a range", async () => {
  expect(await ask("points", { id: 2 })).toEqual({ id: 2, kind: "trip", from: "2026-11-07T09:00:00-05:00", to: "2026-11-07T09:15:00-05:00",
    timezone: "America/Toronto", total: 4, points: [
      { at: "2026-11-07T09:02:00-05:00", lat: 43.652, lon: -79.382, accuracy: 8, place: "Maple St" },
      { at: "2026-11-07T09:06:00-05:00", lat: 43.655, lon: -79.385, accuracy: 9, place: "Queen St W" },
      { at: "2026-11-07T09:10:00-05:00", lat: 43.658, lon: -79.388, accuracy: 11 },
      { at: "2026-11-07T09:14:00-05:00", lat: 43.6595, lon: -79.3895, accuracy: 8, place: "Lake Drive" }] });
  // The iPad's point at 09:45 is in the café stay's time, but the phone made the stay.
  expect(times(await ask("points", { id: 3 }))).toEqual(["09:30", "10:00"]);
  const range = await ask("points", { from: "2026-11-07T09:00", to: "2026-11-07T10:00" });
  expect([range.id, range.kind, range.from, range.total, times(range)])
    .toEqual([undefined, undefined, "2026-11-07T09:00:00-05:00", 6, ["09:02", "09:06", "09:10", "09:14", "09:30", "09:45"]]);
  expect(JSON.stringify(range)).not.toMatch(/d0000000|device|iPad/);
  // Toronto's clocks went back on 1 November, so this week is 169 hours, and still 7 days.
  expect((await ask("points", { from: "2026-11-01", to: "2026-11-08" })).total).toBe(15);
  expect(await ask("points", { from: "2026-11-05", to: "2026-11-06" })).toMatchObject({ total: 0, points: [] });
});

it("refuses points asked by neither id nor range, by both, past 7 days, or for an id no stay or trip has", async () => {
  const either = { refused: "Give the `id` of a stay or trip, or `from` and `to`: one or the other." };
  for (const input of [{}, { id: 2, from: "2026-11-07" }, { from: "2026-11-07" }, { id: 2, to: "2026-11-08" }]) {
    expect(await ask("points", input), JSON.stringify(input)).toEqual(either);
  }
  expect(await ask("points", { from: "2026-11-01", to: "2026-11-09" })).toEqual({ refused: "That is more than 7 days: ask for a shorter range." });
  expect(await ask("points", { id: 99 })).toEqual({ refused: "No stay or trip has this id." });
  expect((await ask("points", { id: 0 })).refused).toBeDefined();
});

const CHAT = (n: number) => `c0000000-0000-4000-8000-00000000000${n}`;

it("finds saved chats holding every word, with the matching lines and no device or session id", async () => {
  const found = await ask("search_chats", { query: "stiffener" });
  expect(found).toEqual({ nextCursor: null, chats: [{ id: CHAT(1), title: "Stiffener plan", project: "relay-ring", app: "claude-code",
    startedAt: "2026-11-04T09:00:00-05:00", lastAt: "2026-11-04T09:10:00-05:00", messages: 4, savedByAi: true, memory: false,
    lines: [{ role: "you", text: "How thick should the stiffener be?" }, { role: "you", text: "Save the plan for the stiffener to Relay" }] }] });
  expect(JSON.stringify(found)).not.toMatch(/seed-session|d0000000|device/);
  // A word in the AI's summary alone finds the chat too; every word must match.
  expect((await ask("search_chats", { query: "soldered" })).chats.map((chat: { id: string }) => chat.id)).toEqual([CHAT(1)]);
  expect((await ask("search_chats", { query: "stiffener webhook" })).chats).toEqual([]);
  const first = await ask("search_chats", { query: "the", limit: 1 });
  expect([first.chats[0].id, first.nextCursor]).toEqual([CHAT(2), `1793816100000.${CHAT(2)}`]);
  expect((await ask("search_chats", { query: "the", cursor: first.nextCursor })).chats.map((chat: { id: string }) => chat.id)).toEqual([CHAT(1)]);
  expect((await ask("search_chats", { query: "the", to: "2026-11-04T12:00" })).chats.map((chat: { id: string }) => chat.id)).toEqual([CHAT(1)]);
  expect((await ask("search_chats", { query: "dark mode" })).chats).toMatchObject([{ id: CHAT(3), app: "codex" }]);
});

it("lists every chat active in a week with no words, newest first, a page at a time, with no lines", async () => {
  const week = { from: "2026-11-01", to: "2026-11-08" };
  const all = await ask("search_chats", week);
  expect(all.chats.map((chat: { id: string; messages: number; lines: unknown[] }) => [chat.id, chat.messages, chat.lines]))
    .toEqual([[CHAT(2), 3, []], [CHAT(1), 4, []], [CHAT(3), 2, []]]);
  expect(all.chats[0].lastAt).toBe("2026-11-04T13:15:00-05:00");
  const first = await ask("search_chats", { ...week, limit: 2 });
  expect([first.chats.length, first.nextCursor]).toEqual([2, `1793801400000.${CHAT(1)}`]);
  expect((await ask("search_chats", { ...week, cursor: first.nextCursor })).chats.map((chat: { id: string }) => chat.id)).toEqual([CHAT(3)]);
  expect((await ask("search_chats", { ...week, query: "stiffener" })).chats.map((chat: { id: string }) => chat.id)).toEqual([CHAT(1)]);
  expect((await ask("search_chats", { from: "2026-11-05", to: "2026-11-08" })).chats).toEqual([]);
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
  expect((await ask("fetch", { id: ID(8) })).title).toBe("A recorded note with no words");
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
  const old = await mcpHandler.fetch(new Request("https://relay-mcp.example.com/mcp", { method: "POST" }), bindings(SPACES), { props: {} });
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
    recordedAt: "2026-11-04T18:00:00-05:00" });
  // A place sent with a note becomes one point of the app's device at the note's time, which fetch finds by time.
  const placed = await ask("add_note", { clientId: "claude-note-0002", text: "At the fab.", lat: 43.65, lon: -79.38, place: "King St W" });
  const fetched = await ask("fetch", { id: placed.id });
  expect(fetched).toMatchObject({ recordedAt: "2026-11-05T09:00:00-05:00", placesNearby: [{ name: "King St W", lat: 43.65, lon: -79.38 }] });
  expect(fetched).not.toHaveProperty("place");
  expect(sql.prepare("SELECT device_id, at, accuracy, place FROM relay_locations WHERE place = 'King St W' AND at = ?").all(NOW))
    .toEqual([{ device_id: GRANT.deviceId, at: NOW, accuracy: 0, place: "King St W" }]);
  expect(await ask("add_note", { clientId: "claude-note-0003", text: "Where?", lat: 43.65 })).toEqual({ refused: "Send lat and lon together." });
  expect(await ask("add_note", { clientId: "claude-note-0003", text: "When?", createdAt: "yesterday" }))
    .toEqual({ refused: "Give `createdAt` as a day or an ISO time." });
  expect((await ask("add_note", { clientId: "short", text: "Hi" })).refused).toContain("clientId");
  client = await connect(seeded().SPACES);
});

it("names an emailed note's device Email", async () => {
  const { sql, SPACES } = seeded();
  sql.exec(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, reaches) VALUES ('d-mail', 'Email', 'inbox:email', '', 0, 'inbox');
    INSERT INTO relay_notes (id, device_id, source, client_id, text, recorded_at, created_at)
    VALUES ('${ID(9)}', 'd-mail', 'typed', 'email:seed-mail-0001', 'Fwd: Your receipt', 1793900000000, 0)`);
  client = await connect(SPACES);
  expect(await ask("fetch", { id: ID(9) })).toMatchObject({ text: "Fwd: Your receipt", source: "typed", device: "Email" });
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


const PHOTO = (n: number) => `f0000000-0000-4000-8000-00000000000${n}`;
const photoIds = (answer: { photos: { id: string }[] }) => answer.photos.map(photo => photo.id);

it("lists photos newest first, a page at a time, and only those near a place when asked", async () => {
  const all = await ask("photos", { from: "2026-11-04", to: "2026-11-05" });
  expect(all).toEqual({ nextCursor: null, photos: [
    { id: PHOTO(3), takenAt: "2026-11-04T17:06:40-05:00", lat: 43.6544, lon: -79.4006, width: 1600, height: 900 },
    { id: PHOTO(2), takenAt: "2026-11-04T14:20:00-05:00", lat: null, lon: null, width: 1200, height: 1600 },
    { id: PHOTO(1), takenAt: "2026-11-04T12:05:00-05:00", lat: 43.6487, lon: -79.3817, width: 1600, height: 1200 }] });
  expect(JSON.stringify(all)).not.toMatch(/people\/|file|seed-photo|d0000000/);
  const first = await ask("photos", { from: "2026-11-04", to: "2026-11-05", limit: 2 });
  expect([photoIds(first), first.nextCursor]).toEqual([[PHOTO(3), PHOTO(2)], `1793820000000.${PHOTO(2)}`]);
  expect(photoIds(await ask("photos", { from: "2026-11-04", to: "2026-11-05", cursor: first.nextCursor }))).toEqual([PHOTO(1)]);
  // King St W and Kensington Ave are about 1.7 km apart.
  const near = (km: number) => ask("photos", { from: "2026-11-04", to: "2026-11-05", near: { lat: 43.6487, lon: -79.3817, km } });
  expect(photoIds(await near(0.5))).toEqual([PHOTO(1)]);
  expect(photoIds(await near(3))).toEqual([PHOTO(3), PHOTO(1)]);
  expect((await near(501)).refused).toBeDefined();
  expect((await ask("photos", { from: "2026-11-04", to: "2026-11-05", limit: 51 })).refused).toBeDefined();
  expect(photoIds(await ask("photos", { from: "2026-11-05", to: "2026-11-06" }))).toEqual([]);
});

it("shows one photo as an image with a line of its time and place, and refuses an id it lacks", async () => {
  const { SPACES } = seeded();
  const { files } = spaceOf(bindings(SPACES), vouch("grant", ANA));
  await files.put(`photos/${PHOTO(1)}`, jpeg(1600, 1200).buffer);
  await files.put(`photos/${PHOTO(2)}`, jpeg(1200, 1600).buffer);
  client = await connect(SPACES);
  const { content, isError } = await client.callTool({ name: "read_photo", arguments: { id: PHOTO(1) } }) as
    { content: { type: string; data?: string; mimeType?: string; text?: string }[]; isError?: boolean };
  expect(isError).toBeFalsy();
  expect(content).toEqual([{ type: "image", data: Buffer.from(jpeg(1600, 1200)).toString("base64"), mimeType: "image/jpeg" },
    { type: "text", text: `Photo ${PHOTO(1)}, taken 2026-11-04T12:05:00-05:00 at 43.6487, -79.3817, 1600 × 1200 pixels.` }]);
  const placeless = await client.callTool({ name: "read_photo", arguments: { id: PHOTO(2), timezone: "Europe/London" } }) as { content: { text?: string }[] };
  expect(placeless.content[1].text).toBe(`Photo ${PHOTO(2)}, taken 2026-11-04T19:20:00+00:00, with no place, 1200 × 1600 pixels.`);
  // A row whose file is gone, an id it lacks, and Ben's grant on Ana's photo all get no photo.
  expect(await ask("read_photo", { id: PHOTO(3) })).toEqual({ refused: "No photo has this id." });
  expect(await ask("read_photo", { id: PHOTO(9) })).toEqual({ refused: "No photo has this id." });
  const ben = await connect(SPACES, { personId: BEN });
  const refused = await ben.callTool({ name: "read_photo", arguments: { id: PHOTO(1) } }) as { content: { text: string }[]; isError?: boolean };
  expect([refused.isError, refused.content[0].text]).toEqual([true, "No photo has this id."]);
  client = await connect(seeded().SPACES);
});

// Only SELECT reaches a space from the connector, but for these writes: a used sign-in code, an app's device row and
// its turning off. A note is added only through apps/relay/add-note.ts; agents' commands go to their own database.
const WRITES = /\b(?:INSERT|UPDATE|DELETE|REPLACE|UPSERT|CREATE|DROP|ALTER|PRAGMA|ATTACH|VACUUM)\b|\b(?:db|DB)\.exec\(|\.(?:batch|run)\(/;
const writes = (source: string) => WRITES.test(source);

it("holds no statement but SELECT in the connector or its queries", () => {
  const folder = new URL(".", import.meta.url);
  const files = [...readdirSync(folder).filter(name => name.endsWith(".ts") && !name.endsWith(".test.ts")).map(name => new URL(name, folder)),
    new URL("../apps/relay/queries.ts", import.meta.url), new URL("../apps/relay/points.ts", import.meta.url)];
  expect(files.length).toBeGreaterThan(5);
  const CODE_TAKEN = "DELETE FROM relay_connect_codes WHERE code_sha256 = ? AND expires_at > ? RETURNING person_id";
  const ALLOWED: Record<string, string[]> = { "auth.ts": [CODE_TAKEN], "index.ts": ['["POST", "DELETE", "OPTIONS"]'],
    "answers.ts": [APP_DEVICE.slice(0, APP_DEVICE.indexOf("VALUES")), ".bind(adder.deviceId, adder.name, `app:${adder.deviceId}`, Date.now()).run()"],
    "asker.ts": [JSON.stringify(APP_DEVICE_OFF), "db.prepare(APP_DEVICE_OFF).bind(Date.now(), deviceId).run()"],
    "inputs.ts": ['"One SQLite command, such as CREATE TABLE, INSERT or SELECT."'] };
  ALLOWED["answers.ts"].push("asker.space.workbench.run(");
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
