import { expect, it, vi } from "vitest";
import { handleApp } from "../index";
import { hashToken } from "./people";
import { call, checker, env, laptop, lost, matthew, NOW, pebbleApp, phone, request, rows } from "../../../tests/relay";

const MINUTE = 60_000;
const SESSION = "0b6f3c1e-5d2a-4e8b-9c7f-1a2b3c4d5e6f";
const said = (seq: number, text = `Message ${seq}`, role = seq % 2 ? "ai" : "you") => ({ seq, role, text, at: NOW - 60 * MINUTE + seq * MINUTE });
const chat = (messages: object[], more: Record<string, unknown> = {}) =>
  ({ sessionId: SESSION, project: "relay-ring", startedAt: NOW - 60 * MINUTE, title: "Stiffener", messages, ...more });
const chatRows = () => rows("relay_chats");
const messageRows = () => rows("relay_chat_messages").map(row => [row.seq, row.role, row.text]);

it("stores a chat's messages once each, in order, and answers only how many it holds", async () => {
  expect(await call(laptop, "POST", "chats", chat([said(0), said(1)]))).toEqual({ status: 200, json: { stored: 2 } });
  expect(await call(laptop, "POST", "chats", chat([said(2, "Read pcb/relay.kicad_pcb", "step"), said(3)]))).toEqual({ status: 200, json: { stored: 4 } });
  expect(messageRows()).toEqual([[0, "you", "Message 0"], [1, "ai", "Message 1"], [2, "step", "Read pcb/relay.kicad_pcb"], [3, "ai", "Message 3"]]);
  expect(chatRows().map(row => [row.device_id, row.session_id, row.project, row.title, row.message_count, row.last_at]))
    .toEqual([["d-laptop", SESSION, "relay-ring", "Stiffener", 4, NOW - 57 * MINUTE]]);
  // Another session is another chat.
  expect((await call(laptop, "POST", "chats", chat([said(0)], { sessionId: "another-session-0001" }))).json).toEqual({ stored: 1 });
  expect(chatRows()).toHaveLength(2);
});

it("stores nothing new for a repeat, and changes no title, project or stored text", async () => {
  await call(laptop, "POST", "chats", chat([said(0), said(1)]));
  const again = await call(laptop, "POST", "chats", chat([said(0, "Changed"), said(1, "Changed too")], { title: "Another title", project: "other" }));
  expect(again).toEqual({ status: 200, json: { stored: 2 } });
  expect(messageRows()).toEqual([[0, "you", "Message 0"], [1, "ai", "Message 1"]]);
  expect(chatRows().map(row => [row.title, row.project])).toEqual([["Stiffener", "relay-ring"]]);
  // A send that overlaps adds only what is new.
  expect((await call(laptop, "POST", "chats", chat([said(1, "Changed"), said(2)]))).json).toEqual({ stored: 3 });
  expect(messageRows().map(row => row[2])).toEqual(["Message 0", "Message 1", "Message 2"]);
});

it("refuses a gap with the count it holds, so the sender resends from there", async () => {
  await call(laptop, "POST", "chats", chat([said(0)]));
  const gap = await call(laptop, "POST", "chats", chat([said(3), said(4)]));
  expect([gap.status, gap.json.stored]).toEqual([400, 1]);
  expect(messageRows()).toHaveLength(1);
  expect((await call(laptop, "POST", "chats", chat([said(1), said(2), said(3), said(4)]))).json).toEqual({ stored: 5 });
});

it("leaves no chat in the list for a refused first send, or a first send with no messages", async () => {
  const gap = await call(laptop, "POST", "chats", chat([said(3), said(4)]));
  expect([gap.status, gap.json.stored]).toEqual([400, 0]);
  expect(await call(laptop, "POST", "chats", chat([]))).toEqual({ status: 200, json: { stored: 0 } });
  expect([chatRows(), messageRows()]).toEqual([[], []]);
  expect((await call(matthew, "GET", "chats")).json.chats).toEqual([]);
  expect((await call(laptop, "POST", "chats", chat([said(0), said(1)]))).json).toEqual({ stored: 2 });
  expect(chatRows()).toHaveLength(1);
});

it("refuses a send over the caps with 413, and stores none of it", async () => {
  const many = Array.from({ length: 501 }, (_, seq) => said(seq));
  expect((await call(laptop, "POST", "chats", chat(many))).status).toBe(413);
  const huge = Array.from({ length: 21 }, (_, seq) => said(seq, "x".repeat(200_000)));
  expect((await call(laptop, "POST", "chats", chat(huge))).status).toBe(413);
  expect([chatRows(), messageRows()]).toEqual([[], []]);
  // At the caps, a send goes in whole, across several bound values.
  const full = Array.from({ length: 20 }, (_, seq) => said(seq, "y".repeat(200_000)));
  expect((await call(laptop, "POST", "chats", chat(full))).json).toEqual({ stored: 20 });
});

it("refuses a malformed send, and messages out of order", async () => {
  for (const wrong of [chat([said(0)], { sessionId: "x" }), chat([said(1), said(0)]), chat([said(0, "x".repeat(200_001))]),
    chat([{ ...said(0), role: "system" }]), chat([said(0)], { project: "" }), chat([{ ...said(0), at: NOW / 1000 }])]) {
    expect((await call(laptop, "POST", "chats", wrong)).status, JSON.stringify(wrong).slice(0, 80)).toBe(400);
  }
  const send = (init: RequestInit) => handleApp(request(laptop, "POST", "https://relay.example.com/apps/relay/api/chats", init), env(), null);
  const json = { "content-type": "application/json" };
  expect((await send({ body: "{", headers: json })).status).toBe(400);
  expect((await send({ body: "{}" })).status).toBe(400);
  expect((await send({ headers: json })).status).toBe(400);
  expect(chatRows()).toEqual([]);
});

it("takes chats only from a chat key: a phone, the Pebble app, a person or a revoked key is refused", async () => {
  for (const who of [phone, pebbleApp, matthew, checker, lost, null]) {
    expect((await call(who, "POST", "chats", chat([said(0)]))).status).toBe(403);
    expect((await call(who, "POST", "chat-saves", { sessionId: SESSION, title: "T", text: "S" })).status).toBe(403);
  }
  expect(chatRows()).toEqual([]);
});

it("keeps a save beside the chat, and shows the newest save's title as the chat's", async () => {
  expect((await call(laptop, "POST", "chat-saves", { sessionId: SESSION, title: "Plan", text: "Summary" })).status).toBe(404);
  await call(laptop, "POST", "chats", chat([said(0), said(1)]));
  expect(await call(laptop, "POST", "chat-saves", { sessionId: SESSION, title: "Stiffener plan", text: "Use 0.2 mm steel." }))
    .toEqual({ status: 200, json: { ok: true } });
  vi.setSystemTime(NOW + MINUTE);
  await call(laptop, "POST", "chat-saves", { sessionId: SESSION, title: "Stiffener plan, final", text: "Glue it." });
  const listed = await call(matthew, "GET", "chats");
  expect(listed.json.chats.map(item => [item.title, item.savedByAi, item.messages])).toEqual([["Stiffener plan, final", true, 2]]);
  const read = await call(matthew, "GET", "chat", { id: listed.json.chats[0].id });
  expect(read.json.saves.map(item => item.text)).toEqual(["Glue it.", "Use 0.2 mm steel."]);
  expect(messageRows()).toHaveLength(2);
  expect(chatRows()[0].title).toBe("Stiffener");
});

it("lists chats newest first, a page at a time, and finds every word in messages and saves", async () => {
  await call(laptop, "POST", "chats", chat([said(0, "How thick is the stiffener?"), said(1, "0.2 mm steel")], { sessionId: "session-one-0001" }));
  await call(laptop, "POST", "chats", chat([said(0, "Fix the webhook"), said(1, "Done"), said(2, "Thanks")], { sessionId: "session-two-0002" }));
  await call(laptop, "POST", "chats", chat([said(0, "Pick a battery")], { sessionId: "session-three-03", title: undefined }));
  await call(laptop, "POST", "chat-saves", { sessionId: "session-three-03", title: "Battery choice", text: "A 15 mAh cell from the stiffener supplier." });
  const titles = async (input: Record<string, unknown> = {}) => (await call(matthew, "GET", "chats", input)).json.chats.map(item => item.title);
  expect(await titles()).toEqual(["Stiffener", "Stiffener", "Battery choice"]);
  const all = (await call(matthew, "GET", "chats")).json;
  expect(all.chats.map(item => item.messages)).toEqual([3, 2, 1]);
  expect(await titles({ q: "STIFFENER" })).toHaveLength(2);
  expect(await titles({ q: "stiffener steel" })).toHaveLength(1);
  expect(await titles({ q: "15 mAh" })).toEqual(["Battery choice"]);
  expect(await titles({ q: "nothing-like-this" })).toEqual([]);
  const first = (await call(matthew, "GET", "chats", { limit: 2 })).json;
  expect([first.chats.length, first.next]).toEqual([2, first.chats[1].lastAt]);
  const rest = (await call(matthew, "GET", "chats", { limit: 2, before: first.next, beforeId: first.nextId })).json;
  expect([rest.chats.length, rest.next]).toEqual([1, null]);
  expect(JSON.stringify(all)).not.toMatch(/session-|d-laptop/);
});

it("reads a chat a part at a time, and says where the next part starts", async () => {
  await call(laptop, "POST", "chats", chat(Array.from({ length: 5 }, (_, seq) => said(seq))));
  const id = chatRows()[0].id as string;
  const first = (await call(matthew, "GET", "chat", { id, limit: 2 })).json;
  expect([first.chat.title, first.chat.messages, first.messages.map(item => item.seq), first.next]).toEqual(["Stiffener", 5, [0, 1], 1]);
  expect(first.chat).not.toHaveProperty("sessionId");
  const second = (await call(matthew, "GET", "chat", { id, limit: 2, after: first.next })).json;
  expect([second.messages.map(item => item.seq), second.next]).toEqual([[2, 3], 3]);
  const last = (await call(matthew, "GET", "chat", { id, after: second.next })).json;
  expect([last.messages.map(item => item.text), last.next]).toEqual([["Message 4"], null]);
  expect((await call(matthew, "GET", "chat", { id: "c0000000-0000-4000-8000-000000000009" })).status).toBe(404);
  expect((await call(matthew, "GET", "chat", { id: "../x" })).status).toBe(400);
});

it("cuts a part of long messages by size, so one answer stays small", async () => {
  await call(laptop, "POST", "chats", chat(Array.from({ length: 5 }, (_, seq) => said(seq, "z".repeat(200_000)))));
  const id = chatRows()[0].id as string;
  const first = (await call(matthew, "GET", "chat", { id })).json;
  expect([first.messages.length, first.next]).toEqual([3, 2]);
  expect((await call(matthew, "GET", "chat", { id, after: 2 })).json.next).toBeNull();
});

it("deletes a chat with its messages and saves, and leaves the others", async () => {
  await call(laptop, "POST", "chats", chat([said(0), said(1)]));
  await call(laptop, "POST", "chat-saves", { sessionId: SESSION, title: "Plan", text: "Summary" });
  await call(laptop, "POST", "chats", chat([said(0)], { sessionId: "another-session-0001" }));
  const [gone, kept] = chatRows().map(row => row.id as string);
  expect(await call(matthew, "DELETE", "chat", { id: gone })).toEqual({ status: 200, json: { id: gone } });
  expect(chatRows().map(row => row.id)).toEqual([kept]);
  expect([rows("relay_chat_saves"), messageRows()]).toEqual([[], [[0, "you", "Message 0"]]]);
  expect((await call(matthew, "DELETE", "chat", { id: gone })).status).toBe(404);
  expect((await call(matthew, "GET", "chats", { q: "Plan" })).json.chats).toEqual([]);
});

it("refuses every device key on the list, a chat and delete, and changes nothing", async () => {
  await call(laptop, "POST", "chats", chat([said(0)]));
  const id = chatRows()[0].id as string;
  for (const who of [laptop, phone, pebbleApp]) {
    expect((await call(who, "GET", "chats")).status).toBe(403);
    expect((await call(who, "GET", "chat", { id })).status).toBe(403);
    expect((await call(who, "DELETE", "chat", { id })).status).toBe(403);
  }
  expect(chatRows()).toHaveLength(1);
  // The checker reads its own empty test space, never Ana's chats.
  expect((await call(checker, "GET", "chats", undefined, { RELAY_CHECKER_SHA256: await hashToken("checker.access") })).json)
    .toEqual({ chats: [], next: null, nextId: null });
  expect((await call(null, "GET", "chats")).status).toBe(401);
});
