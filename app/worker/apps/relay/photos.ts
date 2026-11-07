// POST photos from a phone's key, once per device and clientId, sealed like a recording; GET photos and POST
// photos/delete for the page only. The phone sends the final small JPEG: the server reads only its size.
import { z } from "zod";
import { boundedBytes } from "../../api/body.ts";
import { defineAction, type ActionCall } from "../../api/contract.ts";
import { asDevice, asPerson } from "./caller.ts";
import { refused } from "./store.ts";

const MAX_PHOTO = 3 * 1024 * 1024;
/** The multipart body around the photo: its fields and boundaries. */
const MAX_BODY = MAX_PHOTO + 64 * 1024;
const LONG_SIDE = 1600;
const CLIENT_ID = /^[A-Za-z0-9-]{8,64}$/;
const PAGE = 500;

/** A JPEG's width and height from its first start-of-frame marker, or null when the bytes are no JPEG. */
export function jpegSize(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  for (let at = 2; at + 4 <= bytes.length;) {
    if (bytes[at] !== 0xff) return null;
    const marker = bytes[at + 1];
    // A fill byte, or a marker with no length: the next marker follows at once.
    if (marker === 0xff) { at += 1; continue; }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) { at += 2; continue; }
    if (marker === 0xd9 || marker === 0xda) return null;
    const length = (bytes[at + 2] << 8) | bytes[at + 3];
    if (length < 2) return null;
    // SOF0 to SOF15, except DHT (C4), JPG (C8) and DAC (CC), which share the range.
    if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
      if (at + 9 > bytes.length) return null;
      const height = (bytes[at + 5] << 8) | bytes[at + 6];
      const width = (bytes[at + 7] << 8) | bytes[at + 8];
      return width && height ? { width, height } : null;
    }
    at += 2 + length;
  }
  return null;
}

type Fields = { clientId: string; takenAt: number; lat: number | null; lon: number | null; photo: Uint8Array };

const number = (value: File | string | null) => typeof value === "string" && value.trim() !== "" ? Number(value) : null;

/** The photo's checked fields, or the refusal for the first one that fails. */
async function fieldsOf(body: Uint8Array, type: string): Promise<Fields | Response> {
  let form: FormData;
  try {
    form = await new Response(body, { headers: { "content-type": type } }).formData();
  } catch {
    return refused(400, "Send the photo as multipart/form-data.");
  }
  const clientId = form.get("clientId");
  if (typeof clientId !== "string" || !CLIENT_ID.test(clientId)) return refused(400, "Give the photo's clientId: 8 to 64 letters, digits or dashes.");
  const takenAt = number(form.get("takenAt"));
  if (takenAt === null || !Number.isSafeInteger(takenAt) || takenAt < 1e12 || takenAt > 1e13) {
    return refused(400, "Give takenAt as Unix milliseconds.");
  }
  const [lat, lon] = [number(form.get("lat")), number(form.get("lon"))];
  if ((lat === null) !== (lon === null)) return refused(400, "Send lat and lon together.");
  if (lat !== null && !(Math.abs(lat) <= 90 && Math.abs(lon!) <= 180)) return refused(400, "lat or lon is out of range.");
  const photo = form.get("photo");
  if (!photo || typeof photo === "string" || photo.type !== "image/jpeg") return refused(400, "Send the photo as an image/jpeg file named photo.");
  if (photo.size > MAX_PHOTO) return refused(413, "The photo is larger than 3 MB.");
  return { clientId, takenAt, lat, lon, photo: new Uint8Array(await photo.arrayBuffer()) };
}

/** Stores a photo once per device and clientId: a resend after a lost answer adds nothing. */
export const photoAdd = asDevice<Pick<ActionCall, "identity">>("Only a Relay Everything device key can send photos", async ({ space, device, request }) => {
  let body: Uint8Array;
  try {
    body = await boundedBytes(request.body ?? new Blob().stream(), MAX_BODY, () => new Error("too large"));
  } catch {
    return refused(413, "The photo is larger than 3 MB.");
  }
  const fields = await fieldsOf(body, request.headers.get("content-type") ?? "");
  if (fields instanceof Response) return fields;
  const size = jpegSize(fields.photo);
  if (!size) return refused(400, "The photo is not a JPEG.");
  if (Math.max(size.width, size.height) > LONG_SIDE) return refused(400, `The photo is larger than ${LONG_SIDE} pixels on its long side.`);
  const { db, files } = space;
  const id = crypto.randomUUID();
  const item = `photos/${id}`;
  const name = files.nameOf(item);
  const { results } = await db.prepare(`INSERT INTO relay_photos (id, device_id, client_id, taken_at, lat, lon, width, height, bytes, file_key,
      created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (device_id, client_id) DO NOTHING RETURNING id`)
    .bind(id, device.id, fields.clientId, fields.takenAt, fields.lat, fields.lon, size.width, size.height, fields.photo.byteLength, name, Date.now())
    .all();
  if (!results.length) return Response.json({ ok: true, added: 0 });
  try {
    await files.put(item, fields.photo.slice().buffer);
  } catch {
    await db.prepare("DELETE FROM relay_photos WHERE id = ?").bind(id).run();
    return refused(503, "The photo could not be saved. The phone sends it again.");
  }
  return Response.json({ ok: true, added: 1 });
});

export const photoCount = defineAction({
  operationId: "relay.photos", summary: "Count the photos", description: "Answer how many photos your phones sent. No photo shows.",
  input: z.strictObject({}), output: z.strictObject({ count: z.number().int().describe("How many photos your space holds.") }),
  encoding: "none", effect: "read", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [],
  handler: asPerson<ActionCall>(async ({ space }) => {
    const row = await space.db.prepare("SELECT COUNT(*) AS count FROM relay_photos").first<{ count: number }>();
    return Response.json({ count: row!.count });
  }),
});

export const photoDelete = defineAction({
  operationId: "relay.photos-delete", summary: "Delete all photos",
  description: "Delete every photo your phones sent, and its time and place. Notes, recordings, health and places stay. It can't be undone.",
  input: z.strictObject({ confirm: z.literal("delete").describe("Type \"delete\" to confirm.") }),
  output: z.strictObject({ deleted: z.number().int().describe("How many photos were deleted.") }),
  encoding: "json", effect: "write", agentAvailable: false, requiresIdentity: false, errors: {}, examples: [], confirmWith: "relay.photos",
  handler: asPerson<ActionCall>(async ({ space }) => {
    const { db, files } = space;
    let deleted = 0;
    // A page at a time: files first, then rows, so a step that fails leaves each row's file for the next try.
    for (;;) {
      const { results } = await db.prepare("SELECT id, file_key FROM relay_photos ORDER BY id LIMIT ?").bind(PAGE).all<{ id: string; file_key: string }>();
      if (!results.length) break;
      await files.remove(results.map(row => row.file_key));
      await db.prepare("DELETE FROM relay_photos WHERE id IN (SELECT value FROM json_each(?))").bind(JSON.stringify(results.map(row => row.id))).run();
      deleted += results.length;
    }
    return Response.json({ deleted });
  }),
});
