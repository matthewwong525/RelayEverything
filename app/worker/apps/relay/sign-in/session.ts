// A signed-in browser: a random token in a cookie, kept 30 days, and only its SHA-256 in the directory.
import { cookie, sessionCookie } from "../caller.ts";
import { directory, hashToken, randomToken, type DirectoryEnv } from "../people.ts";

const SESSION_SECONDS = 30 * 24 * 60 * 60;
export const NO_STORE = { "Cache-Control": "no-store" };

/** A refusal in the shape the rest of Relay Everything's API answers with. */
export const answer = (status: number, code: string, message: string) =>
  Response.json({ error: { code, message } }, { status, headers: NO_STORE });

/** A 302 to `location`, with each cookie to set. */
export function redirect(location: string, cookies: string[] = []): Response {
  const headers = new Headers({ Location: location, ...NO_STORE });
  for (const value of cookies) headers.append("Set-Cookie", value);
  return new Response(null, { status: 302, headers });
}

/** The cookie flags for the address: `Secure` only on https, where a browser keeps it. */
export const secure = (url: URL) => url.protocol === "https:" ? "; Secure" : "";

/** Makes a session for the person and answers its Set-Cookie value. */
export async function startSession(env: Pick<DirectoryEnv, "DB">, url: URL, personId: string): Promise<string> {
  const token = randomToken();
  const now = Date.now();
  await directory(env).prepare("INSERT INTO relay_sessions (token_sha256, person_id, created_at, expires_at) VALUES (?, ?, ?, ?)")
    .bind(await hashToken(token), personId, now, now + SESSION_SECONDS * 1000).run();
  return `${sessionCookie(url)}=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${SESSION_SECONDS}${secure(url)}`;
}

/** POST out: ends the browser's session in the directory, so its cookie opens nothing after. */
export async function signOut(request: Request, env: Pick<DirectoryEnv, "DB">): Promise<Response> {
  const url = new URL(request.url);
  const token = cookie(request, sessionCookie(url));
  if (token) await directory(env).prepare("DELETE FROM relay_sessions WHERE token_sha256 = ?").bind(await hashToken(token)).run();
  return Response.json({ ok: true }, { headers: { ...NO_STORE,
    "Set-Cookie": `${sessionCookie(url)}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${secure(url)}` } });
}
