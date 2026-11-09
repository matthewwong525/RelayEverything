import { existsSync, readFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
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
/** Adds each row to `table` through the space's own SQL. */
const insert = (space: { query: (sql: string, params: never[]) => unknown }, table: string, rows: Record<string, unknown>[]) => {
  for (const row of rows) {
    const names = Object.keys(row);
    space.query(`INSERT INTO ${table} (${names.join(", ")}) VALUES (${names.map(() => "?").join(", ")})`, Object.values(row) as never[]);
  }
};

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
  insert(space, "relay_devices", [device]);
  insert(space, "relay_webhooks", [webhook("w-behind", { kinds: '["notes","health"]' }), webhook("w-paused", { active: 0 }),
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
  insert(space, "relay_webhooks", [webhook("w-1")]);
  const key = new Uint8Array(space.fileKey());
  await space.watch(ANA);
  await space.deleteEverything();
  expect(state.alarm).toBeNull();
  expect(state.sql.prepare("SELECT name FROM sqlite_master").all()).toEqual([]);
  migrate(storageOf(space));
  expect(space.query("SELECT count(*) AS count FROM relay_webhooks")).toEqual([{ count: 0 }]);
  expect(new Uint8Array(space.fileKey())).not.toEqual(key);
});

it("answers no address", async () => {
  const response = await spacesWorker.fetch();
  expect([response.status, await response.text()]).toEqual([404, "Not found"]);
});

/** Each file `entry` loads at run time through relative imports, mapped to its loader. `import type` leaves no code. */
function loads(entry: string, from: string | null = null, found = new Map<string, string | null>()) {
  if (found.has(entry)) return found;
  found.set(entry, from);
  if (!entry.endsWith(".ts")) return found;
  for (const [, path] of readFileSync(entry, "utf8").matchAll(/^(?:import|export)(?!\s+type\b)\b[^;]*?from\s+"(\.[^"]+)"/gms)) {
    const file = resolve(dirname(entry), path);
    loads(existsSync(file) ? file : `${file}.ts`, entry, found);
  }
  return found;
}

it("loads no route code and no Vite-only import.meta.glob, since wrangler bundles the spaces Worker alone", () => {
  const worker = fileURLToPath(new URL("./", import.meta.url));
  const found = loads(fileURLToPath(new URL("./spaces-worker.ts", import.meta.url)));
  const chain = (file: string): string[] => [...(found.get(file) ? chain(found.get(file)!) : []), relative(worker, file)];
  expect([...found.keys()].some(file => file.endsWith("apps/relay/webhooks/format.ts"))).toBe(true);
  const bad = [...found.keys()].filter(file => file.endsWith("api/contract.ts") || (file.endsWith(".ts") && readFileSync(file, "utf8").includes("import.meta.glob")));
  expect(bad.map(file => chain(file).join("\n → ")), "the spaces Worker reaches no route code").toEqual([]);
});
