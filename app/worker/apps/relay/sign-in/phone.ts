// A phone's way in by signing in from the Relay Everything app: the person confirms *Connect this phone?*, the app gets
// a code that works once for 5 minutes, and trades it with its own secret for the phone's own key, never shown.
import { callerOf } from "../caller.ts";
import { makeDevice } from "../device.ts";
import { directory, hashToken, randomToken } from "../people.ts";
import { spaceOf, vouch, type Caller, type SpaceEnv } from "../space.ts";
import type { Identity } from "../store.ts";
import { ipOf, limited, tooMany } from "./email.ts";
import type { SignInEnv } from "./index.ts";
import { answer, NO_STORE, redirect } from "./session.ts";

const CODE_MS = 5 * 60_000;
/** Where the app waits for the answer: its own address, which only the Relay Everything app opens. */
const RETURN = "relayeverything://connected";
/** The SHA-256 of the app's secret, in base64url: 43 letters. */
export const CHALLENGE = /^[A-Za-z0-9_-]{43}$/;
export const VERIFIER = /^[A-Za-z0-9_-]{43,128}$/;
const USED = "This sign-in was used already, or is too old. Start again from the Relay Everything app.";

export const escape = (text: string) => text.replace(/[&<>"']/g, char => `&#${char.charCodeAt(0)};`);
const STYLE = "font-family:system-ui;max-width:28rem;margin:3rem auto;padding:0 1rem;line-height:1.5";
export const FIELD = "display:block;width:100%;box-sizing:border-box;padding:.6rem;margin:.5rem 0 1rem;font-size:1rem;border:1px solid #ccc;border-radius:.5rem";
export const BUTTON = "display:block;width:100%;padding:.7rem;margin-top:.5rem;font-size:1rem;border-radius:.5rem;border:1px solid #3f51b5";

export function page(body: string, status = 200): Response {
  return new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Relay Everything</title><body style="${STYLE}">${body}</body>`, { status, headers: { "Content-Type": "text/html; charset=utf-8", ...NO_STORE } });
}

/** The phone's name as the app sent or the person typed it, or `Phone`. */
const nameOf = (value: unknown) => (typeof value === "string" ? value.trim().slice(0, 60) : "") || "Phone";
export const isPerson = (caller: Caller) => caller.kind === "session" || caller.kind === "access";

/** The secret's SHA-256 in base64url, as the app makes its challenge. */
export async function challengeOf(verifier: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
  return btoa(String.fromCharCode(...digest)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

/** GET phone: signed out, the sign-in first and then back here; signed in, *Connect this phone?* with its name. */
export async function phone(request: Request, env: SignInEnv, identity: Identity): Promise<Response> {
  const url = new URL(request.url);
  const challenge = url.searchParams.get("challenge") ?? "";
  if (!CHALLENGE.test(challenge)) return page("<h1>Relay Everything</h1><p>This connect link is not valid. Start again from the Relay Everything app.</p>", 400);
  const caller = await callerOf(request, env, identity);
  if (caller instanceof Response) return caller;
  if (!caller) return redirect(`/?next=${encodeURIComponent(url.pathname + url.search)}`);
  if (!isPerson(caller)) return answer(403, "forbidden", "Sign in as a person to connect a phone.");
  return page(`<h1>Connect this phone?</h1>
<form method="post"><input type="hidden" name="challenge" value="${challenge}">
<label for="name">Name</label><input id="name" name="name" maxlength="60" value="${escape(nameOf(url.searchParams.get("name")))}" style="${FIELD}">
<p>It can add notes, health, places and photos to your space. It can't read them. You can turn it off on your Relay Everything page.</p>
<button name="choice" value="connect" style="${BUTTON};background:#3f51b5;color:#fff">Connect</button>
<button name="choice" value="cancel" style="${BUTTON};background:none;color:#3f51b5">Cancel</button></form>`);
}

/** POST phone: *Connect* keeps the code's SHA-256 for 5 minutes and hands the code to the app; *Cancel* tells it. */
export async function phoneConfirm(request: Request, env: SignInEnv, identity: Identity): Promise<Response> {
  const form = await request.formData().catch(() => null);
  if (form?.get("choice") !== "connect") return redirect(`${RETURN}?error=cancelled`);
  const challenge = String(form.get("challenge") ?? "");
  if (!CHALLENGE.test(challenge)) return answer(400, "invalid_input", "This connect link is not valid. Start again from the Relay Everything app.");
  const caller = await callerOf(request, env, identity);
  if (caller instanceof Response) return caller;
  if (!caller || !isPerson(caller)) return answer(403, "forbidden", "Sign in as a person to connect a phone.");
  const code = randomToken();
  await directory(env).prepare("INSERT INTO relay_phone_codes (code_sha256, person_id, name, challenge, expires_at) VALUES (?, ?, ?, ?, ?)")
    .bind(await hashToken(code), caller.personId, nameOf(form.get("name")), challenge, Date.now() + CODE_MS).run();
  return redirect(`${RETURN}?code=${code}`);
}

type CodeRow = { person_id: string; name: string; challenge: string };

/** POST phone/key: the app trades the code and its secret for the phone's own key, once. A code's first try ends it. */
export async function phoneKey(request: Request, env: SignInEnv): Promise<Response> {
  if (await limited(env, [ipOf(request)])) return tooMany();
  const body = await request.json().catch(() => null) as { code?: unknown; verifier?: unknown } | null;
  const code = typeof body?.code === "string" && body.code.length <= 100 ? body.code : "";
  const verifier = typeof body?.verifier === "string" ? body.verifier : "";
  if (!code || !VERIFIER.test(verifier)) return answer(400, "invalid_input", "Give the sign-in's code and the app's secret.");
  const row = await directory(env).prepare("DELETE FROM relay_phone_codes WHERE code_sha256 = ? AND expires_at > ? RETURNING person_id, name, challenge")
    .bind(await hashToken(code), Date.now()).first<CodeRow>();
  if (!row || row.challenge !== await challengeOf(verifier)) return answer(400, "invalid_input", USED);
  const spaces = env as SignInEnv & Partial<SpaceEnv>;
  if (!spaces.SPACES) return answer(503, "unavailable", "This Relay Everything server has no spaces. Use the shared server.");
  // The code and its secret are this file's own check of the person, so it vouches for them here.
  const caller = vouch("code", row.person_id);
  const { key } = await makeDevice(spaceOf(spaces as SpaceEnv, caller), env, caller, row.name, "phone");
  return Response.json({ server: new URL(request.url).origin, key }, { headers: NO_STORE });
}
