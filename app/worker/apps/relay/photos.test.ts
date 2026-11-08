import { expect, it } from "vitest";
import { ANA, BEN, ben, benPhone, bucket, call, env, ipad, jpeg, laptop, matthew, NOW, owner, phone, request, rows, sendPhoto } from "../../../tests/relay";
import { handleApp } from "../index";
import { jpegSize } from "./photos";
import { spaceOf, vouch } from "./space";

const photo = (bytes: Uint8Array<ArrayBuffer>, type = "image/jpeg") => new File([bytes], "photo.jpg", { type });
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13]);

it("stores a photo once per phone and clientId, sealed under the person's photos folder", async () => {
  expect(await sendPhoto(phone)).toEqual({ status: 200, json: { ok: true, added: 1 } });
  // A resend after a lost answer adds nothing.
  expect(await sendPhoto(phone)).toEqual({ status: 200, json: { ok: true, added: 0 } });
  const [row] = rows("relay_photos");
  expect(rows("relay_photos")).toHaveLength(1);
  expect(row).toMatchObject({ device_id: "d-phone", client_id: "photo-0001", taken_at: NOW - 60_000, lat: 38.7139, lon: -9.1394,
    width: 1600, height: 1200, bytes: jpeg(1600, 1200).byteLength, file_key: `people/${ANA}/photos/${row.id}` });
  expect([...bucket.objects.keys()]).toEqual([row.file_key]);
  // The store holds it only sealed; it opens through Ana's space as the bytes sent.
  expect(bucket.objects.get(String(row.file_key))).not.toEqual(jpeg(1600, 1200));
  expect(await spaceOf(env() as never, vouch("session", ANA)).files.open(String(row.file_key))).toEqual(jpeg(1600, 1200));
  // Another of Ana's devices with the same clientId is another photo; Ben's goes to his own space.
  expect((await sendPhoto(ipad)).json).toEqual({ ok: true, added: 1 });
  expect((await sendPhoto(benPhone)).json).toEqual({ ok: true, added: 1 });
  expect(rows("relay_photos")).toHaveLength(2);
  expect(rows("relay_photos", BEN)).toHaveLength(1);
});

it("keeps a photo with no place, and refuses one place without the other", async () => {
  expect((await sendPhoto(phone, { lat: null, lon: null })).status).toBe(200);
  expect(rows("relay_photos")[0]).toMatchObject({ lat: null, lon: null });
  expect((await sendPhoto(phone, { clientId: "photo-0002", lon: null })).json.error.message).toBe("Send lat and lon together.");
});

it("refuses a PNG, a JPEG over 1,600 pixels, a file over 3 MB and fields it can't read, and stores nothing", async () => {
  const cases: [Record<string, string | Blob | null>, number, string][] = [
    [{ photo: photo(PNG) }, 400, "The photo is not a JPEG."],
    [{ photo: photo(PNG, "image/png") }, 400, "Send the photo as an image/jpeg file named photo."],
    [{ photo: photo(jpeg(2000, 1500)) }, 400, "The photo is larger than 1600 pixels on its long side."],
    [{ photo: photo(jpeg(900, 1601)) }, 400, "The photo is larger than 1600 pixels on its long side."],
    [{ photo: photo(new Uint8Array(3 * 1024 * 1024 + 1)) }, 413, "The photo is larger than 3 MB."],
    [{ photo: photo(new Uint8Array(4 * 1024 * 1024)) }, 413, "The photo is larger than 3 MB."],
    [{ photo: null }, 400, "Send the photo as an image/jpeg file named photo."],
    [{ photo: "not a file" }, 400, "Send the photo as an image/jpeg file named photo."],
    [{ clientId: "a b" }, 400, "Give the photo's clientId: 8 to 64 letters, digits or dashes."],
    [{ takenAt: String(NOW / 1000) }, 400, "Give takenAt as Unix milliseconds."],
    [{ takenAt: null }, 400, "Give takenAt as Unix milliseconds."],
    [{ lat: "91" }, 400, "lat or lon is out of range."],
  ];
  for (const [fields, status, message] of cases) {
    const { status: answered, json } = await sendPhoto(phone, fields);
    expect([answered, json.error.message], message).toEqual([status, message]);
  }
  expect(rows("relay_photos")).toEqual([]);
  expect(bucket.put).not.toHaveBeenCalled();
});

it("takes photos only from a phone key, and answers 503 when the photo can't be saved", async () => {
  for (const who of [matthew, ben, owner, null]) expect((await sendPhoto(who)).status).toBe(403);
  bucket.failing = true;
  expect((await sendPhoto(phone)).status).toBe(503);
  expect(rows("relay_photos")).toEqual([]);
  bucket.failing = false;
  expect((await sendPhoto(phone)).json).toEqual({ ok: true, added: 1 });
});

it("counts and deletes only for the signed-in person: a phone key gets neither", async () => {
  await sendPhoto(phone);
  for (const [method, route, input] of [["GET", "photos", undefined], ["POST", "photos/delete", { confirm: "delete" }]] as const) {
    expect((await call(phone, method, route, input)).status).toBe(403);
    expect((await call(laptop, method, route, input)).status).toBe(403);
    expect((await call(null, method, route, input)).status).toBe(401);
  }
  expect(rows("relay_photos")).toHaveLength(1);
});

it("counts and deletes Ana's photos only, keeps her recording, and Ben's photos stay", async () => {
  for (const clientId of ["photo-0001", "photo-0002", "photo-0003"]) await sendPhoto(phone, { clientId });
  await sendPhoto(benPhone);
  const recording = `people/${ANA}/aaaaaaaa-0000-4000-8000-0000000000a1`;
  bucket.objects.set(recording, new Uint8Array([1]));
  expect(await call(matthew, "GET", "photos")).toEqual({ status: 200, json: { count: 3 } });
  expect(await call(ben, "GET", "photos")).toEqual({ status: 200, json: { count: 1 } });
  expect((await call(matthew, "POST", "photos/delete", { confirm: "yes" })).status).toBe(400);
  expect(await call(matthew, "POST", "photos/delete", { confirm: "delete" })).toEqual({ status: 200, json: { deleted: 3 } });
  expect(await call(owner, "GET", "photos")).toEqual({ status: 200, json: { count: 0 } });
  expect(rows("relay_photos")).toEqual([]);
  expect([...bucket.objects.keys()].filter(key => key.startsWith(`people/${ANA}/`))).toEqual([recording]);
  expect(await call(ben, "GET", "photos")).toEqual({ status: 200, json: { count: 1 } });
  expect([...bucket.objects.keys()].filter(key => key.startsWith(`people/${BEN}/photos/`))).toHaveLength(1);
  expect(await call(matthew, "POST", "photos/delete", { confirm: "delete" })).toEqual({ status: 200, json: { deleted: 0 } });
});

it("refuses a body that is no form, or no body at all", async () => {
  const sent = async (init: RequestInit) => (await handleApp(request(phone, "POST", "https://relay.example.com/apps/relay/api/photos", init),
    env(), null)).json() as Promise<{ error: { message: string } }>;
  for (const init of [{}, { body: "{}", headers: { "content-type": "application/json" } }]) {
    expect((await sent(init)).error.message).toBe("Send the photo as multipart/form-data.");
  }
  expect(rows("relay_photos")).toEqual([]);
});

it("reads a JPEG's size past its other blocks, and nothing from bytes that are no JPEG", () => {
  expect(jpegSize(jpeg(1600, 900))).toEqual({ width: 1600, height: 900 });
  const frame = jpeg(1600, 900).slice(20);
  const start = [0xff, 0xd8];

  expect(jpegSize(new Uint8Array([...start, 0xff, 0xff, 0xff, 0xd0, 0xff, 0xc4, 0x00, 0x03, 0x00, ...frame]))).toEqual({ width: 1600, height: 900 });
  // The image data or a broken block before any frame, a byte that is no marker, and a frame with no width.
  expect(jpegSize(new Uint8Array([...start, 0xff, 0xda, 0x00, 0x02, ...frame]))).toBeNull();
  expect(jpegSize(new Uint8Array([...start, 0xff, 0xe1, 0x00, 0x01, ...frame]))).toBeNull();
  expect(jpegSize(new Uint8Array([...start, 0x00, 0x00, 0x00, 0x00, ...frame]))).toBeNull();
  expect(jpegSize(jpeg(0, 900))).toBeNull();
  expect(jpegSize(PNG)).toBeNull();
  expect(jpegSize(new Uint8Array([0xff, 0xd8, 0xff, 0xd9]))).toBeNull();
  expect(jpegSize(jpeg(1600, 900).slice(0, 26))).toBeNull();
  expect(jpegSize(new Uint8Array())).toBeNull();
});
