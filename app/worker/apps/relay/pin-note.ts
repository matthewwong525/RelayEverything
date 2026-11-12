// PUT notes/pin: a phone or the page pins or unpins any note in its space, by `id` or the device's own `clientId`.
// The newer pin change wins; a pin is not a change to the note's words, so it logs nothing for the webhooks.
import { z } from "zod";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asDeviceOrPage } from "./caller.ts";
import { CLIENT_ID } from "./notes.ts";
import type { PersonSpace } from "./space.ts";
import { time } from "./store.ts";

const pinInput = z.strictObject({
  id: z.string().max(64).optional().describe("The server's id for the note, as GET notes gives it: any note in your space."),
  clientId: z.string().regex(CLIENT_ID).optional().describe("Or the device's own id for a note it sent, as POST notes sent it."),
  pinned: z.boolean().describe("True to pin the note to the top of the notes list, false to unpin it."),
  at: time.optional().describe("When the device made the change, in Unix ms; now when left out. A later time is taken as now."),
}).refine(pin => (pin.id === undefined) !== (pin.clientId === undefined), "Give the note's id or its clientId, not both.");
type Pin = z.infer<typeof pinInput>;
type Stored = { id: string; pinned_at: number | null; pin_changed_at: number | null };

const REFUSAL = "Only a phone key or the Relay Everything page can pin a note.";
const ERRORS = { not_found: "Your space has no note with this id, or this device sent no note with this clientId.",
  older: "The note's pin changed after this change was made, so the newer pin stays: GET notes gives it." };

const failed = (code: keyof typeof ERRORS, status: number) => Response.json({ error: { code, message: ERRORS[code] } }, { status });

async function pinNote({ db }: PersonSpace, deviceId: string, pin: Pin): Promise<Response> {
  const select = "SELECT id, pinned_at, pin_changed_at FROM relay_notes";
  const note = await (pin.id !== undefined ? db.prepare(`${select} WHERE id = ?`).bind(pin.id)
    : db.prepare(`${select} WHERE device_id = ? AND client_id = ?`).bind(deviceId, pin.clientId!)).first<Stored>();
  if (!note) return failed("not_found", 404);
  // A phone's clock can run ahead: a pin from the future would lock the note against every later one.
  const at = Math.min(pin.at ?? Date.now(), Date.now());
  if (note.pin_changed_at !== null && note.pin_changed_at > at) return failed("older", 409);
  // A pin that matches the note's still keeps its time, which is not older here, so an older change made elsewhere
  // can not undo it.
  if ((note.pinned_at !== null) === pin.pinned) {
    if (note.pin_changed_at !== at) await db.prepare("UPDATE relay_notes SET pin_changed_at = ? WHERE id = ?").bind(at, note.id).run();
    return Response.json({ id: note.id, pinned: pin.pinned, pinChangedAt: at, updated: false });
  }
  await db.prepare("UPDATE relay_notes SET pinned_at = ?, pin_changed_at = ? WHERE id = ?").bind(pin.pinned ? at : null, at, note.id).run();
  return Response.json({ id: note.id, pinned: pin.pinned, pinChangedAt: at, updated: true });
}

export const notePin = defineAction({
  operationId: "relay.notes-pin", summary: "Pin or unpin a note",
  description: "Pin any note in your space to the top of the notes list on every phone and the page, or unpin it. "
    + "The page pins notes as your space's Web device. The newer change wins: a change made before the note's last pin change gets 409. "
    + "Webhooks get no message: a pin does not change the note.",
  input: pinInput, output: z.strictObject({ id: z.string(), pinned: z.boolean().describe("Whether the note is pinned now."),
    pinChangedAt: time.describe("When the note's pin last changed, by the server's clock, in Unix ms: keep it to compare with GET notes."),
    updated: z.boolean().describe("False when the note was already pinned or unpinned as asked.") }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: ERRORS, examples: [],
  handler: asDeviceOrPage<ActionCall>(REFUSAL, async ({ space, deviceId, call }) => pinNote(space, deviceId, call.input as Pin)),
});
