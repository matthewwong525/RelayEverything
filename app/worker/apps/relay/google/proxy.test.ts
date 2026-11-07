import { readFileSync } from "node:fs";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ANA, BEN, spaces } from "../../../../tests/relay";
import { GOOGLE } from "../sign-in/oidc";
import { spaceOf, vouch, type SpaceEnv } from "../space";
import { GoogleRefusal, NOT_CONNECTED, pass, target, type GoogleAsk } from "./proxy";
import { keep } from "./token";

const ENV = { RELAY_GOOGLE_CLIENT_ID: "client.apps.googleusercontent.com", RELAY_GOOGLE_SIGN_IN_SECRET: "client-secret" };
const UPLOAD = "https://www.googleapis.com/upload/drive/v3/";
const space = (person = ANA) => spaceOf({ SPACES: spaces.SPACES } as SpaceEnv, vouch("session", person));

let google: (request: Request) => Response;
const asked: Request[] = [];
const logged: string[] = [];
beforeEach(async () => {
  asked.length = 0;
  logged.length = 0;
  google = () => Response.json({ messages: [] });
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    if (url === GOOGLE.token) return Response.json({ access_token: "ya29.ana", expires_in: 3600 });
    const request = new Request(url, init);
    asked.push(request.clone());
    return google(request);
  }));
  vi.spyOn(console, "log").mockImplementation((line: string) => { logged.push(line); });
  await keep(space(), { email: "ana@gmail.example", scopes: [], refreshToken: "1//refresh-ana" });
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

const refusal = (ask: Pick<GoogleAsk, "service" | "path" | "method">) => {
  try {
    return target(ask);
  } catch (error) {
    return error instanceof GoogleRefusal ? error.status : error;
  }
};

it("maps each service to its Google address, and a Drive upload to the upload address", () => {
  expect(target({ service: "gmail", path: "messages/abc", method: "GET" })).toBe("https://gmail.googleapis.com/gmail/v1/users/me/messages/abc");
  expect(target({ service: "calendar", path: "calendars/primary/events", method: "POST" }))
    .toBe("https://www.googleapis.com/calendar/v3/calendars/primary/events");
  expect(target({ service: "drive", path: "files/f1", method: "PATCH" })).toBe("https://www.googleapis.com/drive/v3/files/f1");
  expect(target({ service: "drive", path: "upload/files", method: "POST" })).toBe(`${UPLOAD}files`);
  expect(target({ service: "contacts", path: "people:searchContacts", method: "GET" })).toBe("https://people.googleapis.com/v1/people:searchContacts");
  expect(target({ service: "calendar", path: "calendars/primary/events/e1", method: "DELETE" }))
    .toBe("https://www.googleapis.com/calendar/v3/calendars/primary/events/e1");
});

it("never deletes an email, a thread, a draft or a Drive file for ever, nor empties the bin", () => {
  for (const ask of [{ service: "gmail", path: "messages/abc", method: "DELETE" }, { service: "gmail", path: "threads/abc", method: "DELETE" },
    { service: "gmail", path: "drafts/d1", method: "DELETE" },
    { service: "gmail", path: "messages/batchDelete", method: "POST" }, { service: "drive", path: "files/f1", method: "DELETE" },
    { service: "drive", path: "files/trash", method: "DELETE" }] as const) {
    expect(refusal(ask), `${ask.method} ${ask.path}`).toBe(403);
  }
  expect(refusal({ service: "gmail", path: "messages/abc/trash", method: "POST" })).toMatch(/^https:/);
  expect(refusal({ service: "gmail", path: "drafts/d1", method: "PUT" })).toMatch(/^https:/);
});

it("refuses another person's mail, an odd path, an odd method, and a change to contacts", () => {
  expect(refusal({ service: "gmail", path: "users/sam@example.com/messages", method: "GET" })).toBe(403);
  for (const path of ["../users/sam/messages", "messages/%2e%2e/x", "messages//x", "messages/a%2Fb", "messages/a\\b", "", "messages/.."]) {
    expect(refusal({ service: "gmail", path, method: "GET" }), path).toBe(400);
  }
  expect(refusal({ service: "drive", path: "upload/../files", method: "POST" })).toBe(400);
  expect(refusal({ service: "gmail", path: "messages", method: "HEAD" })).toBe(405);
  expect(refusal({ service: "contacts", path: "people:createContact", method: "POST" })).toBe(405);
});

it("sends the person's own sign-in and only the headers Google needs, and streams Google's answer back", async () => {
  google = () => new Response(new ReadableStream({ start(stream) {
    stream.enqueue(new TextEncoder().encode('{"id":'));
    stream.enqueue(new TextEncoder().encode('"m1"}'));
    stream.close();
  } }), { status: 200, headers: { "content-type": "application/json", etag: "e1", "set-cookie": "google=1", "x-goog-meta": "x" } });
  const response = await pass(ENV, space(), { service: "gmail", path: "messages/send", method: "POST", search: "?alt=json",
    headers: new Headers({ "content-type": "application/json", Authorization: "Bearer rek_x", Cookie: "s=1" }), body: '{"raw":"eA"}' });
  expect(asked[0].url).toBe("https://gmail.googleapis.com/gmail/v1/users/me/messages/send?alt=json");
  expect(Object.fromEntries(asked[0].headers)).toEqual({ authorization: "Bearer ya29.ana", "content-type": "application/json" });
  expect(await asked[0].text()).toBe('{"raw":"eA"}');
  expect(response.body).toBeInstanceOf(ReadableStream);
  expect(await response.json()).toEqual({ id: "m1" });
  expect(Object.fromEntries(response.headers)).toEqual({ "cache-control": "no-store", "content-type": "application/json", etag: "e1" });
});

it("passes Google's refusal on as it is, and points a resumable upload's next address back to the caller", async () => {
  google = () => Response.json({ error: { message: "Not Found" } }, { status: 404 });
  const missing = await pass(ENV, space(), { service: "drive", path: "files/nope", method: "GET" });
  expect([missing.status, await missing.json()]).toEqual([404, { error: { message: "Not Found" } }]);
  google = () => new Response(null, { status: 200, headers: { location: `${UPLOAD}files?uploadType=resumable&upload_id=u1` } });
  const started = await pass(ENV, space(), { service: "drive", path: "upload/files", method: "POST", search: "?uploadType=resumable",
    base: "https://relay-mcp.example.com/v1/google/" });
  expect(started.headers.get("Location")).toBe("https://relay-mcp.example.com/v1/google/drive/upload/files?uploadType=resumable&upload_id=u1");
});

it("logs the service, method, status and time, and never a body, a query or a token", async () => {
  await pass(ENV, space(), { service: "gmail", path: "messages/m1", method: "GET", search: "?q=secret-words" });
  expect(logged.map(line => JSON.parse(line))).toEqual([{ google: "gmail", part: "messages", method: "GET", status: 200, ms: expect.any(Number) }]);
  expect(logged.join()).not.toMatch(/secret-words|ya29|refresh|m1/);
  const source = readFileSync(new URL("./proxy.ts", import.meta.url), "utf8");
  expect(source.match(/console\.\w+\(.*$/gm)).toEqual([expect.stringMatching(/^console\.log\(JSON\.stringify\(\{ google: ask\.service, part: /)]);
});

it("refuses a person with no Google connected, and a server with no Google client, before asking Google", async () => {
  await expect(pass(ENV, space(BEN), { service: "gmail", path: "messages", method: "GET" })).rejects.toThrow(NOT_CONNECTED);
  await expect(pass({}, space(), { service: "gmail", path: "messages", method: "GET" })).rejects.toMatchObject({ status: 503 });
  expect(asked).toEqual([]);
});

it("refuses with 503, asking Google nothing, when Google's sign-in can't be renewed", async () => {
  vi.stubGlobal("fetch", vi.fn(async (url: string) => {
    if (url === GOOGLE.token) return Response.json({ error: "backend_error" }, { status: 503 });
    asked.push(new Request(url));
    return Response.json({});
  }));
  await keep(space(), { email: "ana@gmail.example", scopes: [], refreshToken: "1//refresh-ana-2" });
  const refused = pass(ENV, space(), { service: "gmail", path: "messages", method: "GET" });
  await expect(refused).rejects.toBeInstanceOf(GoogleRefusal);
  await expect(refused).rejects.toMatchObject({ status: 503, message: "Google's sign-in answered 503. Try again." });
  expect(asked).toEqual([]);
});
