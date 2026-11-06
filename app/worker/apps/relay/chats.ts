// POST chats and POST chat-saves: a chat key adds a Claude Code chat a few messages at a time, and the AI's summary.
// It reads back only how many messages its chat holds, so the plugin sends on; a stored message never changes.
import { z } from "zod";
import { boundedBytes } from "../../api/body.ts";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { deviceOf } from "./device.ts";
import { refused, session, time, type Db, type Env, type Identity } from "./store.ts";

/** One send's caps: more is refused whole with 413. */
const CHAT_MESSAGES = 500;
const CHAT_BYTES = 4 * 1024 * 1024;
/** One message's cap: the plugin cuts a longer one and says how much it cut. */
const MESSAGE_CHARACTERS = 200_000;
// D1 takes a bound value of up to 2 MB, so the messages go in as several JSON values in one batch.
const CHUNK_BYTES = 1_000_000;

const sessionId = z.string().regex(/^[A-Za-z0-9_-]{8,128}$/).describe("Claude Code's id for the chat.");
const message = z.strictObject({
  seq: z.number().int().min(0).max(10_000_000), role: z.enum(["you", "ai", "step"]), text: z.string().max(MESSAGE_CHARACTERS), at: time,
});
const chatInput = z.strictObject({
  sessionId, project: z.string().trim().min(1).max(200), startedAt: time, title: z.string().max(200).optional(),
  messages: z.array(message).refine(list => list.every((item, index) => item.seq === list[0].seq + index), "Send messages in order, with no gap."),
});

/** The chat key behind a call, or null: a phone, the Pebble app, a person or the checker. */
async function chatKey(env: Env, identity: Identity) {
  const device = await deviceOf(env, identity);
  return device?.reaches === "chats" ? device : null;
}

const stored = async (db: Db, device: string, session: string) => (await db.prepare(
  "SELECT id, message_count FROM relay_chats WHERE device_id = ? AND session_id = ?").bind(device, session).first<{ id: string; message_count: number }>());

/** Messages as JSON values of under CHUNK_BYTES each. */
function chunks(messages: z.infer<typeof message>[]): string[] {
  const out: string[][] = [[]];
  const encoder = new TextEncoder();
  let size = 0;
  for (const item of messages) {
    const text = JSON.stringify(item);
    const bytes = encoder.encode(text).byteLength;
    if (size + bytes > CHUNK_BYTES && out.at(-1)!.length) { out.push([]); size = 0; }
    out.at(-1)!.push(text);
    size += bytes;
  }
  return out.filter(list => list.length).map(list => `[${list.join(",")}]`);
}

const field = (name: string) => `json_extract(value, '$.${name}')`;

/** POST chats: a bare route, so a send over the caps answers 413 and a gap answers 400 with `stored`. */
export async function chats(request: Request, env: Env, { identity }: Pick<ActionCall, "identity">): Promise<Response> {
  const device = await chatKey(env, identity);
  if (!device) return refused(403, "Only a Relay Everything chat key can send chats.");
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json") return refused(400, "Send the chat as a JSON body.");
  let body: string;
  try {
    body = new TextDecoder().decode(await boundedBytes(request.body ?? new Blob().stream(), CHAT_BYTES, () => new Error("too large")));
  } catch {
    return refused(413, `Send at most ${CHAT_BYTES} bytes at a time.`);
  }
  let parsed;
  try { parsed = chatInput.safeParse(JSON.parse(body)); } catch { return refused(400, "The body is not valid JSON."); }
  if (!parsed.success) return refused(400, parsed.error.issues[0].message);
  const chat = parsed.data;
  if (chat.messages.length > CHAT_MESSAGES) return refused(413, `Send at most ${CHAT_MESSAGES} messages at a time.`);
  const db = session(env);
  const now = Date.now();
  const lastAt = Math.max(chat.startedAt, ...chat.messages.map(item => item.at));
  // The gap check reads the chat as it is, so a refused send leaves no empty chat in the list.
  const before = await stored(db, device.id, chat.sessionId);
  const count = before?.message_count ?? 0;
  if (chat.messages.length && chat.messages[0].seq > count) {
    return Response.json({ error: { code: "invalid_input", message: "Messages are missing before these: send from `stored`." },
      stored: count }, { status: 400, headers: { "Cache-Control": "no-store" } });
  }
  const fresh = chat.messages.filter(item => item.seq >= count);
  if (fresh.length) {
    await db.prepare(`INSERT INTO relay_chats (id, device_id, session_id, app, project, title, started_at, last_at, message_count, created_at)
      VALUES (?, ?, ?, 'claude-code', ?, ?, ?, ?, 0, ?) ON CONFLICT (device_id, session_id) DO NOTHING`)
      .bind(crypto.randomUUID(), device.id, chat.sessionId, chat.project, chat.title ?? "", chat.startedAt, chat.startedAt, now).run();
    const chatId = before?.id ?? (await stored(db, device.id, chat.sessionId))!.id;
    await db.batch([
      ...chunks(fresh).map(json => db.prepare(`INSERT INTO relay_chat_messages (chat_id, seq, role, text, at)
        SELECT ?, ${["seq", "role", "text", "at"].map(field).join(", ")} FROM json_each(?) WHERE true ON CONFLICT (chat_id, seq) DO NOTHING`)
        .bind(chatId, json)),
      db.prepare(`UPDATE relay_chats SET message_count = (SELECT COUNT(*) FROM relay_chat_messages WHERE chat_id = ?1),
        last_at = MAX(last_at, ?2) WHERE id = ?1`).bind(chatId, lastAt),
    ]);
  }
  const after = await stored(db, device.id, chat.sessionId);
  return Response.json({ stored: after?.message_count ?? 0 }, { headers: { "Cache-Control": "no-store" } });
}

const ERRORS = { not_found: "This key has sent no chat with that session id. Send the chat first." };

export const chatSaves = defineAction({
  operationId: "relay.chat-saves-add", summary: "Save the AI's summary of a chat",
  description: "Store a title and a summary the AI wrote for a chat this key sent. The chat's messages stay as they are; the newest save's title shows as the chat's title.",
  input: z.strictObject({
    sessionId, title: z.string().trim().min(1).max(200).describe("The AI's title for the chat."),
    text: z.string().trim().min(1).max(20_000).describe("The AI's summary, shown as written by the AI."),
  }),
  output: z.strictObject({ ok: z.literal(true) }), encoding: "json", effect: "write", agentAvailable: false, errors: ERRORS, examples: [],
  async handler(_request, env, { identity, input }) {
    const device = await chatKey(env, identity);
    if (!device) return refused(403, "Only a Relay Everything chat key can save to a chat.");
    const save = input as { sessionId: string; title: string; text: string };
    const db = session(env);
    const chat = await stored(db, device.id, save.sessionId);
    if (!chat) return Response.json({ error: { code: "not_found", message: ERRORS.not_found } }, { status: 404 });
    await db.prepare("INSERT INTO relay_chat_saves (id, chat_id, title, text, created_at) VALUES (?, ?, ?, ?, ?)")
      .bind(crypto.randomUUID(), chat.id, save.title, save.text, Date.now()).run();
    return Response.json({ ok: true });
  },
});
