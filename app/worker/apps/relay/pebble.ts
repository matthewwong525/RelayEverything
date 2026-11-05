// POST pebble: a ring note from the Pebble app's Index webhook. Checked in Pebble's order (version, timestamp,
// signature), then stored once per X-Index-Delivery; Pebble retries a 408, 429 or 5xx for 10 minutes.
import { boundedBytes } from "../../api/body.ts";
import type { ActionCall } from "../../api/contract.ts";
import { deviceOf } from "./device.ts";
import { placeRingNotes } from "./place.ts";
import { signedBy } from "./signature.ts";
import { refused, session, type Env } from "./store.ts";

const MAX_BODY = 10 * 1024 * 1024;
const WINDOW_SECONDS = 300;
const DELIVERY = /^[A-Za-z0-9._:-]{1,200}$/;

type PebbleEnv = Env & { RELAY_PEBBLE_SIGNING?: string };
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

async function receive(request: Request, env: PebbleEnv, { identity }: Pick<ActionCall, "identity">): Promise<Response> {
  const signed = headersOf(request.headers);
  if (signed instanceof Response) return signed;
  let body: Uint8Array;
  try {
    body = await boundedBytes(request.body ?? new Blob().stream(), MAX_BODY, () => new Error("too large"));
  } catch {
    return refused(413, "The recording is larger than 10 MB");
  }
  if (!await signedBy(env.RELAY_PEBBLE_SIGNING!, signed, body, request.headers.get("X-Index-Signature") ?? "")) {
    return refused(401, "Invalid signature");
  }
  const device = await deviceOf(env, identity);
  if (!device) return refused(403, "Only a Relay device key can send ring notes");
  // A test event is checked like a note and then dropped, so it never shows in the timeline.
  if (signed.test) return ok({ test: true });
  const fields = await fieldsOf(body, request.headers.get("content-type") ?? "");
  if (!fields) return refused(400, "The body has no readable recordedAt");
  return store(env, device.id, signed.delivery, fields);
}

async function store(env: PebbleEnv, device: string, delivery: string, { recordedAt, audio, text }: NonNullable<Awaited<ReturnType<typeof fieldsOf>>>) {
  const db = session(env);
  const id = crypto.randomUUID();
  const key = audio && `notes/${id}.m4a`;
  const { results } = await db.prepare(`INSERT INTO relay_notes (id, device_id, source, delivery_id, text, audio_key, recorded_at, created_at)
    VALUES (?, ?, 'ring', ?, ?, ?, ?, ?) ON CONFLICT (delivery_id) DO NOTHING RETURNING id`)
    .bind(id, device, delivery, text, key, recordedAt, Date.now()).all();
  // Pebble sends a delivery again when it missed the answer: it gets success, and nothing is stored twice.
  if (!results.length) return ok({ duplicate: true });
  if (audio) {
    try {
      await env.RELAY_BUCKET.put(key!, await audio.arrayBuffer(), { httpMetadata: { contentType: "audio/mp4" } });
    } catch {
      await db.prepare("DELETE FROM relay_notes WHERE id = ?").bind(id).run();
      return refused(503, "The recording could not be saved. Pebble sends it again.");
    }
  }
  await placeRingNotes(db, recordedAt, recordedAt);
  return ok({ id });
}

/** Lists its saved key itself, so only this route needs the signing secret saved. */
export const pebble = Object.assign(receive, { keys: ["relay-pebble-signing"] as const });
