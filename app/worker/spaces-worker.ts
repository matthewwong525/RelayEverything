// The spaces Worker: one Durable Object per person, with its own SQLite, holding that person's data, and a second, the
// agents' database. Only apps/relay/space.ts opens them; the alarm wakes late webhooks. wiki/relay-spaces.md
import { DurableObject } from "cloudflare:workers";
import relay from "../../schema/space-migrations/0001_relay.sql";
import space from "../../schema/space-migrations/0002_space.sql";
import apiDevices from "../../schema/space-migrations/0003_api_devices.sql";
import attachments from "../../schema/space-migrations/0004_attachments.sql";
import noPebble from "../../schema/space-migrations/0005_no_pebble.sql";
import phoneData from "../../schema/space-migrations/0006_phone_data.sql";
import noteFiles from "../../schema/space-migrations/0007_note_files.sql";
import photos from "../../schema/space-migrations/0008_photos.sql";
import inbox from "../../schema/space-migrations/0009_inbox.sql";
import noteEdits from "../../schema/space-migrations/0010_note_edits.sql";
import noteSync from "../../schema/space-migrations/0011_note_sync.sql";
import noteDeletes from "../../schema/space-migrations/0012_note_deletes.sql";
import stays from "../../schema/space-migrations/0013_stays.sql";
import nights from "../../schema/space-migrations/0014_nights.sql";
import agentDevices from "../../schema/space-migrations/0015_agent_devices.sql";
import memory from "../../schema/space-migrations/0016_memory.sql";
import type { Row, Sql, SqlValue } from "./apps/relay/space.ts";
import { BEHIND } from "./apps/relay/webhooks/log.ts";

/** The space's migrations, in order. A space runs each once, and keeps the name of each in `space_migrations`. */
export const MIGRATIONS: readonly [string, string][] = [["0001_relay", relay], ["0002_space", space], ["0003_api_devices", apiDevices],
  ["0004_attachments", attachments], ["0005_no_pebble", noPebble], ["0006_phone_data", phoneData],
  ["0007_note_files", noteFiles], ["0008_photos", photos], ["0009_inbox", inbox],
  ["0010_note_edits", noteEdits], ["0011_note_sync", noteSync], ["0012_note_deletes", noteDeletes],
  ["0013_stays", stays], ["0014_nights", nights], ["0015_agent_devices", agentDevices], ["0016_memory", memory]];
/** A staging space ran a migration first under an older name, before another change took its number. */
const RAN_AS: Readonly<Record<string, string>> = { "0010_note_edits": "0008_note_edits" };

const SWEEP = 15 * 60_000;
const KEEP = 30 * 24 * 60 * 60_000;
const FILE_KEY = "files";

type SpacesEnv = { RELAY_WEBHOOKS: Queue };

/** Runs each migration the space has not run yet, each in one transaction with its own row. */
export function migrate(storage: Pick<DurableObjectStorage, "sql" | "transactionSync">) {
  storage.sql.exec("CREATE TABLE IF NOT EXISTS space_migrations (name TEXT PRIMARY KEY, applied_at INTEGER NOT NULL)");
  const done = new Set(storage.sql.exec<{ name: string }>("SELECT name FROM space_migrations").toArray().map(row => row.name));
  for (const [name, text] of MIGRATIONS) {
    if (done.has(name) || done.has(RAN_AS[name])) continue;
    storage.transactionSync(() => {
      storage.sql.exec(text);
      storage.sql.exec("INSERT INTO space_migrations (name, applied_at) VALUES (?, ?)", name, Date.now());
    });
  }
}

export class Space extends DurableObject<SpacesEnv> {
  constructor(ctx: DurableObjectState, env: SpacesEnv) {
    super(ctx, env);
    // Nothing reaches the space before its tables are there.
    void ctx.blockConcurrencyWhile(async () => migrate(ctx.storage));
  }

  private rows(statement: Sql): Row[] {
    return this.ctx.storage.sql.exec<Row>(statement.sql, ...statement.params).toArray();
  }

  /** One statement: its rows, or none for a write without RETURNING. */
  query(sql: string, params: SqlValue[] = []): Row[] {
    return this.rows({ sql, params });
  }

  /** Several statements in one transaction: all of them, or none. */
  batch(statements: Sql[]): Row[][] {
    return this.ctx.storage.transactionSync(() => statements.map(statement => this.rows(statement)));
  }

  /** The key that seals this person's recordings and photos, made on first use. Only space.ts gets it. */
  fileKey(): ArrayBuffer {
    const [found] = this.query("SELECT key FROM space_keys WHERE name = ?", [FILE_KEY]);
    if (found) return found.key as ArrayBuffer;
    const key = crypto.getRandomValues(new Uint8Array(32));
    this.query("INSERT INTO space_keys (name, key, created_at) VALUES (?, ?, ?)", [FILE_KEY, key.buffer, Date.now()]);
    return key.buffer;
  }

  /** Remembers whose space this is, for the alarm's queue messages, and sets the alarm when none is set. */
  async watch(personId: string): Promise<void> {
    this.query("INSERT INTO space_meta (name, value) VALUES ('person', ?) ON CONFLICT (name) DO UPDATE SET value = excluded.value", [personId]);
    if (await this.ctx.storage.getAlarm() === null) await this.ctx.storage.setAlarm(Date.now() + SWEEP);
  }

  /** Wakes each webhook left behind by a lost wake-up, and drops tries older than 30 days. Says how many it woke. The
   *  alarm names the person `watch` kept; a person's own call names them. */
  async sweep(personId?: string): Promise<number> {
    const person = personId ?? this.query("SELECT value FROM space_meta WHERE name = 'person'")[0]?.value;
    const behind = person ? this.query(`SELECT w.id FROM relay_webhooks w WHERE ${BEHIND}`, [Date.now()]) : [];
    if (behind.length) await this.env.RELAY_WEBHOOKS.sendBatch(behind.map(row => ({ body: { webhook: row.id, person } })));
    this.query("DELETE FROM relay_webhook_attempts WHERE at < ?", [Date.now() - KEEP]);
    return behind.length;
  }

  /** Every 15 minutes while the space has a webhook; a space with none sets no alarm, so it costs nothing. */
  async alarm(): Promise<void> {
    await this.sweep();
    if (this.query("SELECT 1 FROM relay_webhooks LIMIT 1").length) await this.ctx.storage.setAlarm(Date.now() + SWEEP);
  }

  /** Deletes every row, the file key and the alarm. The object then holds nothing; a new sign-in gets a new space. */
  async deleteEverything(): Promise<void> {
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }
}

/** What one step to the agents' database may send and get back, and how big the database may grow. */
export const WORKBENCH_LIMITS = { statementBytes: 100_000, statements: 50, rows: 5_000, answerBytes: 5_000_000, databaseBytes: 1_000_000_000 };
const SIZES = { statementBytes: "100 KB", answerBytes: "5 MB", databaseBytes: "1 GB" };

/** A row as JSON carries it: a blob, which JSON has no form for, as base64. */
const shown = (row: Row) => Object.fromEntries(Object.entries(row).map(([name, value]) =>
  [name, value instanceof ArrayBuffer ? { base64: btoa(Array.from(new Uint8Array(value), byte => String.fromCharCode(byte)).join("")) } : value]));

/** Each person's agents' database: only the tables their computers' agents make. It never opens a space, so no
 *  command reaches Relay Everything's own tables. wiki/relay-agent-database.md */
export class Workbench extends DurableObject {
  /** Runs the statements in one transaction: each one's rows and changed rows, or the reason none of it stayed. A
   *  limit throws inside the transaction, so nothing the step wrote stays. */
  run(statements: Sql[]): { results: { rows: Record<string, unknown>[]; changed: number }[] } | { error: string } {
    const { sql } = this.ctx.storage;
    try {
      if (statements.length > WORKBENCH_LIMITS.statements) throw new Error(`Send at most ${WORKBENCH_LIMITS.statements} statements at once.`);
      if (statements.some(item => new TextEncoder().encode(item.sql).length > WORKBENCH_LIMITS.statementBytes)) {
        throw new Error(`A statement is at most ${SIZES.statementBytes}.`);
      }
      return { results: this.ctx.storage.transactionSync(() => {
        let rows = 0, bytes = 0;
        const results = statements.map(({ sql: text, params }) => {
          const cursor = sql.exec<Row>(text, ...params);
          const found = cursor.toArray().map(shown);
          rows += found.length;
          bytes += JSON.stringify(found).length;
          if (rows > WORKBENCH_LIMITS.rows) throw new Error(`An answer is at most ${WORKBENCH_LIMITS.rows} rows: add a LIMIT.`);
          if (bytes > WORKBENCH_LIMITS.answerBytes) throw new Error(`An answer is at most ${SIZES.answerBytes}: add a LIMIT.`);
          return { rows: found, changed: cursor.rowsWritten };
        });
        if (sql.databaseSize > WORKBENCH_LIMITS.databaseBytes) throw new Error(`The agents' database is at most ${SIZES.databaseBytes}.`);
        return results;
      }) };
    } catch (error) {
      // SQLite and each limit throw an Error.
      return { error: (error as Error).message };
    }
  }

  /** Each table the agents made, with its columns and how many rows it holds. */
  tables(): { name: string; columns: string[]; rows: number }[] {
    const { sql } = this.ctx.storage;
    // sqlite_ and _cf_ tables are SQLite's and Cloudflare's own, which no command reads.
    const names = sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table' AND substr(name, 1, 7) <> 'sqlite_' " +
      "AND substr(name, 1, 4) <> '_cf_' ORDER BY name").toArray();
    const quoted = (name: string) => `"${name.replaceAll('"', '""')}"`;
    return names.map(({ name }) => ({ name,
      columns: sql.exec<{ name: string }>("SELECT name FROM pragma_table_info(?)", name).toArray().map(column => column.name),
      rows: Number(sql.exec<{ count: number }>(`SELECT count(*) AS count FROM ${quoted(name)}`).toArray()[0].count) }));
  }

  /** Deletes every table the agents made. */
  async deleteEverything(): Promise<void> {
    await this.ctx.storage.deleteAll();
  }
}

/** The Worker answers no address: only the app, the shared server and the connector reach a space, by RPC. */
export default { fetch: () => new Response("Not found", { status: 404 }) } satisfies ExportedHandler;
