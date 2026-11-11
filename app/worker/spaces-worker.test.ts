import { existsSync, readFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, it } from "vitest";
import { ANA, BEN, NOW, queue, spaces } from "../tests/relay";
import type { SqlValue } from "./apps/relay/space.ts";
import spacesWorker, { migrate, MIGRATIONS, WORKBENCH_LIMITS } from "./spaces-worker.ts";

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

/** A person's agents' database, called as RPC calls it, and its storage's made-up size. */
const workbench = (name = ANA) => {
  const { bench, state } = spaces.benches.open(name);
  return { run: (...statements: [string, SqlValue[]?][]) => bench.run(statements.map(([sql, params = []]) => ({ sql, params }))), bench, state };
};

it("runs an agent's commands in its own database: a table made, then read back", () => {
  const { run, bench } = workbench();
  expect(run(["CREATE TABLE reading_list (title TEXT, done INTEGER)"], ["INSERT INTO reading_list VALUES (?, ?), (?, ?)", ["Dune", 0, "Emma", 1]]))
    .toEqual({ results: [{ rows: [], changed: 0 }, { rows: [], changed: 2 }] });
  expect(run(["SELECT title FROM reading_list WHERE done = ?", [1]])).toEqual({ results: [{ rows: [{ title: "Emma" }], changed: 0 }] });
  expect(bench.tables()).toEqual([{ name: "reading_list", columns: ["title", "done"], rows: 2 }]);
  // Ben's agents have a database of their own.
  expect(workbench(BEN).run(["SELECT * FROM reading_list"])).toEqual({ error: expect.stringContaining("no such table") });
});

it("runs a batch all or none, and never reaches the space's tables", async () => {
  const { run, bench } = workbench();
  run(["CREATE TABLE plans (name TEXT NOT NULL)"]);
  expect(run(["INSERT INTO plans VALUES ('ring')"], ["INSERT INTO plans VALUES (NULL)"])).toEqual({ error: expect.stringContaining("NOT NULL") });
  expect(bench.tables()).toEqual([{ name: "plans", columns: ["name"], rows: 0 }]);
  await (await fresh(ANA)).ready;
  for (const sql of ["SELECT * FROM relay_notes", "DELETE FROM relay_notes", "DROP TABLE relay_health"]) {
    expect(run([sql]), sql).toEqual({ error: expect.stringContaining("no such table") });
  }
});

it("refuses a step past each limit, with the limit, and keeps nothing it wrote", () => {
  const { run, bench, state } = workbench();
  run(["CREATE TABLE n (v)"]);
  expect(run(...Array.from({ length: WORKBENCH_LIMITS.statements + 1 }, () => ["SELECT 1"] as [string]))).toEqual({ error: "Send at most 50 statements at once." });
  expect(run([`SELECT '${"x".repeat(WORKBENCH_LIMITS.statementBytes)}'`])).toEqual({ error: "A statement is at most 100 KB." });
  run(["WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM c WHERE i < 5001) INSERT INTO n SELECT i FROM c"]);
  expect(run(["SELECT v FROM n"])).toEqual({ error: "An answer is at most 5000 rows: add a LIMIT." });
  expect(run(["SELECT v FROM n LIMIT 5000"])).toMatchObject({ results: [{ rows: expect.any(Array) }] });
  expect(run(["SELECT ? AS big", ["x".repeat(WORKBENCH_LIMITS.answerBytes)]])).toEqual({ error: "An answer is at most 5 MB: add a LIMIT." });
  state.size = WORKBENCH_LIMITS.databaseBytes + 1;
  expect(run(["INSERT INTO n VALUES (0)"])).toEqual({ error: "The agents' database is at most 1 GB." });
  state.size = null;
  expect(bench.tables()).toEqual([{ name: "n", columns: ["v"], rows: 5001 }]);
});

it("reads a blob back as base64, as JSON has no bytes", () => {
  expect(workbench().run(["SELECT x'00ff10' AS b"])).toEqual({ results: [{ rows: [{ b: { base64: "AP8Q" } }], changed: 0 }] });
});

it("deletes every table the agents made", async () => {
  const { run, bench } = workbench();
  run(["CREATE TABLE gone (v)"]);
  await bench.deleteEverything();
  expect(bench.tables()).toEqual([]);
});
