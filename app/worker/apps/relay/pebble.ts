// POST pebble: a ring note from the Pebble app's Index webhook, sent with its device key. Checked in Pebble's order
// (version, timestamp, signature by the device's own secret), then stored once per X-Index-Delivery.
import { boundedBytes } from "../../api/body.ts";
import type { ActionCall } from "../../api/contract.ts";
import { asDevice } from "./caller.ts";
import { placeRingNotes } from "./place.ts";
import { signedBy } from "./signature.ts";
import type { PersonSpace } from "./space.ts";
import { refused, type Env } from "./store.ts";
import { wake } from "./webhooks/send.ts";

const MAX_BODY = 10 * 1024 * 1024;
const WINDOW_SECONDS = 300;
const DELIVERY = /^[A-Za-z0-9._:-]{1,200}$/;

const ok = (more: Record<string, unknown>) => Response.json({ ok: true, ...more });

/** The request's checked headers, or the refusal Pebble's guide gives for the first one that fails. */
function headersOf(headers: Headers) {
  const version = headers.get("X-Index-Webhook-Version");
  if (version !== "1") return refused(400, "Unsupported webhook version");
  const timestamp = headers.get("X-Index-Timestamp") ?? "";
  if (!/^\d{1,12}$/.test(timestamp)) return refused(400, "Invalid timestamp");
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > WINDOW_SECONDS) return refused(401, "Expired request");
  const delivery = headers.get("X-Index-Delivery") ?? "";
  if (!DELIVERY.test(delivery)) return refused(400, "Invalid delivery");
  return { version, timestamp, delivery, trigger: headers.get("X-Index-Trigger") ?? "", test: headers.get("X-Index-Test") === "true" };
}

/** The multipart fields Relay keeps, or null when the body or its recording time can't be read. */
async function fieldsOf(body: Uint8Array, type: string) {
  try {
    const form = await new Response(body, { headers: { "content-type": type } }).formData();
    const recordedAt = Number(form.get("recordedAt"));
    if (!Number.isSafeInteger(recordedAt) || recordedAt <= 0) return null;
    const audio = form.get("audio");
    const transcription = form.get("transcription");
    return { recordedAt, audio: typeof audio === "string" || !audio?.size ? null : audio,
      text: typeof transcription === "string" ? transcription.slice(0, 20_000) : "" };
  } catch {
    return null;
  }
}

/** Pebble retries a 408, 429 or 5xx for 10 minutes. */
export const pebble = asDevice<Pick<ActionCall, "identity">>("Only a Relay Everything device key can send ring notes", async ({ space, device, env, request }) => {
  const signed = headersOf(request.headers);
  if (signed instanceof Response) return signed;
  let body: Uint8Array;
  try {
    body = await boundedBytes(request.body ?? new Blob().stream(), MAX_BODY, () => new Error("too large"));
  } catch {
    return refused(413, "The recording is larger than 10 MB");
  }
  const secret = await space.db.prepare("SELECT pebble_secret FROM relay_device_secrets WHERE device_id = ?").bind(device.id)
    .first<{ pebble_secret: string }>();
  if (!secret || !await signedBy(secret.pebble_secret, signed, body, request.headers.get("X-Index-Signature") ?? "")) {
    return refused(401, "Invalid signature");
  }
  // A test event is checked like a note and then dropped, so it never shows in the timeline.
  if (signed.test) return ok({ test: true });
  const fields = await fieldsOf(body, request.headers.get("content-type") ?? "");
  if (!fields) return refused(400, "The body has no readable recordedAt");
  return store(env, space, device.id, signed.delivery, fields);
});

async function store(env: Env, space: PersonSpace, device: string, delivery: string,
  { recordedAt, audio, text }: NonNullable<Awaited<ReturnType<typeof fieldsOf>>>) {
  const { db } = space;
  const id = crypto.randomUUID();
  const key = audio && space.files.nameOf(id);
  const { results } = await db.prepare(`INSERT INTO relay_notes (id, device_id, source, delivery_id, text, audio_key, recorded_at, created_at)
    VALUES (?, ?, 'ring', ?, ?, ?, ?, ?) ON CONFLICT (delivery_id) DO NOTHING RETURNING id`)
    .bind(id, device, delivery, text, key, recordedAt, Date.now()).all();
  // Pebble sends a delivery again when it missed the answer: it gets success, and nothing is stored twice.
  if (!results.length) return ok({ duplicate: true });
  if (audio) {
    try {
      await space.files.put(space.files.nameOf(id), await audio.arrayBuffer());
    } catch {
      await db.prepare("DELETE FROM relay_notes WHERE id = ?").bind(id).run();
      return refused(503, "The recording could not be saved. Pebble sends it again.");
    }
  }
  await placeRingNotes(db, recordedAt, recordedAt);
  await wake(env, space, ["notes"]);
  return ok({ id });
}
