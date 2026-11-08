// The spaces Worker: one Durable Object per person, with its own SQLite, holding that person's data. It runs SQL for
// apps/relay/space.ts, the one file that opens it, and its alarm wakes webhooks that fell behind. wiki/relay-spaces.md
import { DurableObject } from "cloudflare:workers";
import relay from "../../schema/space-migrations/0001_relay.sql";
import space from "../../schema/space-migrations/0002_space.sql";
import apiDevices from "../../schema/space-migrations/0003_api_devices.sql";
import attachments from "../../schema/space-migrations/0004_attachments.sql";
import noPebble from "../../schema/space-migrations/0005_no_pebble.sql";
import phoneData from "../../schema/space-migrations/0006_phone_data.sql";
import noteFiles from "../../schema/space-migrations/0007_note_files.sql";
import type { Row, Sql, SqlValue } from "./apps/relay/space.ts";
import { BEHIND } from "./apps/relay/webhooks/log.ts";

/** The space's migrations, in order. A space runs each once, and keeps the name of each in `space_migrations`. */
export const MIGRATIONS: readonly [string, string][] = [["0001_relay", relay], ["0002_space", space], ["0003_api_devices", apiDevices],
  ["0004_attachments", attachments], ["0005_no_pebble", noPebble], ["0006_phone_data", phoneData],
  ["0007_note_files", noteFiles]];

const SWEEP = 15 * 60_000;
const KEEP = 30 * 24 * 60 * 60_000;
const FILE_KEY = "files";

type SpacesEnv = { RELAY_WEBHOOKS: Queue };

/** Runs each migration the space has not run yet, each in one transaction with its own row. */
export function migrate(storage: Pick<DurableObjectStorage, "sql" | "transactionSync">) {
  storage.sql.exec("CREATE TABLE IF NOT EXISTS space_migrations (name TEXT PRIMARY KEY, applied_at INTEGER NOT NULL)");
  const done = new Set(storage.sql.exec<{ name: string }>("SELECT name FROM space_migrations").toArray().map(row => row.name));
  for (const [name, text] of MIGRATIONS) {
    if (done.has(name)) continue;
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

  /** The key that seals this person's recordings, made on first use. It never leaves the space but to space.ts. */
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

/** The Worker answers no address: only the app, the shared server and the connector reach a space, by RPC. */
export default { fetch: () => new Response("Not found", { status: 404 }) } satisfies ExportedHandler;
