// The one part of node:crypto the worker uses, from nodejs_compat: a streamed HMAC, so a large body is never copied.
declare module "node:crypto" {
  type Hmac = { update(data: string | Uint8Array): Hmac; digest(): Uint8Array };
  export function createHmac(algorithm: "sha256", key: Uint8Array): Hmac;
}
