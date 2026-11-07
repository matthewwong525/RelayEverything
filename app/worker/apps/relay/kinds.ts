// Each kind of data in a person's space, listed once with all its parts; kinds.test.ts fails on a part that is gone and
// not in `missing`. How to add a kind: wiki/relay-webhook-changes.md.
import type { Files } from "./space.ts";
import { MINUTE, type Db } from "./store.ts";
import { calendarEvents, healthSamples, locationPoints, noteCreated, noteUpdated, type AttachmentRow, type EventRow, type HealthRow,
  type LocationRow, type NoteRow } from "./webhooks/format.ts";
import { base64 } from "./webhooks/sign.ts";

type Part = "webhook" | "api" | "tool" | "docs";
export type KindId = "notes" | "health" | "locations" | "calendar" | "files" | "photos" | "chats";
/** One row of the send log, `relay_outbox`. */
export type Entry = { seq: number; kind: string; ref: string; logged_at: number };
/** What a group becomes: a message body, "skip" for a row deleted since, or "wait" for one still saving. */
type Built = { type: string } | "skip" | "wait";

export type DataKind = {
  id: KindId;
  /** The tick's words on the webhook form, as "label: detail". */
  label: string; detail: string;
  /** Goes to every webhook, with no tick. */
  always?: true;
  /** The form warns to tick it only for a database you control. */
  sensitive?: true;
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

const AUDIO_WAIT = 2 * MINUTE;
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
  return Date.now() - row.created_at < AUDIO_WAIT ? "wait" : null;
}

/** A note alone; "skip" when it was deleted since. A `note.updated` row logged before the server stopped placing ring
 *  notes still sends. */
async function note(files: Files, db: Db, [entry]: Entry[]): Promise<Built> {
  const row = await db.prepare(NOTE).bind(entry.ref).first<NoteRow>();
  if (!row) return "skip";
  if (entry.kind === "note.updated") return noteUpdated(row, entry.logged_at);
  const audio = await audioOf(files, row);
  if (audio === "wait") return "wait";
  // The message names the files and never waits for their bytes, as it carries none.
  const { results } = await db.prepare("SELECT id, name, content_type, size FROM relay_attachments WHERE note_id = ? ORDER BY rowid")
    .bind(row.id).all<AttachmentRow>();
  return noteCreated(row, audio, entry.logged_at, results);
}

const NO_WEBHOOK = "No webhook message yet: a later plan adds one.";

export const KINDS: DataKind[] = [
  { id: "notes", label: "Notes", detail: "with their words, recording and place", always: true,
    log: ["note.created", "note.updated"], messages: ["note.created", "note.updated", "note.file"], build: note,
    api: ["/v1/notes", "/v1/notes/{id}"], tools: ["search", "fetch", "timeline", "add_note"], docs: "app/your-notes" },
  { id: "health", label: "Health", detail: "steps, heart rate, sleep, weight and more", sensitive: true,
    log: ["health"], messages: ["health.samples"],
    build: async (_files, db, group) => healthSamples(await rowsOf<HealthRow>(db, "relay_health", group), loggedAt(group)),
    api: ["/v1/health"], tools: ["health"], docs: "app/health" },
  { id: "locations", label: "Location history", detail: "", sensitive: true,
    log: ["location"], messages: ["location.points"],
    build: async (_files, db, group) => locationPoints(await rowsOf<LocationRow>(db, "relay_locations", group), loggedAt(group)),
    api: ["/v1/places"], tools: ["places"], docs: "app/location" },
  { id: "calendar", label: "Calendar", detail: "new, changed and removed events", sensitive: true,
    log: ["calendar"], messages: ["calendar.events"],
    // An event changed twice in one group goes once, as it is now.
    build: async (_files, db, group) => calendarEvents(await rowsOf<EventRow>(db, "relay_calendar_events", group), loggedAt(group)),
    api: ["/v1/calendar"], tools: ["calendar"], docs: "app/calendar" },
  { id: "files", label: "Files", detail: "", log: [], messages: [], api: [], tools: [], docs: "api/files",
    missing: { webhook: NO_WEBHOOK + " A note.created lists a note's files, and a phone that sends to its own webhook sends note.file.",
      api: "No /v1/ route opens a file yet.", tool: "No AI connector tool opens a file yet." } },
  // The Photos switch's photos: a photo shared into a note goes as one of the note's files instead.
  { id: "photos", label: "Photos", detail: "", log: [], messages: [], api: [], tools: ["photos", "read_photo"], docs: "app/photos",
    missing: { webhook: "No webhook takes photos: each carries its place, and stays in the person's sealed space.",
      api: "No /v1/ route reads photos yet: read_photo answers an image, and `near` is no query field." } },
  { id: "chats", label: "Claude Code chats", detail: "", log: [], messages: [], api: ["/v1/chats", "/v1/chats/{id}"],
    tools: ["search_chats", "read_chat"], docs: "connections/claude-code", missing: { webhook: NO_WEBHOOK } },
];

/** The kinds a webhook can take, in the order the form shows them. */
export const WEBHOOK_KINDS = KINDS.filter(kind => !kind.missing?.webhook);

/** The kind that owns a send log kind. */
export const ownerOf = (log: string) => KINDS.find(kind => kind.log.includes(log));
