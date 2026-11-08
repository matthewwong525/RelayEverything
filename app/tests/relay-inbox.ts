// What the inbox tests share: a server that takes mail for in.example.com, and a mail from a saved .eml file.
import { readFileSync } from "node:fs";
import { vi } from "vitest";
import { env } from "./relay";

export const DOMAIN = "in.example.com";
export const inboxEnv = (more: object = {}) => env({ RELAY_INBOX_HMAC_KEY: "test-inbox-key", RELAY_INBOX_MAIL_DOMAIN: DOMAIN, ...more });

export const fixture = (name: string) => readFileSync(new URL(`../worker/apps/relay/inbox/fixtures/${name}`, import.meta.url));

/** A mail as Email Routing hands it over: its envelope's recipient and its raw bytes. */
export const mailTo = (to: string, raw: Uint8Array | string) =>
  ({ to, raw: new Response(raw).body!, setReject: vi.fn((_reason: string) => undefined) });
