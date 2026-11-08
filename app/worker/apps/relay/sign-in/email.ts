// Sign-in by email: a 6-digit code, good for 10 minutes and 5 tries, sent through Cloudflare Email Service. The
// answer is the same for a new and a known address, so the form tells no one who has an account.
import { z } from "zod";
import { directory, hashToken, joinPerson, mayJoin, normalEmail, personByEmail } from "../people.ts";
import { claimOnSignIn } from "../inbox/held.ts";
import type { SignInEnv, Wait } from "./index.ts";
import { ready } from "./oidc.ts";
import { answer, NO_STORE, startSession } from "./session.ts";

const CODE_MS = 10 * 60_000;
const TRIES = 5;
const WRONG = "This code is wrong or old. Ask for a new one.";
const address = z.string().trim().pipe(z.email().max(254));

/** The email sender, when the server has both the binding and its from address. */
const senderOf = (env: SignInEnv) => env.RELAY_EMAIL && env.RELAY_SIGN_IN_FROM ? { email: env.RELAY_EMAIL, from: env.RELAY_SIGN_IN_FROM } : null;

/** GET methods: the ways in this server has set up, so the page shows only those, and its contact address when set. */
export async function methods(_request: Request, env: SignInEnv): Promise<Response> {
  const contact = env.RELAY_CONTACT_EMAIL?.trim();
  return Response.json({ email: !!senderOf(env), apple: ready("apple", env), google: ready("google", env), signUp: env.RELAY_SIGN_UP === "open",
    ...contact ? { contact } : {} }, { headers: NO_STORE });
}

/** The JSON body in this shape, or null. */
async function input<T extends z.ZodType>(request: Request, shape: T): Promise<z.infer<T> | null> {
  const parsed = shape.safeParse(await request.json().catch(() => null));
  return parsed.success ? parsed.data : null;
}

/** True when a rate limit refuses one of the keys. A server with no limit bound, such as a local run, has none. */
export async function limited(env: SignInEnv, keys: string[]): Promise<boolean> {
  for (const key of keys) if (env.RELAY_SIGN_IN_LIMIT && !(await env.RELAY_SIGN_IN_LIMIT.limit({ key })).success) return true;
  return false;
}

export const ipOf = (request: Request) => `ip:${request.headers.get("CF-Connecting-IP") ?? "unknown"}`;
export const tooMany = () => answer(429, "rate_limited", "Too many tries. Wait a few minutes, then try again.");
const codeHash = (email: string, code: string) => hashToken(`${email}:${code}`);

/** The one place a code leaves the server, so another sender can take its place. */
async function sendCode(sender: { email: SendEmail; from: string }, to: string, code: string) {
  const text = `Your Relay Everything sign-in code is ${code}. It works for 10 minutes. If you did not ask for it, do nothing.`;
  await sender.email.send({ from: sender.from, to,
    subject: `${code} is your Relay Everything code`, text, html: `<p>${text}</p>` });
}

/** POST email: makes a new code for the address, in place of an older one, and emails it. */
export async function email(request: Request, env: SignInEnv): Promise<Response> {
  const body = await input(request, z.strictObject({ email: address }));
  if (!body) return answer(400, "invalid_input", "Give an email address.");
  const sender = senderOf(env);
  if (!sender) return answer(503, "unavailable", "This server can't send email codes.");
  const to = normalEmail(body.email);
  if (await limited(env, [`email:${to}`, ipOf(request)])) return tooMany();
  if (!mayJoin(env, to) && !await personByEmail(env, to)) {
    return answer(403, "forbidden", "This Relay Everything server does not take new accounts.");
  }
  const code = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
  await directory(env).prepare(`INSERT INTO relay_sign_in_codes (email, code_sha256, expires_at, tries) VALUES (?, ?, ?, 0)
    ON CONFLICT (email) DO UPDATE SET code_sha256 = excluded.code_sha256, expires_at = excluded.expires_at, tries = 0`)
    .bind(to, await codeHash(to, code), Date.now() + CODE_MS).run();
  await sendCode(sender, to, code);
  return Response.json({ sent: true }, { headers: NO_STORE });
}

type CodeRow = { code_sha256: string; tries: number };

/** POST code: signs in with the emailed code. A code works once; the fifth wrong try ends it. */
export async function code(request: Request, env: SignInEnv, _identity: unknown, wait?: Wait): Promise<Response> {
  const body = await input(request, z.strictObject({ email: address, code: z.string().regex(/^\d{6}$/) }));
  if (!body) return answer(400, "invalid_input", "Give the email address and its 6-digit code.");
  if (await limited(env, [ipOf(request)])) return tooMany();
  const to = normalEmail(body.email);
  const db = directory(env);
  const hash = await codeHash(to, body.code);
  // The try counts before the compare, in one step, so calls at once can't share a try.
  const row = await db.prepare(`UPDATE relay_sign_in_codes SET tries = tries + 1 WHERE email = ? AND tries < ? AND expires_at > ?
    RETURNING code_sha256, tries`).bind(to, TRIES, Date.now()).first<CodeRow>();
  if (!row) return answer(400, "invalid_input", WRONG);
  if (hash !== row.code_sha256) {
    if (row.tries >= TRIES) await db.prepare("DELETE FROM relay_sign_in_codes WHERE email = ? AND tries >= ?").bind(to, TRIES).run();
    return answer(400, "invalid_input", WRONG);
  }
  // Deleting by the hash too means two calls with one code can't both sign in.
  const { results } = await db.prepare("DELETE FROM relay_sign_in_codes WHERE email = ? AND code_sha256 = ? RETURNING email")
    .bind(to, hash).all();
  if (!results.length) return answer(400, "invalid_input", WRONG);
  const person = await joinPerson(env, to);
  if (!person) return answer(403, "forbidden", "This Relay Everything server does not take new accounts.");
  await claimOnSignIn(env, wait)(person);
  return Response.json({ ok: true }, { headers: { ...NO_STORE, "Set-Cookie": await startSession(env, new URL(request.url), person.id) } });
}
