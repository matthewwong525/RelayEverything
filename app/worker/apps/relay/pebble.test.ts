import { createHmac } from "node:crypto";
import { expect, it, vi } from "vitest";
import { handleApp } from "../index";
import { body as read } from "../../../tests/body";
import { ANA, ben, BEN, benPhone, bucket, call, db, env, matthew, NOW, pebbleApp, phone, queue, request, rows, SECRET, type Who } from "../../../tests/relay";

const seconds = String(NOW / 1000);
const RECORDED = NOW - 20_000;

/** The multipart body the Pebble app sends, as bytes, with its content type. */
async function multipart(fields: Record<string, string | Blob>) {
  const form = new FormData();
  for (const [name, value] of Object.entries(fields)) form.append(name, value);
  const request = new Request("https://form.example", { method: "POST", body: form });
  return { bytes: new Uint8Array(await request.arrayBuffer()), type: request.headers.get("content-type")! };
}

const recording = new Blob([new Uint8Array([0, 0, 0, 24, 102, 116, 121, 112])], { type: "audio/mp4" });
const note = (more: Record<string, string | Blob> = {}) =>
  multipart({ audio: new File([recording], "rec-1.m4a"), transcription: "Call the PCB fab about the flex stiffener", recordedAt: String(RECORDED), client: "ring", ...more });

type Sent = { bytes?: Uint8Array; type?: string; headers?: Record<string, string>; who?: Who; secret?: string };

/** A webhook call signed as Pebble signs it; `headers` replaces or, set to "", drops any header. */
async function send({ bytes, type, headers = {}, who = pebbleApp, secret = SECRET }: Sent) {
  const base: Record<string, string> = { "X-Index-Webhook-Version": "1", "X-Index-Timestamp": seconds, "X-Index-Delivery": "delivery-1",
    "X-Index-Trigger": "single-click-hold", ...(type && { "content-type": type }), ...headers };
  const test = base["X-Index-Test"] === "true" ? 1 : 0;
  const prefix = `v${base["X-Index-Webhook-Version"]}\n${base["X-Index-Timestamp"]}\n${base["X-Index-Delivery"]}\n${base["X-Index-Trigger"] ?? ""}\n${test}\n`;
  const signature = createHmac("sha256", secret).update(prefix).update(bytes ?? new Uint8Array()).digest("hex");
  const sent = Object.fromEntries(Object.entries({ "X-Index-Signature": signature, ...base }).filter(([, value]) => value !== ""));
  const response = await handleApp(request(who, "POST", "https://relay.example.com/apps/relay/api/pebble", { headers: sent, body: bytes }), env(),
    who && "kind" in who ? who : null);
  return { status: response.status, json: await read(response) };
}

/** A note's recording as Ana's page plays it, opened with her space's file key, or the status when it can't be. */
async function played(id: string) {
  const response = await handleApp(request(matthew, "GET", `https://relay.example.com/apps/relay/api/audio?id=${id}`), env(), null);
  return response.ok ? new Uint8Array(await response.arrayBuffer()) : response.status;
}

it("stores a signed ring note once, with its words and its recording, however often Pebble sends it", async () => {
  const sent = await note();
  const first = await send(sent);
  expect(first).toEqual({ status: 200, json: { ok: true, id: expect.any(String) } });
  expect(await send(sent)).toEqual({ status: 200, json: { ok: true, duplicate: true } });
  const name = `people/${ANA}/${first.json.id}`;
  expect(rows("relay_notes")).toEqual([expect.objectContaining({ id: first.json.id, device_id: "d-pebble", source: "ring", delivery_id: "delivery-1",
    text: "Call the PCB fab about the flex stiffener", audio_key: name, recorded_at: RECORDED, lat: null })]);
  expect([...bucket.objects.keys()]).toEqual([name]);
  expect(bucket.put).toHaveBeenCalledWith(name, expect.any(Uint8Array), { httpMetadata: { contentType: "application/octet-stream" } });
  // The bucket holds the recording only sealed: the bytes open only through Ana's own space.
  const raw = new Uint8Array(await recording.arrayBuffer());
  expect(Buffer.from(bucket.objects.get(name)!).includes(Buffer.from(raw))).toBe(false);
  expect(await played(String(first.json.id))).toEqual(raw);
  expect(rows("relay_notes", BEN)).toEqual([]);
});

it("keeps a transcription-only note with no recording, and a recording-only note with no words", async () => {
  expect((await send({ ...await note({ audio: "" }), headers: { "X-Index-Delivery": "words" } })).status).toBe(200);
  const recordingOnly = await multipart({ audio: new File([recording], "rec-2.m4a"), recordedAt: String(RECORDED), client: "ring" });
  expect((await send({ ...recordingOnly, headers: { "X-Index-Delivery": "sound", "X-Index-Trigger": "" } })).status).toBe(200);
  const empty = await multipart({ audio: new File([], "rec-3.m4a"), transcription: "Nothing heard", recordedAt: String(RECORDED) });
  expect((await send({ ...empty, headers: { "X-Index-Delivery": "silent" } })).status).toBe(200);
  expect(rows("relay_notes").map(row => [row.delivery_id, row.text, row.audio_key === null])).toEqual([
    ["words", "Call the PCB fab about the flex stiffener", true], ["sound", "", false], ["silent", "Nothing heard", true]]);
});

it("refuses a forged, stale or malformed request and stores nothing", async () => {
  const sent = await note();
  const cases: [Sent, number, string][] = [
    [{ ...sent, secret: "a-forged-secret" }, 401, "Invalid signature"],
    [{ ...sent, headers: { "X-Index-Signature": "" } }, 401, "Invalid signature"],
    [{ ...sent, headers: { "X-Index-Webhook-Version": "2" } }, 400, "Unsupported webhook version"],
    [{ ...sent, headers: { "X-Index-Webhook-Version": "" } }, 400, "Unsupported webhook version"],
    [{ ...sent, headers: { "X-Index-Timestamp": String(NOW / 1000 - 301) } }, 401, "Expired request"],
    [{ ...sent, headers: { "X-Index-Timestamp": String(NOW / 1000 + 301) } }, 401, "Expired request"],
    [{ ...sent, headers: { "X-Index-Timestamp": "soon" } }, 400, "Invalid timestamp"],
    [{ ...sent, headers: { "X-Index-Timestamp": "" } }, 400, "Invalid timestamp"],
    [{ ...sent, headers: { "X-Index-Delivery": "" } }, 400, "Invalid delivery"],
    [{ ...sent, headers: { "X-Index-Delivery": "a b" } }, 400, "Invalid delivery"],
    [{ ...await note({ recordedAt: "yesterday" }) }, 400, "The body has no readable recordedAt"],
    [{ ...await note({ recordedAt: "-5" }) }, 400, "The body has no readable recordedAt"],
    [{ ...sent, type: "text/plain" }, 400, "The body has no readable recordedAt"],
    [{}, 400, "The body has no readable recordedAt"],
  ];
  for (const [request, status, message] of cases) {
    const { status: answered, json } = await send(request);
    expect([answered, json.error.message], message).toEqual([status, message]);
  }
  expect(rows("relay_notes")).toEqual([]);
  expect(bucket.put).not.toHaveBeenCalled();
});

it("a timestamp within five minutes either way passes", async () => {
  expect((await send({ ...await note(), headers: { "X-Index-Timestamp": String(NOW / 1000 - 300) } })).status).toBe(200);
});

it("refuses a body over 10 MB before reading the signature", async () => {
  const large = await note({ audio: new File([new Uint8Array(10 * 1024 * 1024)], "long.m4a") });
  expect((await send(large)).json.error.message).toBe("The recording is larger than 10 MB");
});

it("checks a test event and answers success, but never stores it", async () => {
  const test = await multipart({ test: "true", transcription: "Test event", recordedAt: String(RECORDED), client: "ring" });
  expect(await send({ ...test, headers: { "X-Index-Test": "true", "X-Index-Trigger": "test-event" } })).toEqual({ status: 200, json: { ok: true, test: true } });
  expect((await send({ ...test, headers: { "X-Index-Test": "true", "X-Index-Trigger": "test-event" }, secret: "forged" })).status).toBe(401);
  expect(rows("relay_notes")).toEqual([]);
});

it("takes notes only from a device key, and answers 503 so Pebble retries when the recording can't be saved", async () => {
  const sent = await note();
  for (const who of [matthew, ben, null]) {
    const { status, json } = await send({ ...sent, who });
    expect([status, json.error.message]).toEqual([403, "Only a Relay Everything device key can send ring notes"]);
  }
  bucket.failing = true;
  expect((await send(sent)).status).toBe(503);
  expect(rows("relay_notes")).toEqual([]);
  bucket.failing = false;
  expect((await send(sent)).status).toBe(200);
});

it("checks each note with its own device's secret: a key with none, or a secret from another device, is refused", async () => {
  const sent = await note();
  // Ana's phone and Ben's phone hold no Pebble secret, so even Pebble's own signature is refused.
  for (const who of [phone, benPhone]) expect((await send({ ...sent, who })).json.error.message).toBe("Invalid signature");
  const made = (await call(matthew, "POST", "devices", { name: "Second Pebble", reaches: "phone" })).json;
  const key = { bearer: String(made.key) };
  expect((await send({ ...sent, who: key })).status).toBe(401);
  expect(await send({ ...sent, who: key, secret: String(made.pebbleSecret) })).toEqual({ status: 200, json: { ok: true, id: expect.any(String) } });
  expect(rows("relay_notes").map(row => row.device_id)).toEqual([made.id]);
  expect(rows("relay_notes", BEN)).toEqual([]);
});

it("pins a ring note to the nearest location point within 10 minutes of its recording", async () => {
  const point = db.sql.prepare("INSERT INTO relay_locations (device_id, at, lat, lon, accuracy, place, created_at) VALUES ('d-phone', ?, ?, ?, 12, ?, 0)");
  point.run(RECORDED - 3 * 60_000, 43.6487, -79.3962, "Queen St W");
  point.run(RECORDED + 5 * 60_000, 43.6532, -79.3832, "Nathan Phillips Square");
  point.run(RECORDED - 60 * 60_000, 43.7, -79.4, "Far away in time");
  await send(await note());
  expect(rows("relay_notes")[0]).toMatchObject({ lat: 43.6487, lon: -79.3962, accuracy: 12, place: "Queen St W", place_from: "history" });
});

it("wakes each active webhook for a stored ring note, never for a repeat or a test, and answers success if the queue fails", async () => {
  const webhook = db.sql.prepare(`INSERT INTO relay_webhooks (id, name, url, secret, kinds, active, sent_seq, created_at)
    VALUES (?, ?, 'https://db.example.com/relay', 'whsec_AAAA', '["notes"]', ?, 0, ?)`);
  webhook.run("hook-1", "Example database", 1, NOW);
  webhook.run("hook-2", "Paused", 0, NOW);
  const sent = await note();
  await send(sent);
  await send(sent);
  const test = await multipart({ test: "true", transcription: "Test event", recordedAt: String(RECORDED), client: "ring" });
  await send({ ...test, headers: { "X-Index-Test": "true", "X-Index-Trigger": "test-event" } });
  expect(queue.sent).toEqual([{ webhook: "hook-1", person: ANA }]);
  queue.failing = true;
  const lost = vi.spyOn(console, "error").mockImplementation(() => undefined);
  expect((await send({ ...sent, headers: { "X-Index-Delivery": "delivery-2" } })).status).toBe(200);
  expect(lost).toHaveBeenCalledWith("Relay Everything webhooks: the wake-up was lost", expect.any(Error));
  expect(rows("relay_notes")).toHaveLength(2);
  lost.mockRestore();
});
