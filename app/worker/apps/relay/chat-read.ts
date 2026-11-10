// GET chats, GET chat and DELETE chat: a person's saved chats on the Relay Everything page, from their own space. No
// device key reaches them: the gate in caller.ts lets a chat key only send, and each handler refuses one too.
import { z } from "zod";
import { defineAction, type Action, type ActionCall } from "../../api/contract.ts";
import { asPerson } from "./caller.ts";
import { chatById, chatMessages, chatPage } from "./queries.ts";
import { time, type Db } from "./store.ts";

const PAGE = 30;
const PART = 200;
const id = z.string().regex(/^[0-9a-f-]{36}$/).describe("The chat's id, from the list of chats.");
const ERRORS = { not_found: "No chat has this id." };
const notFound = () => Response.json({ error: { code: "not_found", message: ERRORS.not_found } }, { status: 404 });

const chat = z.strictObject({ id: z.string(), title: z.string(), project: z.string(), app: z.enum(["claude-code", "codex"]).describe("The app the chat came from."),
  startedAt: z.number(), lastAt: z.number(), messages: z.number().describe("How many messages the chat holds."),
  savedByAi: z.boolean().describe("True when the AI saved a title and summary for it.") });
const save = z.strictObject({ id: z.string(), title: z.string(), text: z.string().describe("The summary, written by the AI."), createdAt: z.number() });
const message = z.strictObject({ seq: z.number(), role: z.enum(["you", "ai", "step"]).describe("Yours, the AI's, or one step the AI took."),
  text: z.string(), at: z.number() });

/** A person's route in their own space: any device key is refused before `run`. */
const owners = (run: (db: Db, input: never) => Promise<Response>): Action["handler"] =>
  asPerson<ActionCall>(({ space, call }) => run(space.db, call.input as never));

export const chatList = defineAction({
  operationId: "relay.chats", summary: "List the chats",
  description: "List the saved AI chats from Claude Code and Codex, newest first, or only those whose messages or AI summaries hold every word of `q`.",
  input: z.strictObject({
    q: z.string().trim().max(200).optional().describe("Words to find, in any case."),
    before: time.optional().describe("Only chats last active before this Unix time in milliseconds: the last page's `next`."),
    beforeId: z.string().max(64).optional().describe("With `before`, also the chats at that time with a lower id: the last page's `nextId`."),
    limit: z.number().int().min(1).max(100).optional().describe(`How many chats, ${PAGE} when left out.`),
  }),
  output: z.strictObject({ chats: z.array(chat), next: z.number().nullable(), nextId: z.string().nullable() }),
  encoding: "query", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: owners(async (db, { q = "", before, beforeId, limit = PAGE }: { q?: string; before?: number; beforeId?: string; limit?: number }) =>
    Response.json(await chatPage(db, { before, beforeId, words: q.split(/\s+/).filter(Boolean).slice(0, 10), limit }))),
});

export const chatRead = defineAction({
  operationId: "relay.chat", summary: "Read one chat",
  description: "Read one chat: its AI saves, newest first, and its messages in order, a part at a time.",
  input: z.strictObject({
    id, after: z.number().int().min(0).optional().describe("Only messages after this one: the last part's `next`."),
    limit: z.number().int().min(1).max(PART).optional().describe(`How many messages, ${PART} when left out.`),
  }),
  output: z.strictObject({ chat, saves: z.array(save), messages: z.array(message), next: z.number().nullable() }),
  encoding: "query", effect: "read", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  limits: { inputBytes: 4096, outputBytes: 4_194_304, timeoutMs: 15_000 },
  handler: owners(async (db, { id: chatId, after = -1, limit = PART }: { id: string; after?: number; limit?: number }) => {
    const found = await chatById(db, chatId);
    if (!found) return notFound();
    const { saves, ...rest } = found;
    return Response.json({ chat: rest, saves, ...await chatMessages(db, chatId, after, limit) });
  }),
});

export const chatDelete = defineAction({
  operationId: "relay.chat-delete", summary: "Delete a chat",
  description: "Delete one chat with its messages and AI saves. It can't be brought back.",
  input: z.strictObject({ id }), output: z.strictObject({ id: z.string() }), encoding: "query", effect: "write", agentAvailable: false,
  requiresIdentity: false, confirmWith: "relay.chat", errors: ERRORS, examples: [],
  handler: owners(async (db, { id: chatId }: { id: string }) => {
    if (!await db.prepare("SELECT id FROM relay_chats WHERE id = ?").bind(chatId).first()) return notFound();
    // D1 deletes the children by their foreign keys too; the batch deletes them by name, so no row depends on that.
    await db.batch([
      db.prepare("DELETE FROM relay_chat_messages WHERE chat_id = ?").bind(chatId),
      db.prepare("DELETE FROM relay_chat_saves WHERE chat_id = ?").bind(chatId),
      db.prepare("DELETE FROM relay_chats WHERE id = ?").bind(chatId),
    ]);
    return Response.json({ id: chatId });
  }),
});
