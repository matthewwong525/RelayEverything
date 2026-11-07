import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ANA, BEN, NOW, rows, spaces } from "../../../../tests/relay";
import { GOOGLE } from "../sign-in/oidc";
import { spaceOf, vouch, type SpaceEnv } from "../space";
import { accessToken, connectionOf, disconnect, GoogleRefusal, keep, REVOKE_URL } from "./token";

const ENV = { RELAY_GOOGLE_CLIENT_ID: "client.apps.googleusercontent.com", RELAY_GOOGLE_SIGN_IN_SECRET: "client-secret" };
const SCOPES = ["https://www.googleapis.com/auth/gmail.modify", "https://www.googleapis.com/auth/calendar"];
const space = (person = ANA) => spaceOf({ SPACES: spaces.SPACES } as SpaceEnv, vouch("session", person));

let grant: Record<string, unknown>;
let status: number;
const sent: { url: string; body: URLSearchParams }[] = [];
beforeEach(() => {
  grant = { access_token: "ya29.first", expires_in: 3600 };
  status = 200;
  sent.length = 0;
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    sent.push({ url, body: new URLSearchParams(String(init.body)) });
    return Response.json(grant, { status });
  }));
});
afterEach(() => vi.unstubAllGlobals());

const connect = (person = ANA, refreshToken = "1//refresh-ana") => keep(space(person), { email: `${person}@example.com`, scopes: SCOPES, refreshToken });

it("keeps the address and permissions, and the refresh token only sealed", async () => {
  await connect();
  expect(await connectionOf(space())).toEqual({ email: `${ANA}@example.com`, scopes: SCOPES, connectedAt: NOW });
  const [row] = rows("relay_google") as { token: Uint8Array }[];
  expect(new TextDecoder().decode(row.token)).not.toContain("refresh-ana");
  expect(await connectionOf(space(BEN))).toBeNull();
});

it("refreshes an access token once, keeps it until a minute before it ends, and asks again after", async () => {
  await connect();
  expect(await accessToken(ENV, space())).toBe("ya29.first");
  expect(Object.fromEntries(sent[0].body)).toEqual({ grant_type: "refresh_token", refresh_token: "1//refresh-ana", client_id: ENV.RELAY_GOOGLE_CLIENT_ID,
    client_secret: ENV.RELAY_GOOGLE_SIGN_IN_SECRET });
  expect(sent[0].url).toBe(GOOGLE.token);
  expect(await accessToken(ENV, space())).toBe("ya29.first");
  expect(sent).toHaveLength(1);
  grant = { access_token: "ya29.second", expires_in: 3600 };
  vi.setSystemTime(NOW + 59 * 60_000);
  expect(await accessToken(ENV, space())).toBe("ya29.second");
  expect(sent).toHaveLength(2);
});

it("gives each person their own token, and a new connection a new one", async () => {
  await connect();
  await connect(BEN, "1//refresh-ben");
  expect(await accessToken(ENV, space())).toBe("ya29.first");
  grant = { access_token: "ya29.ben", expires_in: 3600 };
  expect(await accessToken(ENV, space(BEN))).toBe("ya29.ben");
  expect(sent[1].body.get("refresh_token")).toBe("1//refresh-ben");
  await connect(ANA, "1//refresh-ana-2");
  grant = { access_token: "ya29.again", expires_in: 3600 };
  expect(await accessToken(ENV, space())).toBe("ya29.again");
});

it("deletes the connection when Google ended the sign-in, and refuses with 503 on any other failure, keeping it", async () => {
  await connect();
  status = 500;
  grant = { error: "backend_error" };
  await expect(accessToken(ENV, space())).rejects.toMatchObject({ status: 503, message: "Google's sign-in answered 500. Try again." });
  status = 401;
  grant = { error: "invalid_client" };
  await expect(accessToken(ENV, space())).rejects.toBeInstanceOf(GoogleRefusal);
  vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("offline"); }));
  await expect(accessToken(ENV, space())).rejects.toMatchObject({ status: 503, message: "Google's sign-in could not be reached. Try again." });
  expect(rows("relay_google")).toHaveLength(1);
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    sent.push({ url, body: new URLSearchParams(String(init.body)) });
    return Response.json(grant, { status });
  }));
  status = 400;
  grant = { error: "invalid_grant" };
  expect(await accessToken(ENV, space())).toBeNull();
  expect(rows("relay_google")).toHaveLength(0);
});

it("gives no token with nothing connected or no Google client, and asks Google nothing", async () => {
  expect(await accessToken(ENV, space())).toBeNull();
  await connect();
  expect(await accessToken({}, space())).toBeNull();
  expect(sent).toHaveLength(0);
});

it("ends the sign-in at Google and deletes it on disconnect, and stops the cached token at once", async () => {
  await connect();
  expect(await accessToken(ENV, space())).toBe("ya29.first");
  expect(await disconnect(space())).toBe(true);
  expect(sent.at(-1)).toEqual({ url: REVOKE_URL, body: new URLSearchParams({ token: "1//refresh-ana" }) });
  expect(rows("relay_google")).toHaveLength(0);
  expect(await accessToken(ENV, space())).toBeNull();
  expect(await disconnect(space())).toBe(false);
});

it("deletes a sign-in that no longer opens, asking Google nothing, and keeps an hour when Google names no time", async () => {
  await connect();
  spaces.sql(ANA).prepare("UPDATE relay_google SET token = ?").run(new Uint8Array([1, 2, 3]));
  expect(await disconnect(space())).toBe(true);
  expect(sent).toHaveLength(0);
  await connect();
  spaces.sql(ANA).prepare("UPDATE relay_google SET token = ?").run(new Uint8Array([1, 2, 3]));
  expect(await accessToken(ENV, space())).toBeNull();
  expect(rows("relay_google")).toHaveLength(0);
  await connect();
  grant = { access_token: "ya29.hour" };
  expect(await accessToken(ENV, space())).toBe("ya29.hour");
  vi.setSystemTime(NOW + 58 * 60_000);
  expect(await accessToken(ENV, space())).toBe("ya29.hour");
  expect(sent).toHaveLength(1);
});

it("throws on an answer that is not JSON, and disconnects when Google can't be reached", async () => {
  await connect();
  vi.stubGlobal("fetch", vi.fn(async () => new Response("<html>down</html>", { status: 502 })));
  await expect(accessToken(ENV, space())).rejects.toMatchObject({ status: 503, message: "Google's sign-in answered 502. Try again." });
  vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("offline"); }));
  expect(await disconnect(space())).toBe(true);
  expect(rows("relay_google")).toHaveLength(0);
});
