// Each kind of data in a person's space, listed once with all its parts; kinds.test.ts fails on a part that is gone and
// not in `missing`. How to add a kind: wiki/relay-webhook-changes.md.
import type { Files } from "./space.ts";
import { MINUTE, type Db } from "./store.ts";
import { calendarEvents, healthSamples, locationPoints, locationStays, noteCreated, noteDeleted, noteFile, noteUpdated, photoCreated, type AttachmentRow, type EventRow,
  type HealthRow, type LocationRow, type NoteRow, type PhotoRow, type StayRow } from "./webhooks/format.ts";
import { base64 } from "./webhooks/sign.ts";

type Part = "webhook" | "api" | "tool" | "docs";
export type KindId = "notes" | "health" | "locations" | "calendar" | "files" | "photos" | "chats";
/** One row of the send log, `relay_outbox`. */
export type Entry = { seq: number; kind: string; ref: string; logged_at: number };
/** A message whose file's bytes the sender writes into its empty `base64`, so no long string is made. */
export type WithFile = { message: ReturnType<typeof noteFile> | ReturnType<typeof photoCreated>; bytes: Uint8Array };
/** What a group becomes: a message body, "skip" for a row deleted since, or "wait" for one still saving. */
type Built = { type: string } | WithFile | "skip" | "wait";

export type DataKind = {
  id: KindId;
  /** The tick's words on the webhook form, as "label: detail". */
  label: string; detail: string;
  /** Goes to every webhook, with no tick. */
  always?: true;
  /** The form warns to tick it only for a database you control. */
  sensitive?: true;
  /** Each of its log rows goes in a message of its own, as a note with its recording or a photo with its bytes. */
  alone?: true;
  /** The `relay_outbox` kinds it owns. */
  log: string[];
  /** The webhook message types it owns, from webhooks/format.ts. */
  messages: string[];
  /** The message for a group of its log rows, all of one log kind. */
  build?: (files: Files, db: Db, group: Entry[]) => Promise<Built>;
  /** Its /v1/ paths, from relay-mcp/api.ts, and its tools, from relay-mcp/inputs.ts. */
  api: string[]; tools: string[];
  /** Its page on the website, under site/src/content/docs/. */
  docs?: string;
  /** The parts it does not have yet, each with the reason. */
  missing?: Partial<Record<Part, string>>;
};

/** How long a recording or a photo, stored after its row, may still be saving. */
const FILE_WAIT = 2 * MINUTE;
const NOTE = `SELECT n.*, d.name AS device_name FROM relay_notes n JOIN relay_devices d ON d.id = n.device_id WHERE n.id = ?`;
const ids = (group: Entry[]) => JSON.stringify(group.map(entry => Number(entry.ref)));
const inOrder = `IN (SELECT value FROM json_each(?)) ORDER BY 1`;
const loggedAt = (group: Entry[]) => group.at(-1)!.logged_at;

/** The rows of `table` that a group names, in order, each with its device's name. */
const rowsOf = async <Row>(db: Db, table: string, group: Entry[]) => (await db.prepare(`SELECT t.*, d.name AS device_name FROM ${table} t
  JOIN relay_devices d ON d.id = t.device_id WHERE t.id ${inOrder}`).bind(ids(group)).all<Row>()).results;

/** A ring note's recording in base64: "wait" while it may still be saving, null when it never came. */
async function audioOf(files: Files, row: NoteRow): Promise<string | null | "wait"> {
  if (!row.audio_key) return null;
  const bytes = await files.open(row.audio_key);
  if (bytes) return base64(bytes);
  return Date.now() - row.created_at < FILE_WAIT ? "wait" : null;
}

/** One stored file of a note; "skip" when the note, and so the file, was deleted since. */
async function file(files: Files, db: Db, entry: Entry): Promise<Built> {
  const row = await db.prepare("SELECT id, note_id, name, content_type, size, file_key FROM relay_attachments WHERE id = ?").bind(entry.ref)
    .first<AttachmentRow & { note_id: string; file_key: string | null }>();
  const bytes = row?.file_key ? await files.open(row.file_key) : null;
  if (!row || !bytes) return "skip";
  return { message: noteFile(row, row.note_id, entry.logged_at), bytes };
}

/** A note alone, as it is now; "skip" when it was deleted since. A `note.updated` is a change from the phone that sent
 *  it, or a ring note's place from before the server stopped placing them. A `note.deleted` needs only its log row. */
async function note(files: Files, db: Db, [entry]: Entry[]): Promise<Built> {
  if (entry.kind === "note.file") return file(files, db, entry);
  if (entry.kind === "note.deleted") return noteDeleted(entry.ref, entry.logged_at);
  const row = await db.prepare(NOTE).bind(entry.ref).first<NoteRow>();
  if (!row) return "skip";
  // The message names the files and never waits for their bytes, as it carries none.
  const { results } = await db.prepare("SELECT id, name, content_type, size FROM relay_attachments WHERE note_id = ? ORDER BY rowid")
    .bind(row.id).all<AttachmentRow>();
  if (entry.kind === "note.updated") return noteUpdated(row, entry.logged_at, results);
  const audio = await audioOf(files, row);
  if (audio === "wait") return "wait";
  return noteCreated(row, audio, entry.logged_at, results);
}

const PHOTO = `SELECT p.*, d.name AS device_name FROM relay_photos p JOIN relay_devices d ON d.id = p.device_id WHERE p.id = ?`;

/** A photo alone, with its bytes: "wait" while its file may still be saving, and "skip" when it was deleted since, or
 *  its file never came, as when the store failed and the phone sends it again under the same clientId. */
async function photo(files: Files, db: Db, [entry]: Entry[]): Promise<Built> {
  const row = await db.prepare(PHOTO).bind(entry.ref).first<PhotoRow & { file_key: string; created_at: number }>();
  if (!row) return "skip";
  const bytes = await files.open(row.file_key);
  if (bytes) return { message: photoCreated(row, entry.logged_at), bytes };
  return Date.now() - row.created_at < FILE_WAIT ? "wait" : "skip";
}

const NO_WEBHOOK = "No webhook message yet: a later plan adds one.";

export const KINDS: DataKind[] = [
  { id: "notes", label: "Notes", detail: "with their words, recording and place", always: true, alone: true,
    log: ["note.created", "note.updated", "note.file", "note.deleted"], messages: ["note.created", "note.updated", "note.file", "note.deleted"],
    build: note,
    api: ["/v1/notes", "/v1/notes/{id}"], tools: ["search", "fetch", "timeline", "add_note"], docs: "app/your-notes" },
  { id: "health", label: "Health", detail: "steps, heart rate, sleep, weight and more", sensitive: true,
    log: ["health"], messages: ["health.samples"],
    build: async (_files, db, group) => healthSamples(await rowsOf<HealthRow>(db, "relay_health", group), loggedAt(group)),
    api: ["/v1/health"], tools: ["health"], docs: "app/health" },
  { id: "locations", label: "Location history", detail: "", sensitive: true,
    log: ["location", "stay"], messages: ["location.points", "location.stays"],
    // A stay changed twice in one group goes once, as it is now.
    build: async (_files, db, group) => group[0].kind === "stay"
      ? locationStays(await rowsOf<StayRow>(db, "relay_stays", group), loggedAt(group))
      : locationPoints(await rowsOf<LocationRow>(db, "relay_locations", group), loggedAt(group)),
    api: ["/v1/places"], tools: ["places"], docs: "app/location" },
  { id: "calendar", label: "Calendar", detail: "new, changed and removed events", sensitive: true,
    log: ["calendar"], messages: ["calendar.events"],
    // An event changed twice in one group goes once, as it is now.
    build: async (_files, db, group) => calendarEvents(await rowsOf<EventRow>(db, "relay_calendar_events", group), loggedAt(group)),
    api: ["/v1/calendar"], tools: ["calendar"], docs: "app/calendar" },
  { id: "files", label: "Files", detail: "", log: [], messages: [], api: [], tools: [], docs: "api/files",
    missing: { webhook: "A file goes with its note as note.file, under Notes.",
      api: "No /v1/ route opens a file yet.", tool: "No AI connector tool opens a file yet." } },
  // The Photos switch's photos: a photo shared into a note goes as one of the note's files instead.
  { id: "photos", label: "Photos", detail: "each with the picture, when and where you took it", sensitive: true, alone: true,
    log: ["photo"], messages: ["photo.created"], build: photo, api: [], tools: ["photos", "read_photo"], docs: "app/photos",
    missing: { api: "No /v1/ route reads photos yet: read_photo answers an image, and `near` is no query field." } },
  { id: "chats", label: "Claude Code chats", detail: "", log: [], messages: [], api: ["/v1/chats", "/v1/chats/{id}"],
    tools: ["search_chats", "read_chat"], docs: "connections/claude-code", missing: { webhook: NO_WEBHOOK } },
];

/** The kinds a webhook can take, in the order the form shows them. */
export const WEBHOOK_KINDS = KINDS.filter(kind => !kind.missing?.webhook);

/** The kind that owns a send log kind. */
export const ownerOf = (log: string) => KINDS.find(kind => kind.log.includes(log));
