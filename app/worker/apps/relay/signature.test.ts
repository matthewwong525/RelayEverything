import { createHmac } from "node:crypto";
import { expect, it } from "vitest";
import { signedBy, type Signed } from "./signature";

const signed: Signed = { version: "1", timestamp: "1762300800", delivery: "0b7f6c1e-1111-4a2b-9c3d-123456789abc", trigger: "single-click-hold", test: false };
const body = new TextEncoder().encode('--b\r\nContent-Disposition: form-data; name="transcription"\r\n\r\nCall the PCB fab\r\n--b--\r\n');
const SECRET = "relay-test-signing-secret-0123456789";

// Made with the Python verifier in Pebble's INDEX_WEBHOOK_API.md: hmac.new(secret, prefix + raw_body, sha256).
const PEBBLE_EXAMPLE = "f00e2489984585c28c43a55b226f18d74db5e1fcb950e4048e8deec02b12efb9";

it("accepts the signature Pebble's documented verifier makes, over the version, time, delivery, trigger and body", async () => {
  expect(await signedBy(SECRET, signed, body, PEBBLE_EXAMPLE)).toBe(true);
  const prefix = "v1\n1762300800\n0b7f6c1e-1111-4a2b-9c3d-123456789abc\nsingle-click-hold\n0\n";
  expect(createHmac("sha256", SECRET).update(prefix).update(body).digest("hex")).toBe(PEBBLE_EXAMPLE);
});

it("refuses a signature when any signed part changes, or when it is not 64 lowercase hex digits", async () => {
  for (const change of [{ timestamp: "1762300801" }, { delivery: "another" }, { trigger: "double-click-hold" }, { test: true }, { version: "2" }]) {
    expect(await signedBy(SECRET, { ...signed, ...change }, body, PEBBLE_EXAMPLE), JSON.stringify(change)).toBe(false);
  }
  expect(await signedBy("another-secret", signed, body, PEBBLE_EXAMPLE)).toBe(false);
  expect(await signedBy(SECRET, signed, body.slice(1), PEBBLE_EXAMPLE)).toBe(false);
  for (const wrong of [PEBBLE_EXAMPLE.toUpperCase(), `sha256=${PEBBLE_EXAMPLE}`, PEBBLE_EXAMPLE.slice(2), ""]) {
    expect(await signedBy(SECRET, signed, body, wrong)).toBe(false);
  }
});
