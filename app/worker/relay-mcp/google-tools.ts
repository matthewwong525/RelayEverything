// The connector's Gmail, Calendar, Drive and Contacts tools: fourteen fixed questions, each made into a request for
// apps/relay/google/proxy.ts, the one door to Google. Each answer goes straight back to the AI; nothing is kept.
import { z } from "zod";
import { GoogleRefusal, pass, type Service } from "../apps/relay/google/proxy.ts";
import { GOOGLE_AGAIN, range, Refusal, type Asker } from "./answers.ts";
import { attachmentsOf, headerOf, mailText, rawOf, type GmailMessage } from "./google-mail.ts";
import { when, zone } from "./inputs.ts";
import { instant, local, ZONE } from "./time.ts";

/** The most words a tool gives back from one email, thread or file. */
export const TEXT_CAP = 20_000;
const PAGE = 25;
const DOC = "application/vnd.google-apps.document";
const FILE_FIELDS = "id, name, mimeType, modifiedTime, webViewLink, size, parents, trashed";

type Query = Record<string, string | number | boolean | string[] | undefined>;
type Call = { method?: string; query?: Query; json?: unknown; body?: string; type?: string; text?: true };

/** A query string: each field once, an array's values each, and a missing field left out. */
const searchOf = (query: Query) => {
  const search = new URLSearchParams();
  for (const [name, value] of Object.entries(query)) for (const item of [value ?? []].flat()) search.append(name, String(item));
  const text = search.toString();
  return text ? `?${text}` : "";
};

/** Google's own words for a refused request. */
async function reasonOf(response: Response): Promise<string> {
  const body = await response.json().catch(() => null) as { error?: { message?: string } | string; error_description?: string } | null;
  return (typeof body?.error === "object" ? body.error.message : body?.error_description) ?? "Google gave no reason.";
}

/** One request to the caller's own Google: its JSON, or its words with `text`; an empty answer is "". A refusal is
 *  one the AI can read. */
async function google<T>(asker: Asker, service: Service, path: string, { method = "GET", query = {}, json, body, type, text }: Call = {}): Promise<T> {
  if (!asker.google) throw new Refusal(GOOGLE_AGAIN, 403);
  const headers = new Headers();
  if (json !== undefined || type) headers.set("content-type", type ?? "application/json");
  let response: Response;
  try {
    response = await pass(asker.env, asker.space, { service, path, method, search: searchOf(query), headers,
      body: json === undefined ? body : JSON.stringify(json) });
  } catch (error) {
    if (error instanceof GoogleRefusal) throw new Refusal(error.message, 403);
    throw error;
  }
  if (!response.ok) throw new Refusal(`Google answered ${response.status}: ${await reasonOf(response)}`, response.status === 404 ? 404 : 400);
  const words = await response.text();
  return (text || !words ? words : JSON.parse(words)) as T;
}

/** Words cut to TEXT_CAP, and whether they were cut. */
const capped = (text: string, cap = TEXT_CAP) => ({ text: text.slice(0, cap), cut: text.length > cap });

const id = (what: string) => z.string().regex(/^[A-Za-z0-9_-]{1,256}$/).describe(what);
const addresses = z.array(z.string().max(320).regex(/^[^\s,;<>]+@[^\s,;<>]+$/, "An email address, such as sam@example.com.")).max(50);
const line = (what: string) => z.string().max(1000).regex(/^[^\r\n]*$/, "One line.").describe(what);
const pageToken = z.string().max(1000).optional().describe("The last answer's `nextPageToken`, to read the next page.");
const limit = (fallback: number, most = PAGE) => z.number().int().min(1).max(most).default(fallback).describe(`How many, at most ${most}.`);
const calendarId = z.string().max(300).default("primary").describe("The calendar's id; `primary` is your own.");
const enc = encodeURIComponent;

const READ = { readOnlyHint: true, destructiveHint: false, openWorldHint: true };
const CHANGE = { readOnlyHint: false, destructiveHint: false, openWorldHint: true };
const FINAL = { readOnlyHint: false, destructiveHint: true, openWorldHint: true };
type Hints = typeof READ | typeof CHANGE | typeof FINAL;

/** One tool: its words for the AI, its input, its hints, and how it asks Google. */
const tool = <Shape extends z.ZodRawShape>(made: { title: string; description: string; input: Shape; hints: Hints;
  ask: (asker: Asker, input: z.output<z.ZodObject<Shape>>) => Promise<unknown> }) => made;

// Gmail

const METADATA = ["From", "To", "Cc", "Subject", "Date"];

/** An email as a list shows it. */
const mailShown = (message: GmailMessage) => ({ id: message.id, threadId: message.threadId, from: headerOf(message, "From"),
  to: headerOf(message, "To"), subject: headerOf(message, "Subject"), date: headerOf(message, "Date"), snippet: message.snippet ?? "",
  labels: message.labelIds ?? [], unread: message.labelIds?.includes("UNREAD") ?? false });

const letter = { to: addresses.optional().describe("Who it goes to. Left out on a reply, it goes to the sender of the email answered."),
  cc: addresses.optional().describe("Copies to."), bcc: addresses.optional().describe("Hidden copies to."),
  subject: line("The subject. Left out on a reply, it is the answered email's, with Re:.").optional(),
  text: z.string().min(1).max(100_000).describe("What the email says, as plain text."),
  replyTo: id("The id of the email this answers: the reply goes in its thread.").optional() };
type LetterInput = z.output<z.ZodObject<typeof letter>>;

/** A new email or reply as Gmail's raw text, with its thread for a reply. */
async function letterOf(asker: Asker, { to, cc, bcc, subject, text, replyTo }: LetterInput) {
  if (!replyTo) {
    if (!to?.length) throw new Refusal("Say who it goes to in `to`.");
    return { raw: rawOf({ to, cc, bcc, subject: subject ?? "", text }) };
  }
  const original = await google<GmailMessage>(asker, "gmail", `messages/${replyTo}`,
    { query: { format: "metadata", metadataHeaders: ["From", "Reply-To", "Subject", "Message-ID", "References"] } });
  const was = headerOf(original, "Subject") ?? "";
  const messageId = headerOf(original, "Message-ID");
  const more: Record<string, string> = messageId ? { "In-Reply-To": messageId, References: `${headerOf(original, "References") ?? ""} ${messageId}`.trim() } : {};
  const sender = headerOf(original, "Reply-To") ?? headerOf(original, "From");
  return { threadId: original.threadId, raw: rawOf({ to: to?.length ? to : sender ? [sender] : [], cc, bcc, text, more,
    subject: subject ?? (/^re:/i.test(was) ? was : `Re: ${was}`) }) };
}

const GMAIL = {
  search_email: tool({
    title: "Search email",
    description: "Emails that match a Gmail search, newest first, with each one's sender, subject, date and a short snippet. Use Gmail's own " +
      "search words, such as `from:sam invoice after:2026/11/01`. Read one with read_email.",
    input: { query: z.string().trim().min(1).max(500).describe("A Gmail search, as in Gmail's search box."), limit: limit(10), pageToken },
    hints: READ,
    ask: async (asker, { query, limit: most, pageToken: next }) => {
      const found = await google<{ messages?: { id: string }[]; nextPageToken?: string }>(asker, "gmail", "messages",
        { query: { q: query, maxResults: most, pageToken: next } });
      const messages = await Promise.all((found.messages ?? []).map(message => google<GmailMessage>(asker, "gmail", `messages/${message.id}`,
        { query: { format: "metadata", metadataHeaders: METADATA } })));
      return { messages: messages.map(mailShown), nextPageToken: found.nextPageToken ?? null };
    },
  }),
  read_email: tool({
    title: "Read email",
    description: `One email, or its whole thread, with its words as plain text: at most ${TEXT_CAP} characters in all. Attachments are named, ` +
      "never read.",
    input: { id: id("The email's id, or the thread's id with `thread`."), thread: z.boolean().default(false).describe("Read the whole thread.") },
    hints: READ,
    ask: async (asker, { id: which, thread }) => {
      const found = await google<GmailMessage & { messages?: GmailMessage[] }>(asker, "gmail", `${thread ? "threads" : "messages"}/${which}`,
        { query: { format: "full" } });
      let left = TEXT_CAP;
      const messages = (thread ? found.messages ?? [] : [found]).map(message => {
        const { text, cut } = capped(mailText(message), left);
        left -= text.length;
        return { ...mailShown(message), cc: headerOf(message, "Cc"), text, cut, attachments: attachmentsOf(message) };
      });
      return thread ? { threadId: which, messages } : messages[0];
    },
  }),
  send_email: tool({
    title: "Send email",
    description: "Send an email, or a reply in its thread, from the person's own address. Only when the person asks to send it: a sent email " +
      "can't be undone. To let them check it first, use draft_email.",
    input: letter, hints: FINAL,
    ask: async (asker, input) => {
      const sent = await google<GmailMessage>(asker, "gmail", "messages/send", { method: "POST", json: await letterOf(asker, input) });
      return { id: sent.id, threadId: sent.threadId, sent: true };
    },
  }),
  draft_email: tool({
    title: "Draft email",
    description: "Put a draft email, or a reply in its thread, in the person's Gmail drafts, for them to check and send.",
    input: letter, hints: CHANGE,
    ask: async (asker, input) => {
      const draft = await google<{ id: string; message: GmailMessage }>(asker, "gmail", "drafts", { method: "POST",
        json: { message: await letterOf(asker, input) } });
      return { draftId: draft.id, id: draft.message.id, threadId: draft.message.threadId };
    },
  }),
  change_email: tool({
    title: "Change email",
    description: "Archive an email or thread, mark it read or unread, add or remove labels, or put it in the bin, or take it out. The bin " +
      "keeps it 30 days; nothing deletes for ever.",
    input: { id: id("The email's id, or the thread's id with `thread`."), thread: z.boolean().default(false).describe("Change the whole thread."),
      archive: z.boolean().optional().describe("true takes it out of the inbox; false puts it back."),
      read: z.boolean().optional().describe("true marks it read; false unread."),
      addLabels: z.array(id("A label id")).max(20).optional().describe("Label ids to add, such as STARRED or IMPORTANT, or one of your own."),
      removeLabels: z.array(id("A label id")).max(20).optional().describe("Label ids to remove."),
      bin: z.boolean().optional().describe("true puts it in the bin; false takes it out. Nothing else changes with it.") },
    hints: CHANGE,
    ask: async (asker, { id: which, thread, archive, read, addLabels = [], removeLabels = [], bin }) => {
      const path = `${thread ? "threads" : "messages"}/${which}`;
      if (bin !== undefined) {
        await google(asker, "gmail", `${path}/${bin ? "trash" : "untrash"}`, { method: "POST" });
        return { id: which, bin };
      }
      const add = [...addLabels, ...archive === false ? ["INBOX"] : [], ...read === false ? ["UNREAD"] : []];
      const remove = [...removeLabels, ...archive ? ["INBOX"] : [], ...read ? ["UNREAD"] : []];
      if (!add.length && !remove.length) throw new Refusal("Say what to change: archive, read, addLabels, removeLabels or bin.");
      await google(asker, "gmail", `${path}/modify`, { method: "POST", json: { addLabelIds: add, removeLabelIds: remove } });
      return { id: which, added: add, removed: remove };
    },
  }),
};

// Calendar

type Slot = { date?: string; dateTime?: string; timeZone?: string };
type CalendarEvent = { id: string; status?: string; summary?: string; description?: string; location?: string; start?: Slot; end?: Slot;
  attendees?: { email: string }[]; htmlLink?: string };

const eventShown = (event: CalendarEvent) => ({ id: event.id, summary: event.summary ?? "", start: event.start?.dateTime ?? event.start?.date ?? null,
  end: event.end?.dateTime ?? event.end?.date ?? null, allDay: event.start?.date !== undefined, location: event.location ?? null,
  description: event.description ? capped(event.description, 2000).text : null, attendees: event.attendees?.map(person => person.email) ?? [],
  link: event.htmlLink ?? null });

/** A start or end as Calendar takes it: a day for an all-day event, else a time in the zone. */
function slotOf(text: string, allDay: boolean, timezone: string): Slot {
  if (allDay) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) throw new Refusal("An all-day event starts and ends on a day, as YYYY-MM-DD; its end is the day after.");
    return { date: text };
  }
  const at = instant(text, timezone);
  if (Number.isNaN(at)) throw new Refusal("Give `start` and `end` as a day or an ISO time.");
  return { dateTime: local(at, timezone), timeZone: timezone };
}

const eventFields = { summary: line("The event's title."), location: line("Where it is.").optional(),
  description: z.string().max(8000).optional().describe("Notes on the event."), attendees: addresses.optional()
    .describe("Guests' email addresses: each gets an invitation."), calendarId, timezone: zone };

/** The fields a change or a new event sends, with only those given. */
function eventBody({ summary, location, description, start, end, allDay = false, timezone = ZONE, attendees }:
  Partial<z.output<z.ZodObject<typeof eventFields>>> & { start?: string; end?: string; allDay?: boolean }) {
  const body = { summary, location, description, start: start && slotOf(start, allDay, timezone), end: end && slotOf(end, allDay, timezone),
    attendees: attendees?.map(email => ({ email })) };
  return Object.fromEntries(Object.entries(body).filter(([, value]) => value !== undefined));
}
const invites = (attendees?: string[]) => ({ sendUpdates: attendees?.length ? "all" : "none" });

const CALENDAR = {
  list_events: tool({
    title: "List events",
    description: "The person's calendar events from one time to another, in order, each repeat on its own, with times in the zone.",
    input: { from: when("The first time"), to: when("The time to stop before"), query: z.string().max(200).optional()
      .describe("Only events holding these words."), calendarId, limit: limit(50, 100), pageToken, timezone: zone },
    hints: READ,
    ask: async (asker, { from, to, query, calendarId: calendar, limit: most, pageToken: next, timezone = ZONE }) => {
      const [start, end] = range(from, to, timezone);
      const found = await google<{ items?: CalendarEvent[]; nextPageToken?: string }>(asker, "calendar", `calendars/${enc(calendar)}/events`,
        { query: { timeMin: new Date(start).toISOString(), timeMax: new Date(end).toISOString(), singleEvents: true, orderBy: "startTime", q: query,
          maxResults: most, pageToken: next, timeZone: timezone } });
      return { timezone, events: (found.items ?? []).map(eventShown), nextPageToken: found.nextPageToken ?? null };
    },
  }),
  add_event: tool({
    title: "Add event",
    description: "Add an event to the person's calendar. Guests get an invitation.",
    input: { ...eventFields, start: when("When it starts"), end: when("When it ends"),
      allDay: z.boolean().default(false).describe("An all-day event: `start` and `end` are days, and `end` is the day after the last.") },
    hints: CHANGE,
    ask: async (asker, input) => eventShown(await google<CalendarEvent>(asker, "calendar", `calendars/${enc(input.calendarId)}/events`,
      { method: "POST", query: invites(input.attendees), json: eventBody(input) })),
  }),
  change_event: tool({
    title: "Change event",
    description: "Move or edit one of the person's events: only the fields given change. Guests hear of the change.",
    input: { id: id("The event's id, from list_events."), ...eventFields, summary: eventFields.summary.optional(),
      start: when("When it starts").optional(), end: when("When it ends").optional(),
      allDay: z.boolean().optional().describe("Whether `start` and `end` are days.") },
    hints: CHANGE,
    ask: async (asker, { id: which, ...input }) => {
      const body = eventBody(input);
      if (!Object.keys(body).length) throw new Refusal("Say what to change: summary, start, end, location, description or attendees.");
      return eventShown(await google<CalendarEvent>(asker, "calendar", `calendars/${enc(input.calendarId)}/events/${which}`,
        { method: "PATCH", query: { sendUpdates: "all" }, json: body }));
    },
  }),
  delete_event: tool({
    title: "Delete event",
    description: "Take an event off the person's calendar. Guests hear it is cancelled. Only when the person asks.",
    input: { id: id("The event's id, from list_events."), calendarId },
    hints: FINAL,
    ask: async (asker, { id: which, calendarId: calendar }) => {
      await google(asker, "calendar", `calendars/${enc(calendar)}/events/${which}`, { method: "DELETE", query: { sendUpdates: "all" } });
      return { id: which, deleted: true };
    },
  }),
};

// Drive

type DriveFile = { id: string; name: string; mimeType: string; size?: string; webViewLink?: string; parents?: string[]; trashed?: boolean };
const EXPORTS: Record<string, string> = { [DOC]: "text/plain", "application/vnd.google-apps.spreadsheet": "text/csv",
  "application/vnd.google-apps.presentation": "text/plain" };
const TEXT_TYPES = /^(?:text\/|application\/(?:json|xml|csv|x-yaml|javascript))/;
const MAX_TEXT_FILE = 10_000_000;

/** Drive's search words: a name or the words inside, out of the bin. */
const driveQuery = (words: string) => {
  const quoted = words.replaceAll("\\", "\\\\").replaceAll("'", "\\'");
  return `(name contains '${quoted}' or fullText contains '${quoted}') and trashed = false`;
};

async function fileText(asker: Asker, file: DriveFile): Promise<string> {
  if (EXPORTS[file.mimeType]) {
    return google<string>(asker, "drive", `files/${file.id}/export`, { query: { mimeType: EXPORTS[file.mimeType] }, text: true });
  }
  if (TEXT_TYPES.test(file.mimeType) && Number(file.size ?? 0) <= MAX_TEXT_FILE) {
    return google<string>(asker, "drive", `files/${file.id}`, { query: { alt: "media" }, text: true });
  }
  throw new Refusal(`read_file reads the words of Docs, Sheets, Slides and text files up to 10 MB, not PDFs, images or other files. ` +
    `Open "${file.name}" in Drive: ${file.webViewLink ?? `https://drive.google.com/file/d/${file.id}/view`}`);
}

const DRIVE = {
  search_files: tool({
    title: "Search files",
    description: "Drive files whose name or words hold the query, out of the bin, with each file's type, link and folder.",
    input: { query: z.string().trim().min(1).max(200).describe("Words in the file's name or inside it."), limit: limit(10), pageToken },
    hints: READ,
    ask: async (asker, { query, limit: most, pageToken: next }) => {
      const found = await google<{ files?: DriveFile[]; nextPageToken?: string }>(asker, "drive", "files",
        { query: { q: driveQuery(query), pageSize: most, pageToken: next, fields: `nextPageToken, files(${FILE_FIELDS})` } });
      return { files: found.files ?? [], nextPageToken: found.nextPageToken ?? null };
    },
  }),
  read_file: tool({
    title: "Read file",
    description: `A Drive file's words, at most ${TEXT_CAP} characters: a Doc or Slides as text, a Sheet's first sheet as CSV, or a text ` +
      "file. It refuses a PDF, an image and other files, and gives the file's Drive link instead.",
    input: { id: id("The file's id, from search_files.") },
    hints: READ,
    ask: async (asker, { id: which }) => {
      const file = await google<DriveFile>(asker, "drive", `files/${which}`, { query: { fields: FILE_FIELDS } });
      return { id: file.id, name: file.name, mimeType: file.mimeType, link: file.webViewLink ?? null, ...capped(await fileText(asker, file)) };
    },
  }),
  save_file: tool({
    title: "Save file",
    description: "Save words as a new Google Doc, or a plain text file, in the person's Drive.",
    input: { name: line("The file's name."), text: z.string().max(1_000_000).describe("What the file says."),
      kind: z.enum(["doc", "text"]).default("doc").describe("A Google Doc, or a plain text file."),
      folderId: id("The folder to save it in; the top of My Drive when left out.").optional() },
    hints: CHANGE,
    ask: async (asker, { name, text, kind, folderId }) => {
      const boundary = `relay-${crypto.randomUUID()}`;
      const about = { name, mimeType: kind === "doc" ? DOC : "text/plain", ...folderId && { parents: [folderId] } };
      const body = [`--${boundary}`, "Content-Type: application/json; charset=UTF-8", "", JSON.stringify(about), `--${boundary}`,
        "Content-Type: text/plain; charset=UTF-8", "", text, `--${boundary}--`].join("\r\n");
      return google<DriveFile>(asker, "drive", "upload/files", { method: "POST", query: { uploadType: "multipart", fields: FILE_FIELDS },
        type: `multipart/related; boundary=${boundary}`, body });
    },
  }),
  change_file: tool({
    title: "Change file",
    description: "Rename a Drive file, move it to another folder, or put it in the bin, or take it out. The bin keeps it 30 days; nothing " +
      "deletes for ever.",
    input: { id: id("The file's id, from search_files."), name: line("Its new name.").optional(),
      moveTo: id("The id of the folder to move it to.").optional(), bin: z.boolean().optional().describe("true puts it in the bin; false takes it out.") },
    hints: CHANGE,
    ask: async (asker, { id: which, name, moveTo, bin }) => {
      if (name === undefined && moveTo === undefined && bin === undefined) throw new Refusal("Say what to change: name, moveTo or bin.");
      const from = moveTo ? (await google<DriveFile>(asker, "drive", `files/${which}`, { query: { fields: "parents" } })).parents ?? [] : [];
      return google<DriveFile>(asker, "drive", `files/${which}`, { method: "PATCH", json: { name, trashed: bin },
        query: { fields: FILE_FIELDS, addParents: moveTo, removeParents: moveTo ? from.join(",") : undefined } });
    },
  }),
};

// Contacts

type Person = { names?: { displayName?: string }[]; emailAddresses?: { value?: string }[]; phoneNumbers?: { value?: string }[] };
const MASK = "names,emailAddresses,phoneNumbers";
const personShown = (person: Person, saved: boolean) => ({ name: person.names?.[0]?.displayName ?? null,
  emails: person.emailAddresses?.flatMap(email => email.value ?? []) ?? [], phones: person.phoneNumbers?.flatMap(phone => phone.value ?? []) ?? [], saved });

const CONTACTS = {
  find_contact: tool({
    title: "Find contact",
    description: "A person's name, email addresses and phone numbers, from the person's saved contacts and the people they email but " +
      "never saved (`saved: false`).",
    input: { query: z.string().trim().min(1).max(200).describe("A name, an email address or a phone number, or the start of one."), limit: limit(10) },
    hints: READ,
    ask: async (asker, { query, limit: most }) => {
      const search = (path: string, words: string) => google<{ results?: { person: Person }[] }>(asker, "contacts", path,
        { query: { query: words, readMask: MASK, pageSize: most } });
      // Google's People API asks for an empty search first, to warm its cache; without it, a search can miss people.
      const both = (words: string) => Promise.all([search("people:searchContacts", words), search("otherContacts:search", words)]);
      await both("");
      const [saved, other] = await both(query);
      return { contacts: [...(saved.results ?? []).map(found => personShown(found.person, true)),
        ...(other.results ?? []).map(found => personShown(found.person, false))].slice(0, most) };
    },
  }),
};

/** Every Google tool, in the order an AI app lists them. */
export const GOOGLE_TOOLS = { ...GMAIL, ...CALENDAR, ...DRIVE, ...CONTACTS };
