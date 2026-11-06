import { expect, it } from "vitest";
import { ANA, BEN, NOW, queue, spaces } from "../tests/relay";
import spacesWorker, { migrate, MIGRATIONS } from "./spaces-worker.ts";

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;
/** A space no test seeded, ready to call. */
const fresh = async (name = "cccccccc-0000-4000-8000-00000000000c") => {
  const found = spaces.open(name);
  await found.ready;
  return found;
};
const storageOf = (space: object) => (space as { ctx: DurableObjectState }).ctx.storage;
const device = { id: "d-new", name: "New phone", token_client_id: "rek:d-new", token_id: "", created_at: NOW, reaches: "phone" };
const webhook = (id: string, more: object = {}) => ({ id, name: "Example database", url: "https://db.example.com/relay", secret: "whsec_x",
  kinds: '["notes"]', sent_seq: 0, created_at: NOW, ...more });

it("runs each migration once and records it in space_migrations", async () => {
  const { space, state } = await fresh();
  const applied = () => state.sql.prepare("SELECT name, applied_at FROM space_migrations ORDER BY name").all().map(row => ({ ...row }));
  expect(applied()).toEqual(MIGRATIONS.map(([name]) => ({ name, applied_at: NOW })));
  space.query("INSERT INTO space_meta (name, value) VALUES ('kept', 'yes')");
  // A second start finds every migration done, so it runs none again and keeps the rows.
  migrate(storageOf(space));
  expect(applied()).toHaveLength(MIGRATIONS.length);
  expect(space.query("SELECT value FROM space_meta WHERE name = 'kept'")).toEqual([{ value: "yes" }]);
});

it("adds moved rows once, and refuses a table or column the move does not write", async () => {
  const { space } = await fresh();
  expect(space.import("relay_devices", [device])).toBe(1);
  expect(space.import("relay_devices", [device, { ...device, id: "d-other", token_client_id: "rek:d-other" }])).toBe(1);
  expect(() => space.import("space_keys" as never, [{ name: "files" }])).toThrow("space_keys is not a table the move writes.");
  expect(() => space.import("relay_devices", [{ ...device, id: "d-bad", "name) VALUES (1); --": "x" }]))
    .toThrow("A column name is not one the move writes.");
  expect(space.query("SELECT id FROM relay_devices ORDER BY id")).toEqual([{ id: "d-new" }, { id: "d-other" }]);
});

it("counts only the moved rows it added, not the send log rows their triggers write", async () => {
  const { space } = await fresh();
  space.import("relay_devices", [device]);
  const note = (id: string) => ({ id, device_id: "d-new", source: "typed", text: "A note", recorded_at: NOW, created_at: NOW });
  expect(space.import("relay_notes", [note("n-1"), note("n-2")])).toBe(2);
  expect(space.query("SELECT count(*) AS count FROM relay_outbox")).toEqual([{ count: 2 }]);
  expect(space.import("relay_notes", [note("n-1"), note("n-3")])).toBe(1);
});

it("counts the rows in each moved table", async () => {
  const { space } = await fresh();
  space.import("relay_devices", [device]);
  space.import("relay_webhooks", [webhook("w-1"), webhook("w-2")]);
  expect(space.counts()).toEqual({ relay_devices: 1, relay_notes: 0, relay_health: 0, relay_locations: 0, relay_chats: 0,
    relay_chat_messages: 0, relay_chat_saves: 0, relay_webhooks: 2 });
});

it("runs a batch in one transaction: all of it, or none", async () => {
  const { space } = await fresh();
  const insert = { sql: "INSERT INTO space_meta (name, value) VALUES (?, ?)", params: ["a", "1"] };
  expect(space.batch([insert, { sql: "SELECT value FROM space_meta", params: [] }])).toEqual([[], [{ value: "1" }]]);
  expect(() => space.batch([{ ...insert, params: ["b", "2"] }, insert])).toThrow();
  expect(space.query("SELECT name FROM space_meta")).toEqual([{ name: "a" }]);
});

it("makes the file key once and gives the same one after", async () => {
  const { space } = await fresh();
  const first = new Uint8Array(space.fileKey());
  expect(first).toHaveLength(32);
  expect(new Uint8Array(space.fileKey())).toEqual(first);
  expect(new Uint8Array((await fresh(BEN)).space.fileKey())).not.toEqual(first);
});

it("sends each webhook behind from its alarm with the person watch kept, and drops tries older than 30 days", async () => {
  const { space, state } = await fresh();
  space.import("relay_devices", [device]);
  space.import("relay_webhooks", [webhook("w-behind", { kinds: '["notes","health"]' }), webhook("w-paused", { active: 0 }),
    webhook("w-waiting", { next_try_at: NOW + MINUTE })]);
  space.query("INSERT INTO relay_notes (id, device_id, source, text, recorded_at, created_at) VALUES ('n', 'd-new', 'typed', 'A note', ?, ?)",
    [NOW, NOW]);
  const attempt = "INSERT INTO relay_webhook_attempts (webhook_id, at, type, ms) VALUES ('w-behind', ?, 'note.created', 5)";
  space.query(attempt, [NOW - 31 * DAY]);
  space.query(attempt, [NOW - 29 * DAY]);
  // Before watch, the space knows no person, so its alarm can name no one.
  expect(await space.sweep()).toBe(0);
  expect(queue.sent).toEqual([]);
  await space.watch(ANA);
  await space.watch(ANA);
  expect(state.alarm).toBe(NOW + 15 * MINUTE);
  await space.alarm();
  expect(queue.sent).toEqual([{ webhook: "w-behind", person: ANA }]);
  expect(space.query("SELECT at FROM relay_webhook_attempts")).toEqual([{ at: NOW - 29 * DAY }]);
  expect(await space.sweep(BEN)).toBe(1);
  expect(queue.sent.at(-1)).toEqual({ webhook: "w-behind", person: BEN });
});

it("deletes every row, the file key and the alarm", async () => {
  const { space, state } = await fresh();
  space.import("relay_webhooks", [webhook("w-1")]);
  const key = new Uint8Array(space.fileKey());
  await space.watch(ANA);
  await space.deleteEverything();
  expect(state.alarm).toBeNull();
  expect(state.sql.prepare("SELECT name FROM sqlite_master").all()).toEqual([]);
  migrate(storageOf(space));
  expect(space.counts().relay_webhooks).toBe(0);
  expect(new Uint8Array(space.fileKey())).not.toEqual(key);
});

it("answers no address", async () => {
  const response = await spacesWorker.fetch();
  expect([response.status, await response.text()]).toEqual([404, "Not found"]);
});
