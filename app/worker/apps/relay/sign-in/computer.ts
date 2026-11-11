// A computer's way in from Claude Code or Codex: `/relay:connect` sends its secret's SHA-256 and shows a link and code.
// The person signs in there and clicks Connect; the computer asks every few seconds and gets its own key, once.
import { callerOf } from "../caller.ts";
import { apiAddress, makeDevice } from "../device.ts";
import { directory } from "../people.ts";
import { spaceOf, vouch, type SpaceEnv } from "../space.ts";
import type { Identity } from "../store.ts";
import { ipOf, limited, tooMany } from "./email.ts";
import type { SignInEnv } from "./index.ts";
import { BUTTON, CHALLENGE, challengeOf, escape, FIELD, isPerson, page, VERIFIER } from "./phone.ts";
import { answer, NO_STORE, redirect } from "./session.ts";

const LINK_MS = 10 * 60_000;
const LINK = "/apps/relay/sign-in/computer";
const AGAIN = "Start again on your computer: type /relay:connect.";
const USED = `This link was used already, or is too old. ${AGAIN}`;
/** Short words for the code a person compares: one of these and four digits, such as KITE-4821. */
const WORDS = ["KITE", "LAKE", "MOON", "PINE", "ROCK", "SAND", "TREE", "WAVE", "BIRD", "FISH", "LEAF", "STAR", "RAIN", "SNOW", "WIND", "FERN",
  "BOAT", "DOOR", "LAMP", "BELL", "COIN", "DRUM", "GOLD", "HILL", "IRON", "JADE", "MILK", "NEST", "OPAL", "PEAR", "ROSE", "SALT"];

/** The computer's name as it sent it or the person typed it, or `Computer`. */
const nameOf = (value: unknown) => (typeof value === "string" ? value.trim().slice(0, 60) : "") || "Computer";

function words(): string {
  const [word, digits] = crypto.getRandomValues(new Uint32Array(2));
  return `${WORDS[word % WORDS.length]}-${String(digits % 10_000).padStart(4, "0")}`;
}

type Row = { words: string; name: string; person_id: string | null };

/** The link's row while it is new, or null. */
const rowOf = (env: SignInEnv, challenge: string) => directory(env).prepare(
  "SELECT words, name, person_id FROM relay_computer_codes WHERE challenge = ? AND expires_at > ?").bind(challenge, Date.now()).first<Row>();

const json = async (request: Request) => await request.json().catch(() => null) as Record<string, unknown> | null;

/** POST computer/start: the computer's secret's SHA-256 and its name. Keeps a row for 10 minutes; answers the link and
 *  the code. No person yet: the link is what a person confirms. */
export async function computerStart(request: Request, env: SignInEnv): Promise<Response> {
  if (await limited(env, [ipOf(request)])) return tooMany();
  const body = await json(request);
  const challenge = typeof body?.challenge === "string" ? body.challenge : "";
  if (!CHALLENGE.test(challenge)) return answer(400, "invalid_input", "Give the SHA-256 of the computer's secret, in base64url.");
  const db = directory(env);
  const now = Date.now();
  const code = words();
  await db.prepare("DELETE FROM relay_computer_codes WHERE expires_at <= ?").bind(now).run();
  const made = await db.prepare(`INSERT INTO relay_computer_codes (challenge, words, name, person_id, expires_at) VALUES (?, ?, ?, NULL, ?)
    ON CONFLICT (challenge) DO NOTHING RETURNING challenge`).bind(challenge, code, nameOf(body?.name), now + LINK_MS).first();
  if (!made) return answer(400, "invalid_input", "This secret was used already. Make a new one.");
  const link = `${new URL(request.url).origin}${LINK}?c=${challenge}`;
  return Response.json({ link, words: code }, { headers: NO_STORE });
}

/** GET computer?c=: signed out, the sign-in first and then back here; signed in, *Connect this computer?* with its
 *  name, the code to compare, and what the key can do. */
export async function computer(request: Request, env: SignInEnv, identity: Identity): Promise<Response> {
  const url = new URL(request.url);
  const challenge = url.searchParams.get("c") ?? "";
  if (!CHALLENGE.test(challenge)) return page(`<h1>Relay Everything</h1><p>This connect link is not valid. ${AGAIN}</p>`, 400);
  const caller = await callerOf(request, env, identity);
  if (caller instanceof Response) return caller;
  if (!caller) return redirect(`/?next=${encodeURIComponent(url.pathname + url.search)}`);
  if (!isPerson(caller)) return answer(403, "forbidden", "Sign in as a person to connect a computer.");
  const row = await rowOf(env, challenge);
  if (!row || row.person_id) return page(`<h1>Relay Everything</h1><p>${USED}</p>`, 400);
  return page(`<h1>Connect this computer?</h1>
<p>Check that this code is the one on your computer:</p>
<p style="font-size:1.6rem;font-weight:700;letter-spacing:.1em;text-align:center">${escape(row.words)}</p>
<p><b>Connect only a computer you just started this on.</b> If someone sent you this link, click Cancel.</p>
<form method="post"><input type="hidden" name="c" value="${challenge}">
<label for="name">Name</label><input id="name" name="name" maxlength="60" value="${escape(row.name)}" style="${FIELD}">
<p>It saves your AI chats from Claude Code and Codex and reads all your Relay Everything data. To stop it, disconnect it in Connect your AI on your Relay Everything page.</p>
<button name="choice" value="connect" style="${BUTTON};background:#3f51b5;color:#fff">Connect</button>
<button name="choice" value="cancel" style="${BUTTON};background:none;color:#3f51b5">Cancel</button></form>`);
}

/** POST computer (form): *Connect* names the person on the row, once; *Cancel* deletes it, so the computer stops. */
export async function computerConfirm(request: Request, env: SignInEnv, identity: Identity): Promise<Response> {
  const form = await request.formData().catch(() => null);
  const challenge = String(form?.get("c") ?? "");
  if (!CHALLENGE.test(challenge)) return answer(400, "invalid_input", `This connect link is not valid. ${AGAIN}`);
  const caller = await callerOf(request, env, identity);
  if (caller instanceof Response) return caller;
  if (!caller || !isPerson(caller)) return answer(403, "forbidden", "Sign in as a person to connect a computer.");
  const db = directory(env);
  if (form?.get("choice") !== "connect") {
    await db.prepare("DELETE FROM relay_computer_codes WHERE challenge = ? AND person_id IS NULL").bind(challenge).run();
    return page("<h1>Cancelled</h1><p>The computer is not connected. You can close this page.</p>");
  }
  const done = await db.prepare(`UPDATE relay_computer_codes SET person_id = ?, name = ? WHERE challenge = ? AND person_id IS NULL AND expires_at > ?
    RETURNING name`).bind(caller.personId, nameOf(form.get("name")), challenge, Date.now()).first<{ name: string }>();
  if (!done) return page(`<h1>Relay Everything</h1><p>${USED}</p>`, 400);
  return page(`<h1>Connected</h1><p>${escape(done.name)} is connected to Relay Everything. Go back to your computer.</p>`);
}

/** POST computer/key: the secret finds its row; waiting until Connect, then the key, once. A 256-bit secret that lives
 *  10 minutes needs no rate limit, so the computer may ask every few seconds. */
export async function computerKey(request: Request, env: SignInEnv): Promise<Response> {
  const body = await json(request);
  const verifier = typeof body?.verifier === "string" ? body.verifier : "";
  if (!VERIFIER.test(verifier)) return answer(400, "invalid_input", "Give the computer's secret.");
  const spaces = env as SignInEnv & Partial<SpaceEnv>;
  if (!spaces.SPACES) return answer(503, "unavailable", "This Relay Everything server has no spaces. Use the shared server.");
  const challenge = await challengeOf(verifier);
  // One DELETE takes a confirmed row, so two asks at once can't both make a key.
  const taken = await directory(env).prepare(`DELETE FROM relay_computer_codes WHERE challenge = ? AND person_id IS NOT NULL AND expires_at > ?
    RETURNING person_id, name`).bind(challenge, Date.now()).first<{ person_id: string; name: string }>();
  if (!taken) return await rowOf(env, challenge) ? Response.json({ waiting: true }, { status: 202, headers: NO_STORE }) : answer(400, "invalid_input", USED);
  // The secret and the person's Connect are this file's own check of the person, so it vouches for them here.
  const caller = vouch("code", taken.person_id);
  const { key } = await makeDevice(spaceOf(spaces as SpaceEnv, caller), env, caller, taken.name, "agent");
  return Response.json({ server: new URL(request.url).origin, key, api: apiAddress(env), name: taken.name }, { headers: NO_STORE });
}
