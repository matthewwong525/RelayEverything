// Pebble's Index webhook signing, version 1 (coredevices/mobileapp INDEX_WEBHOOK_API.md): HMAC-SHA256, keyed with the
// secret's UTF-8 bytes, over "v1\n{timestamp}\n{delivery}\n{trigger}\n{0|1}\n" then the raw body, as lowercase hex.
const encoder = new TextEncoder();

export type Signed = { version: string; timestamp: string; delivery: string; trigger: string; test: boolean };

const hexBytes = (hex: string) => Uint8Array.from(hex.match(/../g)!, pair => parseInt(pair, 16));

/** Whether `signature` signs this request. The runtime's own HMAC check compares in constant time. */
export async function signedBy(secret: string, signed: Signed, body: Uint8Array, signature: string): Promise<boolean> {
  if (!/^[0-9a-f]{64}$/.test(signature)) return false;
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  const prefix = encoder.encode(`v${signed.version}\n${signed.timestamp}\n${signed.delivery}\n${signed.trigger}\n${signed.test ? 1 : 0}\n`);
  const data = new Uint8Array(prefix.length + body.length);
  data.set(prefix);
  data.set(body, prefix.length);
  return crypto.subtle.verify("HMAC", key, hexBytes(signature), data);
}
