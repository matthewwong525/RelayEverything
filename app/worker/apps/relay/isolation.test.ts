import { expect, it } from "vitest";
import { handleApp } from "../index";
import { photoById, photoPage } from "./queries";
import { spaceOf, vouch } from "./space";
import { email } from "./inbox/email";
import { addressOf } from "./inbox/links";
import { fixture, inboxEnv, mailTo } from "../../../tests/relay-inbox";
import { ANA, BEN, ben, benPhone, bucket, call, env, laptop, matthew, NOW, owner, phone, request, rows, sendPhoto, spaces, type Who } from "../../../tests/relay";

const ANA_RING = "aaaaaaaa-0000-4000-8000-0000000000a1";
const BEN_RING = "bbbbbbbb-0000-4000-8000-0000000000b1";
const SOUND = [0, 0, 0, 24, 102, 116, 121, 112, 77, 52, 65, 32];

const note = (clientId: string, text: string) => ({ clientId, text, createdAt: NOW - 60_000 });
const texts = async (who: Who) => (await call(who, "GET", "timeline")).json.notes.map(item => item.text);
/** A stored ring note in a person's space, its recording at `key`. */
const ringNote = (person: string, device: string, id: string, key: string) => spaces.sql(person).prepare(`INSERT INTO relay_notes (id, device_id,
  source, delivery_id, text, audio_key, recorded_at, created_at) VALUES (?, ?, 'ring', ?, 'Ring note', ?, ?, 0)`).run(id, device, `delivery-${id}`, key, NOW);
const filesOf = (person: string) => spaceOf(env() as never, vouch("session", person)).files;
const play = (who: Who, id: string) => handleApp(request(who, "GET", `https://relay.example.com/apps/relay/api/audio?id=${id}`), env(),
  who && "kind" in who ? who : null);

it("lets Ana's session, phone key and Access email reach only Ana's rows", async () => {
  await call(phone, "POST", "notes", note("ana-note-01", "Ana's note"));
  await call(benPhone, "POST", "notes", note("ben-note-01", "Ben's note"));
  await call(phone, "POST", "health", { samples: [{ type: "steps", start: NOW - 60_000, end: NOW, value: 900, unit: "count", source: "Health Connect" }] });
  await call(phone, "POST", "locations", { points: [{ at: NOW, lat: 43.65, lon: -79.38, accuracy: 10 }] });
  await call(phone, "POST", "stays", { stays: [{ kind: "stay", start: NOW, end: NOW + 600_000, lat: 43.65, lon: -79.38, name: "Corner Café",
    source: "map" }] });
  await call(phone, "POST", "calendar", { events: [{ key: "w:1:1", calendar: "Work", title: "Ana's meeting", start: NOW, end: NOW + 60_000,
    allDay: false, people: [] }], removed: [] });
  expect(rows("relay_notes").map(row => row.text)).toEqual(["Ana's note"]);
  expect([rows("relay_calendar_events").length, rows("relay_calendar_events", BEN).length]).toEqual([1, 0]);
  expect(rows("relay_notes", BEN).map(row => row.text)).toEqual(["Ben's note"]);
  expect([rows("relay_health").length, rows("relay_locations").length]).toEqual([1, 1]);
  expect([rows("relay_health", BEN), rows("relay_locations", BEN), rows("relay_stays", BEN)]).toEqual([[], [], []]);
  expect(rows("relay_stays")).toHaveLength(1);
  for (const who of [matthew, owner]) expect(await texts(who)).toEqual(["Ana's note"]);
  expect((await call(ben, "GET", "summary", { day: "2026-11-05" })).json).toMatchObject({ notes: 1, steps: 0, places: [], events: [] });
  expect((await call(matthew, "GET", "summary", { day: "2026-11-05" })).json.events).toMatchObject([{ title: "Ana's meeting" }]);
});

it("never shows Ben Ana's notes or chats, and lets him delete none of hers", async () => {
  await call(phone, "POST", "notes", note("ana-note-01", "Ana's note"));
  await call(laptop, "POST", "chats", { sessionId: "ana-session-0001", project: "relay-ring", startedAt: NOW - 60_000,
    messages: [{ seq: 0, role: "you", text: "Ana's question", at: NOW - 60_000 }] });
  const chat = rows("relay_chats")[0].id as string;
  expect(await texts(ben)).toEqual([]);
  expect((await call(ben, "GET", "chats", { q: "question" })).json.chats).toEqual([]);
  expect((await call(ben, "GET", "chat", { id: chat })).status).toBe(404);
  expect((await call(ben, "DELETE", "chat", { id: chat })).status).toBe(404);
  expect(rows("relay_chats")).toHaveLength(1);
  expect((await call(matthew, "GET", "chats", { q: "question" })).json.chats).toHaveLength(1);
});

it("answers not found when Ana asks for Ben's recording, by its note id or by its name", async () => {
  ringNote(BEN, "d-ben", BEN_RING, await filesOf(BEN).put(BEN_RING, new Uint8Array(SOUND).buffer));
  expect((await play(ben, BEN_RING)).status).toBe(200);
  for (const who of [matthew, owner]) expect((await play(who, BEN_RING)).status).toBe(404);
  // A row in Ana's space that names Ben's object still opens nothing: it is outside her folder.
  ringNote(ANA, "d-ipad", ANA_RING, `people/${BEN}/${BEN_RING}`);
  expect((await play(matthew, ANA_RING)).status).toBe(404);
});

it("stores a recording sealed, plays back the bytes sent, and opens no copy under another name", async () => {
  const name = await filesOf(ANA).put(ANA_RING, new Uint8Array(SOUND).buffer);
  ringNote(ANA, "d-ipad", ANA_RING, name);
  expect(name).toBe(`people/${ANA}/${ANA_RING}`);
  const stored = bucket.objects.get(name)!;
  expect(stored).not.toEqual(new Uint8Array(SOUND));
  expect(Buffer.from(stored).includes(Buffer.from(SOUND))).toBe(false);
  expect(new Uint8Array(await (await play(matthew, ANA_RING)).arrayBuffer())).toEqual(new Uint8Array(SOUND));
  const copy = "aaaaaaaa-0000-4000-8000-0000000000a2";
  bucket.objects.set(`people/${ANA}/${copy}`, stored);
  ringNote(ANA, "d-ipad", copy, `people/${ANA}/${copy}`);
  expect((await play(matthew, copy)).status).toBe(404);
});

it("opens a photo only under the name it was sealed with, and deletes no file outside the person's folder", async () => {
  const files = filesOf(ANA);
  const name = await files.put(`photos/${ANA_RING}`, new Uint8Array(SOUND).buffer);
  expect(name).toBe(`people/${ANA}/photos/${ANA_RING}`);
  expect(await files.open(name)).toEqual(new Uint8Array(SOUND));
  // The same sealed bytes under a recording's name, or another photo's, never open.
  for (const other of [files.nameOf(ANA_RING), files.nameOf("photos/aaaaaaaa-0000-4000-8000-0000000000a2")]) {
    bucket.objects.set(other, bucket.objects.get(name)!);
    expect(await files.open(other)).toBeNull();
  }
  // A delete names only files in the person's own folder; another person's name, or none, deletes nothing.
  bucket.objects.set(filesOf(BEN).nameOf(`photos/${ANA_RING}`), new Uint8Array([1]));
  await files.remove([filesOf(BEN).nameOf(`photos/${ANA_RING}`)]);
  await files.remove([]);
  expect(bucket.objects.has(filesOf(BEN).nameOf(`photos/${ANA_RING}`))).toBe(true);
  bucket.objects.delete(filesOf(BEN).nameOf(`photos/${ANA_RING}`));
});

it("never gives Ana's queries or count Ben's photos", async () => {
  await sendPhoto(benPhone);
  const benPhoto = String(rows("relay_photos", BEN)[0].id);
  const anaDb = spaceOf(env() as never, vouch("grant", ANA)).db;
  expect((await photoPage(anaDb, { limit: 50 })).photos).toEqual([]);
  expect(await photoById(anaDb, benPhoto)).toBeNull();
  expect((await call(matthew, "GET", "photos")).json).toEqual({ count: 0 });
  expect((await call(matthew, "POST", "photos/delete", { confirm: "delete" })).json).toEqual({ deleted: 0 });
  expect(rows("relay_photos", BEN)).toHaveLength(1);
  expect(await photoById(spaceOf(env() as never, vouch("grant", BEN)).db, benPhoto)).toMatchObject({ id: benPhoto });
});

it("never opens Ana's note file for Ben's session, and Ben's key can't add a file to her note", async () => {
  const file = { id: "file-ana-0001", name: "passport.pdf", type: "application/pdf", size: 4 };
  await call(phone, "POST", "notes", { ...note("ana-note-01", "Ana's file"), attachments: [file] });
  const send = (who: Who) => handleApp(request(who, "POST", "https://relay.example.com/apps/relay/api/attachments", { body: new Uint8Array(4),
    headers: { "X-Note-Client-Id": "ana-note-01", "X-Attachment-Id": file.id } }), env(), null);
  expect((await send(benPhone)).status).toBe(404);
  expect((await send(phone)).status).toBe(200);
  const open = (who: Who) => handleApp(request(who, "GET", `https://relay.example.com/apps/relay/api/attachment?id=${file.id}`), env(), null);
  expect((await open(matthew)).status).toBe(200);
  expect((await open(ben)).status).toBe(404);
});

it("makes mail to Ana's notes address a note in Ana's space only, never Ben's", async () => {
  const address = (await addressOf(inboxEnv(), ANA))!;
  await email(mailTo(address, fixture("forwarded-pdf.eml")), inboxEnv());
  expect(rows("relay_notes").map(row => row.client_id?.toString().slice(0, 6))).toEqual(["email:"]);
  expect([rows("relay_notes", BEN), rows("relay_attachments", BEN)]).toEqual([[], []]);
  expect([...bucket.objects.keys()].every(key => key.startsWith(`people/${ANA}/`))).toBe(true);
});
