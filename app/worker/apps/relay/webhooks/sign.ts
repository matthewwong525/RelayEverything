// Standard Webhooks signing (standardwebhooks.com), so a receiver checks each message with a ready library: an
// HMAC-SHA256 of "{id}.{timestamp}.{body}" with the webhook's secret, sent as `webhook-signature: v1,<base64>`.
import { createHmac } from "node:crypto";

const PREFIX = "whsec_";
const CHUNK = 0x8000;

/** Bytes as base64, a piece at a time, so a 10 MB recording never spreads into one call's arguments. */
export function base64(bytes: Uint8Array): string {
  let text = "";
  for (let start = 0; start < bytes.length; start += CHUNK) text += String.fromCharCode(...bytes.subarray(start, start + CHUNK));
  return btoa(text);
}

/** A new secret: `whsec_` and 32 random bytes in base64. */
export const newSecret = () => PREFIX + base64(crypto.getRandomValues(new Uint8Array(32)));

/** Fed a piece at a time, so a file's body is never copied to be signed. */
function signature(secret: string, id: string, timestamp: string, body: string | Uint8Array) {
  const key = Uint8Array.from(atob(secret.slice(PREFIX.length)), char => char.charCodeAt(0));
  const mac = createHmac("sha256", key).update(`${id}.${timestamp}.`).update(body).digest();
  return `v1,${base64(mac)}`;
}

/** The headers of one signed message. The timestamp is the send time, so a receiver can refuse an old replay. */
export async function signedHeaders(secret: string, id: string, body: string | Uint8Array, now = Date.now()): Promise<Record<string, string>> {
  const timestamp = String(Math.floor(now / 1000));
  return { "content-type": "application/json", "user-agent": "Relay-Webhooks/1", "webhook-id": id, "webhook-timestamp": timestamp,
    "webhook-signature": signature(secret, id, timestamp, body) };
}
