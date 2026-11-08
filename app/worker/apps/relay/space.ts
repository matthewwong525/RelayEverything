// The one door into a person's space: only this file opens a space or the file store, and only for a caller that the
// sign-in already checked. space-access.test.ts fails when another file does. wiki/relay-spaces.md

/** A value SQLite takes or gives back. */
export type SqlValue = string | number | null | ArrayBuffer;
/** One statement and its bound values. */
export type Sql = { sql: string; params: SqlValue[] };
export type Row = Record<string, SqlValue>;

const checked = Symbol("checked caller");

/** How the caller proved who they are: a signed-in browser, a device key, an AI app's grant, a phone's sign-in code,
 *  Access on a self-host, the preview checker, the server's own queue message, or mail found by the inbox. */
export type CallerKind = "session" | "key" | "grant" | "code" | "access" | "checker" | "queue" | "inbox";
/** A key's reach: a phone, a chat sender, or an API key, which reaches only the web API. */
export type Reach = "phone" | "chats" | "api";
export type Caller = {
  readonly kind: CallerKind; readonly personId: string; readonly email?: string;
  /** A device key's own device: a phone or chat key only adds data; an API key reads and adds through the web API. */
  readonly device?: { readonly id: string; readonly reaches: Reach };
  readonly [checked]: true;
};

/** A caller, made only where its identity was checked: space-access.test.ts lists the files that may call this. */
export const vouch = (kind: CallerKind, personId: string, more: Pick<Caller, "email" | "device"> = {}): Caller =>
  ({ kind, personId, ...more, [checked]: true });

/** A statement in the shape of D1's, which the routes already write. */
interface Statement {
  bind(...values: SqlValue[]): Statement;
  first<T = Row>(): Promise<T | null>;
  all<T = Row>(): Promise<{ results: T[] }>;
  run(): Promise<unknown>;
}
export interface Db {
  prepare(sql: string): Statement;
  batch(statements: Statement[]): Promise<unknown[]>;
}

/** The space's RPC methods, as spaces-worker.ts serves them: the class lives in its own Worker, bound by name. */
type Stub = {
  query(sql: string, params: SqlValue[]): Promise<Row[]>; batch(statements: Sql[]): Promise<Row[][]>;
  fileKey(): Promise<ArrayBuffer>;
  watch(personId: string): Promise<void>; sweep(personId: string): Promise<number>; deleteEverything(): Promise<void>;
};
export type SpaceEnv = { SPACES: DurableObjectNamespace; RELAY_BUCKET: R2Bucket };

const sqlOf = new WeakMap<Statement, Sql>();

/** The space's SQL as a `Db`, so each route keeps its own SQL. */
function dbOf(stub: Pick<Stub, "query" | "batch">): Db {
  const statement = (sql: string, params: SqlValue[]): Statement => {
    const made: Statement = {
      bind: (...values) => statement(sql, values),
      first: async <T>() => ((await stub.query(sql, params))[0] ?? null) as T | null,
      all: async <T>() => ({ results: await stub.query(sql, params) as T[] }),
      run: async () => ({ results: await stub.query(sql, params) }),
    };
    sqlOf.set(made, { sql, params });
    return made;
  };
  return { prepare: sql => statement(sql, []), batch: async statements => stub.batch(statements.map(item => sqlOf.get(item)!)) };
}

const encoder = new TextEncoder();
const IV = 12;

/** A person's recordings and note files in the file store: each under their own folder, sealed with their space's
 *  file key and its own name, so the store alone, or a copy under another name, never opens. */
function filesOf(bucket: R2Bucket, stub: Pick<Stub, "fileKey">, personId: string) {
  const prefix = `people/${personId}/`;
  let key: Promise<CryptoKey> | undefined;
  const sealing = () => key ??= stub.fileKey().then(raw => crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]));
  const seal = async (name: string, bytes: ArrayBuffer) => {
    const iv = crypto.getRandomValues(new Uint8Array(IV));
    const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: encoder.encode(name) }, await sealing(), bytes));
    const out = new Uint8Array(IV + sealed.length);
    out.set(iv);
    out.set(sealed, IV);
    return out;
  };
  const files = {
    /** The file store's name for a note's recording (its note id), or a note's file (`attachments/<id>`). */
    nameOf: (item: string) => `${prefix}${item}`,
    /** Seals a recording or a file and stores it under the person's folder; answers its name for the row. */
    async put(item: string, bytes: ArrayBuffer): Promise<string> {
      const name = files.nameOf(item);
      await bucket.put(name, await seal(name, bytes), { httpMetadata: { contentType: "application/octet-stream" } });
      return name;
    },
    /** A recording's bytes, or null when it is missing, outside the person's folder, or does not open. */
    async open(name: string): Promise<Uint8Array | null> {
      if (!name.startsWith(prefix)) return null;
      const object = await bucket.get(name);
      if (!object) return null;
      const data = new Uint8Array(await object.arrayBuffer());
      try {
        return new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: data.subarray(0, IV), additionalData: encoder.encode(name) },
          await sealing(), data.subarray(IV)));
      } catch {
        return null;
      }
    },
    /** Deletes every object in the person's folder, a page at a time; answers how many. */
    removeAll: (): Promise<number> => removePrefix(bucket, prefix),
  };
  return files;
}

/** Deletes every object under the prefix, a page at a time; answers how many. */
async function removePrefix(bucket: R2Bucket, prefix: string): Promise<number> {
  let removed = 0;
  for (let cursor: string | undefined, more = true; more;) {
    const page = await bucket.list({ prefix, cursor });
    if (page.objects.length) await bucket.delete(page.objects.map(object => object.key));
    removed += page.objects.length;
    more = page.truncated;
    cursor = page.truncated ? page.cursor : undefined;
  }
  return removed;
}

const HELD = "held/";

/** Mail kept for an email with no account yet, under `held/` and nowhere else: inbox/held.ts seals each object with
 *  a key made from the sender's email, so this store holds nothing it can open. */
export type HeldFilesEnv = Pick<SpaceEnv, "RELAY_BUCKET">;

export function heldFiles(env: HeldFilesEnv) {
  const inside = (name: string) => {
    if (!name.startsWith(HELD)) throw new Error("Kept mail stays under held/.");
    return name;
  };
  return {
    put: async (name: string, bytes: Uint8Array) => { await env.RELAY_BUCKET.put(inside(name), bytes); },
    async get(name: string): Promise<Uint8Array | null> {
      const object = await env.RELAY_BUCKET.get(inside(name));
      return object ? new Uint8Array(await object.arrayBuffer()) : null;
    },
    removeAll: (prefix: string) => removePrefix(env.RELAY_BUCKET, inside(prefix)),
  };
}

export type Files = ReturnType<typeof filesOf>;
export type PersonSpace = {
  personId: string; db: Db; files: Files;
  /** Keeps the webhook alarm set while the space has a webhook. */
  watch(): Promise<void>;
  sweep(): Promise<number>;
  deleteEverything(): Promise<void>;
};

/** The caller's own space, and only theirs: its name is the caller's checked person id. */
export function spaceOf(env: SpaceEnv, caller: Caller): PersonSpace {
  if (caller[checked] !== true) throw new Error("A space opens only for a checked caller.");
  const stub = env.SPACES.get(env.SPACES.idFromName(caller.personId)) as unknown as Stub;
  return {
    personId: caller.personId, db: dbOf(stub), files: filesOf(env.RELAY_BUCKET, stub, caller.personId),
    watch: async () => stub.watch(caller.personId), sweep: async () => stub.sweep(caller.personId),
    deleteEverything: async () => stub.deleteEverything(),
  };
}
