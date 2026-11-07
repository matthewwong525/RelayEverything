// Sign in with Apple and Google: the code flow with `state` and a nonce, plus PKCE for Google. The ID token is checked
// against the provider's keys, and only a checked email signs in.
import { cookie } from "../caller.ts";
import { directory, joinPerson, randomToken, type Person } from "../people.ts";
import type { SignInEnv } from "./index.ts";
import { appleSecret, challenge, verifyIdToken } from "./jwt.ts";
import { answer, redirect, secure, startSession } from "./session.ts";

type Provider = "apple" | "google";
type Saved = { provider: Provider; state: string; nonce: string; verifier: string; next: string };

const OAUTH = "relay_oauth";
const HOME = "/apps/relay/";
const FAILED = `${HOME}?signIn=failed`;

/** Google's sign-in addresses, which Connect Google shares: google/connect.ts. */
export const GOOGLE = { authorize: "https://accounts.google.com/o/oauth2/v2/auth", token: "https://oauth2.googleapis.com/token",
  jwks: "https://www.googleapis.com/oauth2/v3/certs", issuers: ["accounts.google.com", "https://accounts.google.com"] };

const PROVIDERS = {
  google: {
    ...GOOGLE,
    params: { scope: "openid email", response_type: "code" },
    client: (env: SignInEnv) => env.RELAY_GOOGLE_CLIENT_ID && env.RELAY_GOOGLE_SIGN_IN_SECRET
      ? { id: env.RELAY_GOOGLE_CLIENT_ID, secret: async () => env.RELAY_GOOGLE_SIGN_IN_SECRET! } : null,
  },
  apple: {
    authorize: "https://appleid.apple.com/auth/authorize", token: "https://appleid.apple.com/auth/token",
    jwks: "https://appleid.apple.com/auth/keys", issuers: ["https://appleid.apple.com"],
    // Apple sends the email only to a form post, so its answer comes back as a POST from Apple's own site.
    params: { scope: "name email", response_type: "code", response_mode: "form_post" },
    client: ({ RELAY_APPLE_TEAM_ID: team, RELAY_APPLE_SERVICES_ID: services, RELAY_APPLE_SIGN_IN_KEY_ID: keyId,
      RELAY_APPLE_SIGN_IN_KEY: pem }: SignInEnv) => team && services && keyId && pem
      ? { id: services, secret: () => appleSecret({ team, services, keyId, pem }) } : null,
  },
};

/** True when the server has this provider's values. */
export const ready = (provider: Provider, env: SignInEnv) => PROVIDERS[provider].client(env) !== null;

/** Only a path on Relay Everything's page may follow a sign-in, so no link can send a person elsewhere. */
const safeNext = (next: string | null) => next?.startsWith(HOME) ? next : HOME;
const callbackOf = (url: URL, provider: Provider) => `${url.origin}/apps/relay/sign-in/${provider}/callback`;

/** The cookie that carries a sign-in's state to its callback. SameSite=None, since Apple's callback is a cross-site
 *  POST; that needs Secure, so a local http run uses Lax and only Google. */
const oauthCookie = (url: URL, value: string, seconds: number) => `${OAUTH}=${value}; Path=/apps/relay/sign-in/; HttpOnly; ` +
  `Max-Age=${seconds}${url.protocol === "https:" ? "; SameSite=None" : "; SameSite=Lax"}${secure(url)}`;

/** GET apple, GET google: sends the browser to the provider. */
export const start = (provider: Provider) => async (request: Request, env: SignInEnv): Promise<Response> => {
  const client = PROVIDERS[provider].client(env);
  if (!client) return answer(503, "unavailable", "This server does not sign in this way.");
  const url = new URL(request.url);
  const saved: Saved = { provider, state: randomToken(), nonce: randomToken(), verifier: randomToken(), next: safeNext(url.searchParams.get("next")) };
  const params = new URLSearchParams({ client_id: client.id, redirect_uri: callbackOf(url, provider), state: saved.state, nonce: saved.nonce,
    ...PROVIDERS[provider].params });
  if (provider === "google") {
    params.set("code_challenge", await challenge(saved.verifier));
    params.set("code_challenge_method", "S256");
  }
  return redirect(`${PROVIDERS[provider].authorize}?${params}`, [oauthCookie(url, btoa(JSON.stringify(saved)), 600)]);
};

function savedOf(request: Request): Saved | null {
  try {
    return JSON.parse(atob(cookie(request, OAUTH) ?? "")) as Saved;
  } catch {
    return null;
  }
}

/** The code and state the provider sent back: a form post from Apple, the address's query from Google. */
async function answerOf(request: Request, provider: Provider): Promise<URLSearchParams> {
  if (provider === "google") return new URL(request.url).searchParams;
  const form = await request.formData().catch(() => new FormData());
  return new URLSearchParams([...form].filter((entry): entry is [string, string] => typeof entry[1] === "string"));
}

/** Trades the code for the provider's ID token, or null. */
async function idTokenOf(provider: Provider, env: SignInEnv, url: URL, code: string, saved: Saved): Promise<string | null> {
  const client = PROVIDERS[provider].client(env);
  if (!client) return null;
  const form = new URLSearchParams({ grant_type: "authorization_code", code, redirect_uri: callbackOf(url, provider),
    client_id: client.id, client_secret: await client.secret() });
  if (provider === "google") form.set("code_verifier", saved.verifier);
  const response = await fetch(PROVIDERS[provider].token, { method: "POST", body: form });
  const tokens = response.ok ? await response.json<{ id_token?: unknown }>() : {};
  return typeof tokens.id_token === "string" ? tokens.id_token : null;
}

/** The person this login belongs to: by the provider's own id once linked, else by the checked email. */
async function personOf(env: SignInEnv, provider: Provider, sub: string, email: string): Promise<Person | null> {
  const db = directory(env);
  const linked = await db.prepare(`SELECT p.id, p.email FROM relay_logins l JOIN relay_people p ON p.id = l.person_id
    WHERE l.provider = ? AND l.subject = ?`).bind(provider, sub).first<Person>();
  if (linked) return linked;
  const person = await joinPerson(env, email);
  if (person) {
    await db.prepare("INSERT INTO relay_logins (provider, subject, person_id, created_at) VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING")
      .bind(provider, sub, person.id, Date.now()).run();
  }
  return person;
}

/** GET google/callback, POST apple/callback: checks the provider's answer, then signs the person in. */
export const callback = (provider: Provider) => async (request: Request, env: SignInEnv): Promise<Response> => {
  const url = new URL(request.url);
  const clear = oauthCookie(url, "", 0);
  const saved = savedOf(request);
  const sent = await answerOf(request, provider);
  const code = sent.get("code");
  if (saved?.provider !== provider || !code || sent.get("state") !== saved.state) return redirect(FAILED, [clear]);
  try {
    const token = await idTokenOf(provider, env, url, code, saved);
    const claims = token && await verifyIdToken(token, { jwks: PROVIDERS[provider].jwks, issuers: PROVIDERS[provider].issuers,
      audience: PROVIDERS[provider].client(env)!.id, nonce: saved.nonce });
    const person = claims && await personOf(env, provider, claims.sub, claims.email);
    return person ? redirect(saved.next, [await startSession(env, url, person.id), clear]) : redirect(FAILED, [clear]);
  } catch {
    return redirect(FAILED, [clear]);
  }
};
