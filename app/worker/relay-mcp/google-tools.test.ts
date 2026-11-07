import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ANA, BEN, fakeSpaces, queue } from "../../tests/relay";
import { NOT_CONNECTED } from "../apps/relay/google/proxy";
import { keep } from "../apps/relay/google/token";
import { GOOGLE } from "../apps/relay/sign-in/oidc";
import { spaceOf, vouch, type SpaceEnv } from "../apps/relay/space";
import { GOOGLE_AGAIN } from "./answers";
import type { GrantProps } from "./env";
import { TEXT_CAP } from "./google-tools";
import { mcpHandler } from "./tools";

const ENV = { RELAY_GOOGLE_CLIENT_ID: "client.apps.googleusercontent.com", RELAY_GOOGLE_SIGN_IN_SECRET: "client-secret" };
const GMAIL = "GET gmail.googleapis.com/gmail/v1/users/me/";
const CALENDAR = "www.googleapis.com/calendar/v3/calendars/primary/events";
const DRIVE = "www.googleapis.com/drive/v3/files";
const GRANT: GrantProps = { personId: ANA, adds: true, google: true, deviceId: "e0000000-0000-4000-8000-000000000001", name: "Claude" };
const data = (text: string) => btoa(String.fromCharCode(...new TextEncoder().encode(text))).replaceAll("+", "-").replaceAll("/", "_");
const unraw = (raw: string) => new TextDecoder().decode(Uint8Array.from(atob(raw.replaceAll("-", "+").replaceAll("_", "/")), c => c.charCodeAt(0)));

type Seen = { method: string; url: URL; body: string; type: string | null };
const seen: Seen[] = [];
/** Google's answer to each `METHOD host/path`: JSON, words, a Response, an Error to throw, or a function of the URL.
 *  A missing one is Google's 404. */
let replies: Record<string, unknown>;
let spaces: ReturnType<typeof fakeSpaces>;

beforeEach(async () => {
  seen.length = 0;
  replies = {};
  spaces = fakeSpaces();
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    if (url === GOOGLE.token) return Response.json({ access_token: "ya29.ana", expires_in: 3600 });
    const at = new URL(url);
    seen.push({ method: init.method!, url: at, body: init.body ? String(init.body) : "", type: new Headers(init.headers).get("content-type") });
    const found = replies[`${init.method} ${at.host}${at.pathname}`];
    if (found === undefined) return Response.json({ error: { message: "Requested entity was not found." } }, { status: 404 });
    if (found instanceof Error) throw found;
    if (found instanceof Response) return found;
    if (typeof found === "function") return (found as (url: URL) => Response)(at);
    return typeof found === "string" ? new Response(found || null, { status: found ? 200 : 204 }) : Response.json(found);
  }));
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  await keep(spaceOf({ SPACES: spaces.SPACES } as SpaceEnv, vouch("session", ANA)), { email: "ana@gmail.example", scopes: [], refreshToken: "1//r" });
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

/** A tool's answer as JSON, or its refusal's text, through an AI app with this grant. */
async function ask(name: string, args: Record<string, unknown>, props: GrantProps = GRANT) {
  const client = new Client({ name: "test", version: "1.0.0" });
  await client.connect(new StreamableHTTPClientTransport(new URL("https://relay-mcp.example.com/mcp"), { fetch: (url, init) =>
    mcpHandler.fetch(new Request(url, init), { SPACES: spaces.SPACES, RELAY_WEBHOOKS: queue as never, ...ENV }, { props }) }));
  const { content, isError } = await client.callTool({ name, arguments: args }) as { content: { text: string }[]; isError?: boolean };
  return isError ? { refused: content[0].text } : JSON.parse(content[0].text);
}
const query = (at: number) => Object.fromEntries(seen[at].url.searchParams);
const json = (at: number) => JSON.parse(seen[at].body);

const message = (id: string, more: object = {}) => ({ id, threadId: "t1", snippet: "Lunch at noon?", labelIds: ["INBOX", "UNREAD"],
  payload: { headers: [{ name: "From", value: "Sam <sam@example.com>" }, { name: "Subject", value: "Lunch" }, { name: "Date", value: "Thu, 5 Nov 2026" },
    { name: "Message-ID", value: "<m1@example.com>" }], ...more } });

it("searches email with Gmail's own words and shows each match's sender, subject and snippet", async () => {
  replies[`${GMAIL}messages`] = { messages: [{ id: "m1" }], nextPageToken: "p2" };
  replies[`${GMAIL}messages/m1`] = message("m1");
  expect(await ask("search_email", { query: "from:sam lunch", limit: 5 })).toEqual({ nextPageToken: "p2", messages: [{ id: "m1", threadId: "t1",
    from: "Sam <sam@example.com>", to: null, subject: "Lunch", date: "Thu, 5 Nov 2026", snippet: "Lunch at noon?", labels: ["INBOX", "UNREAD"], unread: true }] });
  expect(query(0)).toEqual({ q: "from:sam lunch", maxResults: "5" });
  expect(seen[1].url.searchParams.getAll("metadataHeaders")).toEqual(["From", "To", "Cc", "Subject", "Date"]);
  expect(await ask("search_email", { query: "x", limit: 26 })).toMatchObject({ refused: expect.stringContaining("limit") });
});

it("reads an email as plain text, its HTML as words when it has no text, cut at the cap, and names attachments only", async () => {
  replies[`${GMAIL}messages/m1`] = message("m1", { parts: [{ mimeType: "text/html", body: { data: data("<p>See you <b>at noon</b>&amp; bring it</p>") } },
    { mimeType: "application/pdf", filename: "menu.pdf", body: { attachmentId: "a1" } }] });
  expect(await ask("read_email", { id: "m1" })).toMatchObject({ id: "m1", text: "See you at noon& bring it", cut: false, attachments: ["menu.pdf"] });
  replies[`${GMAIL}threads/t1`] = { messages: [message("m1", { body: { data: data("a".repeat(TEXT_CAP - 5)) }, mimeType: "text/plain" }),
    message("m2", { body: { data: data("b".repeat(50)) }, mimeType: "text/plain" })] };
  const thread = await ask("read_email", { id: "t1", thread: true });
  expect(thread.messages.map((one: { text: string; cut: boolean }) => [one.text.length, one.cut])).toEqual([[TEXT_CAP - 5, false], [5, true]]);
  expect(await ask("read_email", { id: "../m1" })).toHaveProperty("refused");
});

it("sends a new email as plain text, and a reply in its thread to the sender, with Re:", async () => {
  replies["POST gmail.googleapis.com/gmail/v1/users/me/messages/send"] = { id: "s1", threadId: "t9" };
  expect(await ask("send_email", { to: ["sam@example.com"], subject: "Café plans", text: "Noon works." })).toEqual({ id: "s1", threadId: "t9", sent: true });
  const sent = unraw(json(0).raw);
  expect(sent).toMatch(/^To: sam@example.com\r\nSubject: =\?UTF-8\?B\?[^?]+\?=\r\nMIME-Version: 1.0\r\n/);
  expect(sent).toContain(`\r\n\r\n${btoa("Noon works.")}`);
  replies[`${GMAIL}messages/m1`] = message("m1");
  await ask("send_email", { replyTo: "m1", text: "Yes." });
  const reply = json(2);
  expect(reply.threadId).toBe("t1");
  expect(unraw(reply.raw)).toMatch(/^To: Sam <sam@example.com>\r\nSubject: Re: Lunch\r\nIn-Reply-To: <m1@example.com>\r\nReferences: <m1@example.com>\r\n/);
  expect(await ask("send_email", { text: "Hi" })).toEqual({ refused: "Say who it goes to in `to`." });
  expect(await ask("send_email", { to: ["sam@example.com"], subject: "Hi\r\nBcc: eve@example.com", text: "x" })).toHaveProperty("refused");
});

it("puts a draft in Gmail's drafts, and sends nothing", async () => {
  replies["POST gmail.googleapis.com/gmail/v1/users/me/drafts"] = { id: "d1", message: { id: "m5", threadId: "t5" } };
  expect(await ask("draft_email", { to: ["sam@example.com"], text: "Draft." })).toEqual({ draftId: "d1", id: "m5", threadId: "t5" });
  expect(Object.keys(json(0).message)).toEqual(["raw"]);
  expect(seen.map(one => one.url.pathname)).toEqual(["/gmail/v1/users/me/drafts"]);
});

it("archives, marks and labels an email, and puts it in the bin, never deleting it", async () => {
  replies["POST gmail.googleapis.com/gmail/v1/users/me/messages/m1/modify"] = {};
  replies["POST gmail.googleapis.com/gmail/v1/users/me/threads/t1/trash"] = {};
  expect(await ask("change_email", { id: "m1", archive: true, read: true, addLabels: ["STARRED"] }))
    .toEqual({ id: "m1", added: ["STARRED"], removed: ["INBOX", "UNREAD"] });
  expect(json(0)).toEqual({ addLabelIds: ["STARRED"], removeLabelIds: ["INBOX", "UNREAD"] });
  expect(await ask("change_email", { id: "t1", thread: true, bin: true })).toEqual({ id: "t1", bin: true });
  expect(await ask("change_email", { id: "m1" })).toEqual({ refused: "Say what to change: archive, read, addLabels, removeLabels or bin." });
});

it("lists events in the zone, and adds, moves and deletes one, telling guests", async () => {
  replies[`GET ${CALENDAR}`] = { items: [{ id: "e1", summary: "Lunch", start: { dateTime: "2026-11-05T12:00:00-05:00" },
    end: { dateTime: "2026-11-05T13:00:00-05:00" }, attendees: [{ email: "sam@example.com" }] }] };
  expect(await ask("list_events", { from: "2026-11-05", to: "2026-11-06" })).toMatchObject({ timezone: "America/Toronto",
    events: [{ id: "e1", summary: "Lunch", allDay: false, attendees: ["sam@example.com"] }], nextPageToken: null });
  expect(query(0)).toMatchObject({ timeMin: "2026-11-05T05:00:00.000Z", timeMax: "2026-11-06T05:00:00.000Z", singleEvents: "true", orderBy: "startTime" });
  expect(await ask("list_events", { from: "2026-11-06", to: "2026-11-05" })).toEqual({ refused: "`from` must come before `to`." });
  replies[`POST ${CALENDAR}`] = { id: "e2" };
  await ask("add_event", { summary: "Fab visit", start: "2026-11-06T09:00", end: "2026-11-06T10:00", attendees: ["sam@example.com"] });
  expect([json(1), query(1)]).toEqual([{ summary: "Fab visit", start: { dateTime: "2026-11-06T09:00:00-05:00", timeZone: "America/Toronto" },
    end: { dateTime: "2026-11-06T10:00:00-05:00", timeZone: "America/Toronto" }, attendees: [{ email: "sam@example.com" }] }, { sendUpdates: "all" }]);
  await ask("add_event", { summary: "Holiday", start: "2026-12-24", end: "2026-12-27", allDay: true });
  expect([json(2).start, json(2).end, query(2)]).toEqual([{ date: "2026-12-24" }, { date: "2026-12-27" }, { sendUpdates: "none" }]);
  replies[`PATCH ${CALENDAR}/e1`] = { id: "e1" };
  await ask("change_event", { id: "e1", start: "2026-11-05T12:30", end: "2026-11-05T13:30" });
  expect(Object.keys(json(3))).toEqual(["start", "end"]);
  expect(await ask("change_event", { id: "e1" })).toHaveProperty("refused");
  replies[`DELETE ${CALENDAR}/e1`] = "";
  expect(await ask("delete_event", { id: "e1" })).toEqual({ id: "e1", deleted: true });
  expect([seen.at(-1)!.method, query(seen.length - 1)]).toEqual(["DELETE", { sendUpdates: "all" }]);
});

it("finds Drive files, reads a Doc, and refuses a PDF or an image with its link, changing nothing in Drive", async () => {
  replies[`GET ${DRIVE}`] = { files: [{ id: "f1", name: "Ring plan", mimeType: "application/vnd.google-apps.document" }] };
  expect(await ask("search_files", { query: "Sam's plan" })).toMatchObject({ files: [{ id: "f1" }], nextPageToken: null });
  expect(query(0).q).toBe("(name contains 'Sam\\'s plan' or fullText contains 'Sam\\'s plan') and trashed = false");
  replies[`GET ${DRIVE}/f1`] = { id: "f1", name: "Ring plan", mimeType: "application/vnd.google-apps.document" };
  replies[`GET ${DRIVE}/f1/export`] = "Steel stiffener.";
  expect(await ask("read_file", { id: "f1" })).toMatchObject({ id: "f1", text: "Steel stiffener.", cut: false });
  replies[`GET ${DRIVE}/p1`] = { id: "p1", name: "Invoice.pdf", mimeType: "application/pdf", webViewLink: "https://drive.google.com/file/d/p1/view" };
  replies[`GET ${DRIVE}/i1`] = { id: "i1", name: "Ring.png", mimeType: "image/png" };
  seen.length = 0;
  const pdf = (await ask("read_file", { id: "p1" })).refused;
  expect(pdf).toMatch(/^read_file reads the words of Docs, Sheets, Slides and text files .* not PDFs/);
  expect(pdf).toContain('"Invoice.pdf" in Drive: https://drive.google.com/file/d/p1/view');
  expect((await ask("read_file", { id: "i1" })).refused).toContain('"Ring.png" in Drive: https://drive.google.com/file/d/i1/view');
  expect(seen.map(one => `${one.method} ${one.url.pathname}`)).toEqual(["GET /drive/v3/files/p1", "GET /drive/v3/files/i1"]);
});

it("saves a new Doc, and renames, moves and bins a file without deleting it", async () => {
  replies["POST www.googleapis.com/upload/drive/v3/files"] = { id: "n1", name: "Notes" };
  expect(await ask("save_file", { name: "Notes", text: "Hello." })).toEqual({ id: "n1", name: "Notes" });
  expect([query(0).uploadType, seen[0].type]).toEqual(["multipart", expect.stringMatching(/^multipart\/related; boundary=relay-/)]);
  expect(seen[0].body).toContain('"mimeType":"application/vnd.google-apps.document"');
  replies[`GET ${DRIVE}/f1`] = { parents: ["old"] };
  replies[`PATCH ${DRIVE}/f1`] = { id: "f1" };
  await ask("change_file", { id: "f1", moveTo: "new", name: "Plan" });
  expect([json(2), query(2)]).toMatchObject([{ name: "Plan" }, { addParents: "new", removeParents: "old" }]);
  await ask("change_file", { id: "f1", bin: true });
  expect(json(3)).toEqual({ trashed: true });
  expect(seen.some(one => one.method === "DELETE")).toBe(false);
});

it("finds a contact among saved contacts and the people the person emails", async () => {
  replies["GET people.googleapis.com/v1/people:searchContacts"] = { results: [{ person: { names: [{ displayName: "Sam Lee" }],
    emailAddresses: [{ value: "sam@example.com" }] } }] };
  replies["GET people.googleapis.com/v1/otherContacts:search"] = { results: [{ person: { emailAddresses: [{ value: "sam.l@example.org" }] } }] };
  expect(await ask("find_contact", { query: "sam" })).toEqual({ contacts: [{ name: "Sam Lee", emails: ["sam@example.com"], phones: [], saved: true },
    { name: null, emails: ["sam.l@example.org"], phones: [], saved: false }] });
  // Google's warm-up, an empty search of each, goes first.
  expect(seen.map(one => one.url.searchParams.get("query"))).toEqual(["", "", "sam", "sam"]);
  expect(seen.map(one => one.url.pathname).sort()).toEqual(["/v1/otherContacts:search", "/v1/otherContacts:search", "/v1/people:searchContacts",
    "/v1/people:searchContacts"]);
  expect(seen.every(one => one.url.searchParams.get("readMask") === "names,emailAddresses,phoneNumbers")).toBe(true);
});

it("asks an app from before Google to connect again, a person to connect Google, and passes Google's refusal on", async () => {
  expect(await ask("search_email", { query: "x" }, { ...GRANT, google: undefined })).toEqual({ refused: GOOGLE_AGAIN });
  expect(await ask("search_email", { query: "x" }, { ...GRANT, personId: BEN })).toEqual({ refused: NOT_CONNECTED });
  expect(await ask("read_email", { id: "gone" })).toEqual({ refused: "Google answered 404: Requested entity was not found." });
  expect(seen.filter(one => one.method !== "GET")).toEqual([]);
});

it("answers what Google leaves out as empty, not as an error", async () => {
  replies[`${GMAIL}messages`] = {};
  expect(await ask("search_email", { query: "nothing" })).toEqual({ messages: [], nextPageToken: null });
  replies[`${GMAIL}messages/m2`] = { id: "m2", threadId: "t2" };
  expect(await ask("read_email", { id: "m2" })).toEqual({ id: "m2", threadId: "t2", from: null, to: null, cc: null, subject: null, date: null,
    snippet: "", labels: [], unread: false, text: "", cut: false, attachments: [] });
  replies[`${GMAIL}threads/t3`] = {};
  expect(await ask("read_email", { id: "t3", thread: true })).toEqual({ threadId: "t3", messages: [] });
  replies[`GET ${CALENDAR}`] = {};
  expect((await ask("list_events", { from: "2026-11-05", to: "2026-11-06" })).events).toEqual([]);
  replies[`GET ${DRIVE}`] = {};
  expect(await ask("search_files", { query: "plan" })).toEqual({ files: [], nextPageToken: null });
  replies["GET people.googleapis.com/v1/people:searchContacts"] = { results: [{ person: { phoneNumbers: [{ value: "+1 555 0100" }, {}] } }] };
  replies["GET people.googleapis.com/v1/otherContacts:search"] = { results: [{ person: { emailAddresses: [{}] } }] };
  expect((await ask("find_contact", { query: "555" })).contacts).toEqual([{ name: null, emails: [], phones: ["+1 555 0100"], saved: true },
    { name: null, emails: [], phones: [], saved: false }]);
  replies["GET people.googleapis.com/v1/people:searchContacts"] = {};
  replies["GET people.googleapis.com/v1/otherContacts:search"] = {};
  expect(await ask("find_contact", { query: "nobody" })).toEqual({ contacts: [] });
});

it("replies to the address given, keeps a subject that has Re:, and sends a reply with no sender to no one", async () => {
  replies["POST gmail.googleapis.com/gmail/v1/users/me/drafts"] = { id: "d1", message: { id: "m5", threadId: "t1" } };
  replies[`${GMAIL}messages/m1`] = message("m1", { headers: [{ name: "Subject", value: "Re: Lunch" }] });
  await ask("draft_email", { replyTo: "m1", to: ["kim@example.com"], text: "Yes." });
  expect(unraw(json(1).message.raw)).toMatch(/^To: kim@example.com\r\nSubject: Re: Lunch\r\nMIME-Version/);
  replies[`${GMAIL}messages/m1`] = { id: "m1", threadId: "t1" };
  await ask("draft_email", { replyTo: "m1", text: "Yes." });
  expect(unraw(json(3).message.raw)).toMatch(/^Subject: Re: \r\nMIME-Version/);
});

it("takes an email out of the bin, and puts it back in the inbox, unread", async () => {
  replies["POST gmail.googleapis.com/gmail/v1/users/me/messages/m1/untrash"] = {};
  replies["POST gmail.googleapis.com/gmail/v1/users/me/messages/m1/modify"] = {};
  expect(await ask("change_email", { id: "m1", bin: false })).toEqual({ id: "m1", bin: false });
  expect(await ask("change_email", { id: "m1", archive: false, read: false })).toEqual({ id: "m1", added: ["INBOX", "UNREAD"], removed: [] });
});

it("refuses an all-day event on a time and an event at no time, and shows an event's notes", async () => {
  expect(await ask("add_event", { summary: "Trip", start: "2026-12-24T09:00", end: "2026-12-27", allDay: true }))
    .toEqual({ refused: "An all-day event starts and ends on a day, as YYYY-MM-DD; its end is the day after." });
  expect(await ask("add_event", { summary: "Trip", start: "soon", end: "later" })).toEqual({ refused: "Give `start` and `end` as a day or an ISO time." });
  replies[`PATCH ${CALENDAR}/e1`] = { id: "e1", description: "Bring the ring.", start: { date: "2026-12-24" }, end: { date: "2026-12-25" } };
  expect(await ask("change_event", { id: "e1", description: "Bring the ring." })).toMatchObject({ description: "Bring the ring.", allDay: true,
    start: "2026-12-24", end: "2026-12-25" });
  expect(seen).toHaveLength(1);
});

it("reads a text file up to 10 MB, saves a text file in a folder, and refuses a change with nothing to change", async () => {
  const file = (about: object) => (url: URL) => url.searchParams.has("alt") ? new Response("Hello there.") : Response.json(about);
  replies[`GET ${DRIVE}/t1`] = file({ id: "t1", name: "notes.txt", mimeType: "text/plain", size: "12" });
  replies[`GET ${DRIVE}/t2`] = file({ id: "t2", name: "log.json", mimeType: "application/json" });
  replies[`GET ${DRIVE}/t3`] = { id: "t3", name: "big.csv", mimeType: "text/csv", size: "10000001" };
  expect(await ask("read_file", { id: "t1" })).toMatchObject({ text: "Hello there.", link: null });
  expect(query(1)).toEqual({ alt: "media" });
  expect((await ask("read_file", { id: "t2" })).text).toBe("Hello there.");
  expect((await ask("read_file", { id: "t3" })).refused).toMatch(/^read_file reads the words/);
  replies["POST www.googleapis.com/upload/drive/v3/files"] = { id: "n2" };
  await ask("save_file", { name: "notes.txt", text: "Hi.", kind: "text", folderId: "folder1" });
  expect(seen.at(-1)!.body).toContain('{"name":"notes.txt","mimeType":"text/plain","parents":["folder1"]}');
  replies[`GET ${DRIVE}/f1`] = {};
  replies[`PATCH ${DRIVE}/f1`] = { id: "f1" };
  await ask("change_file", { id: "f1", moveTo: "new" });
  expect(query(seen.length - 1)).toMatchObject({ addParents: "new", removeParents: "" });
  expect(await ask("change_file", { id: "f1" })).toEqual({ refused: "Say what to change: name, moveTo or bin." });
});

it("gives Google's own reason for a refusal, a plain one when it gives none, and lets a network fault through", async () => {
  replies[`${GMAIL}messages`] = Response.json({ error: "invalid_request", error_description: "Bad search." }, { status: 400 });
  expect(await ask("search_email", { query: "x" })).toEqual({ refused: "Google answered 400: Bad search." });
  replies[`${GMAIL}messages`] = new Response("<html>down</html>", { status: 500 });
  expect(await ask("search_email", { query: "x" })).toEqual({ refused: "Google answered 500: Google gave no reason." });
  replies[`${GMAIL}messages`] = new TypeError("offline");
  expect(await ask("search_email", { query: "x" })).toHaveProperty("refused", expect.stringContaining("offline"));
});

it("answers in words when Google's sign-in can't be renewed", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("offline"); }));
  await keep(spaceOf({ SPACES: spaces.SPACES } as SpaceEnv, vouch("session", ANA)), { email: "ana@gmail.example", scopes: [], refreshToken: "1//r2" });
  expect(await ask("search_email", { query: "x" })).toEqual({ refused: "Google's sign-in could not be reached. Try again." });
});
