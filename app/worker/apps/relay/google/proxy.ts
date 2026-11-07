// The one door to Google: a caller's request goes to the matching Gmail, Calendar, Drive or People API path with the
// person's own sign-in, and Google's answer streams back. Nothing is kept, and the log names no body or query.
import type { PersonSpace } from "../space.ts";
import { accessToken, clientOf, GoogleRefusal, type GoogleEnv } from "./token.ts";

export { GoogleRefusal };

export type Service = "gmail" | "calendar" | "drive" | "contacts";
export const METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE"];

const UPLOAD = "https://www.googleapis.com/upload/drive/v3/";
const BASES: Record<Service, string> = {
  gmail: "https://gmail.googleapis.com/gmail/v1/users/me/", calendar: "https://www.googleapis.com/calendar/v3/",
  drive: "https://www.googleapis.com/drive/v3/", contacts: "https://people.googleapis.com/v1/",
};
/** Deletes for ever, which no caller may send: an email, a thread or a draft, and a Drive file or the whole bin. The
 *  bin keeps a mistake for 30 days; a deleted draft skips it. */
const FOREVER: { service: Service; method: string; path: RegExp }[] = [
  { service: "gmail", method: "DELETE", path: /^(?:messages|threads|drafts)\/[^/]+$/ },
  { service: "gmail", method: "POST", path: /^messages\/batchDelete$/ },
  { service: "drive", method: "DELETE", path: /^files\/[^/]+$/ },
];
// What a resumable Drive upload needs on its way in and out, beside the body's type.
const SENT = ["content-type", "content-range", "x-upload-content-type", "x-upload-content-length", "if-match"];
const KEPT = ["content-type", "etag", "range"];

export const NOT_CONNECTED = "Connect Google on your Relay Everything page first.";

/** One request for Google. `path` is the part after the service, as sent; `base` is the caller's own address for
 *  `/v1/google/`, so an upload's next address points back here. */
export type GoogleAsk = { service: Service; path: string; method: string; search?: string; headers?: Headers; body?: BodyInit | null; base?: string };

const badSegment = (segment: string) => !segment || /^(?:\.|%2e){1,2}$/i.test(segment);

/** The Google address for a request, or a refusal: an odd path, a method a service doesn't take, another person's
 *  mail, or a delete for ever. */
export function target({ service, path, method }: Pick<GoogleAsk, "service" | "path" | "method">): string {
  if (!METHODS.includes(method)) throw new GoogleRefusal(`Google paths take ${METHODS.join(", ")}.`, 405);
  if (service === "contacts" && method !== "GET") throw new GoogleRefusal("Contacts only read: send GET.", 405);
  const upload = service === "drive" && path.startsWith("upload/");
  const rest = upload ? path.slice("upload/".length) : path;
  if (rest.split("/").some(badSegment) || /%2f|%5c|\\/i.test(rest)) throw new GoogleRefusal("This is not a path Relay Everything passes to Google.", 400);
  if (service === "gmail" && rest.startsWith("users/")) throw new GoogleRefusal("Gmail paths start after users/me/: you reach only your own mail.", 403);
  if (FOREVER.some(rule => rule.service === service && rule.method === method && rule.path.test(rest))) {
    throw new GoogleRefusal("Relay Everything never deletes an email, a draft or a file for ever. Put it in the bin instead.", 403);
  }
  return `${upload ? UPLOAD : BASES[service]}${rest}`;
}

const copied = (from: Headers | undefined, names: string[], to: Headers) => {
  for (const name of names) {
    const value = from?.get(name);
    if (value) to.set(name, value);
  }
  return to;
};

/** Sends one request to Google as the space's person, and answers Google's status, type and body as it streams. */
export async function pass(env: GoogleEnv, space: PersonSpace, ask: GoogleAsk): Promise<Response> {
  const url = `${target(ask)}${ask.search ?? ""}`;
  if (!clientOf(env)) throw new GoogleRefusal("This server does not connect Google.", 503);
  const token = await accessToken(env, space);
  if (!token) throw new GoogleRefusal(NOT_CONNECTED, 403);
  const headers = copied(ask.headers, SENT, new Headers({ Authorization: `Bearer ${token}` }));
  const started = Date.now();
  const body = ask.method === "GET" ? null : ask.body ?? null;
  const answer = await fetch(url, { method: ask.method, headers, body, ...(body instanceof ReadableStream && { duplex: "half" }) } as RequestInit);
  console.log(JSON.stringify({ google: ask.service, part: ask.path.split("/")[0], method: ask.method, status: answer.status, ms: Date.now() - started }));
  const out = copied(answer.headers, KEPT, new Headers({ "Cache-Control": "no-store" }));
  const next = answer.headers.get("location");
  if (next?.startsWith(UPLOAD) && ask.base) out.set("Location", `${ask.base}drive/upload/${next.slice(UPLOAD.length)}`);
  return new Response(answer.body, { status: answer.status, headers: out });
}
