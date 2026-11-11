// Who calls Relay Everything, checked once per request: a device key, the preview checker, a signed-in browser, or
// the email Access checked on a self-host or the company app. Each route opens only that caller's space.
import { directory, hashToken, joinPerson, type DirectoryEnv } from "./people.ts";
import { spaceOf, vouch, type Caller, type PersonSpace, type Reach, type SpaceEnv } from "./space.ts";
import { refused, type Env, type Identity } from "./store.ts";

export type CallerEnv = DirectoryEnv & { RELAY_CHECKER_SHA256?: string };

/** The preview checker's own empty space: it signs in as this fixed test person, never as a real one. */
export const CHECKER_PERSON = "00000000-0000-4000-8000-000000000000";
export const KEY = /^Bearer (rek_[A-Za-z0-9_-]{43})$/;
export const SESSION_COOKIE = "__Host-relay_session";
/** A browser keeps a `__Host-` cookie only from https, so a local run on http uses the plain name. */
export const sessionCookie = (url: URL) => url.protocol === "https:" ? SESSION_COOKIE : "relay_session";

/** A key's reach: POST and `GET key` (its own name); a phone also reads `GET connections` (names and addresses) and its
 *  notes and files, changes or deletes any note, and signs out a phone. `GET chats` and a send share an address. */
const REACH: Record<Reach, { routes: RegExp; refusal: string }> = {
  phone: { routes: /^\/apps\/relay\/api\/(?:notes|attachments|health|nights|locations|stays|calendar|photos)$/, refusal: "A device key can only send to Relay Everything." },
  chats: { routes: /^\/apps\/relay\/api\/(?:chats|chat-saves)$/, refusal: "A chat key can only send chats." },
  api: { routes: /^$/, refusal: "An API key works only on the web API, at your AI connector's address under /v1/." },
  agent: { routes: /^\/apps\/relay\/api\/(?:chats|chat-saves)$/, refusal: "A computer's key sends chats here, and reads through the web API under /v1/." },
};
const KEY_CHECK = "/apps/relay/api/key";
const NOTES = "/apps/relay/api/notes";
/** A phone's reads: its account's email, names and notes addresses, and its notes, files and old ring recordings. */
const PHONE_READS = /^\/apps\/relay\/api\/(?:connections|notes|attachment|audio)$/;
/** A phone signs out a lost phone; the route refuses a computer or an API key. */
const SIGN_OUT = "/apps/relay/api/devices/off";

/** True when a key of this reach may call the method on the address. */
export function reaches(reach: Reach, method: string, pathname: string): boolean {
  if (method === "GET") return pathname === KEY_CHECK || (reach === "phone" && PHONE_READS.test(pathname));
  if (method === "PATCH" || method === "DELETE") return reach === "phone" && pathname === NOTES;
  return method === "POST" && (REACH[reach].routes.test(pathname) || (reach === "phone" && pathname === SIGN_OUT));
}

type KeyRow = { person_id: string; email: string; device_id: string; reaches: Reach; revoked_at: number | null };

async function keyCaller(env: Pick<CallerEnv, "DB">, key: string): Promise<Caller | Response> {
  const row = await directory(env).prepare(`SELECT k.person_id, p.email, k.device_id, k.reaches, k.revoked_at FROM relay_keys k
    JOIN relay_people p ON p.id = k.person_id WHERE k.key_sha256 = ?`).bind(await hashToken(key)).first<KeyRow>();
  if (!row) return refused(403, "This key is on no list of devices.");
  if (row.revoked_at !== null) return refused(403, "This device key is turned off.");
  return vouch("key", row.person_id, { email: row.email, device: { id: row.device_id, reaches: row.reaches } });
}

/** The web API's caller from its `rek_` key: only a live API key or computer's key, never a phone's or a chat's. */
export async function apiKeyCaller(env: Pick<CallerEnv, "DB">, key: string): Promise<Caller | Response> {
  const caller = await keyCaller(env, key);
  if (caller instanceof Response || caller.device?.reaches === "api" || caller.device?.reaches === "agent") return caller;
  if (caller.device?.reaches === "chats") return refused(403, "This computer's key only saves chats. Type /relay:connect to connect it again.");
  return refused(403, "A phone key only sends. Make an API key on your Relay Everything page.");
}

/** A cookie's value from the request, or null. */
export function cookie(request: Request, name: string): string | null {
  for (const part of (request.headers.get("Cookie") ?? "").split(";")) {
    const [key, ...value] = part.trim().split("=");
    if (key === name) return value.join("=") || null;
  }
  return null;
}

async function sessionCaller(env: CallerEnv, token: string): Promise<Caller | null> {
  const row = await directory(env).prepare(`SELECT p.id, p.email FROM relay_sessions s JOIN relay_people p ON p.id = s.person_id
    WHERE s.token_sha256 = ? AND s.expires_at > ?`).bind(await hashToken(token), Date.now()).first<{ id: string; email: string }>();
  return row && vouch("session", row.id, { email: row.email });
}

/** Access's email on a server that signs in with Access: its person, made only for one who may join. */
async function accessCaller(env: CallerEnv, email: string): Promise<Caller | Response> {
  const person = await joinPerson(env, email);
  return person ? vouch("access", person.id, { email: person.email }) : refused(403, "This email has no Relay Everything account on this server.");
}

async function resolve(request: Request, env: CallerEnv, identity: Identity): Promise<Caller | Response | null> {
  const bearer = KEY.exec(request.headers.get("Authorization") ?? "");
  if (bearer) return keyCaller(env, bearer[1]);
  // Git holds only the checker's fingerprint: its Client ID stays in .env with the other checker values.
  if (identity?.kind === "service") {
    return await hashToken(identity.id) === env.RELAY_CHECKER_SHA256 ? vouch("checker", CHECKER_PERSON) : refused(403, "This key is on no list of devices.");
  }
  const token = cookie(request, sessionCookie(new URL(request.url)));
  const signedIn = token ? await sessionCaller(env, token) : null;
  if (signedIn) return signedIn;
  const email = identity?.kind === "user" ? identity.claims.email : undefined;
  return email ? accessCaller(env, email) : null;
}

const callers = new WeakMap<Request, Promise<Caller | Response | null>>();

/** The request's caller, a refusal, or null for no one signed in. The Worker's gate asks first; each route's answer
 *  then comes from the same check. */
export function callerOf(request: Request, env: CallerEnv, identity: Identity): Promise<Caller | Response | null> {
  let found = callers.get(request);
  if (!found) {
    found = resolve(request, env, identity).catch(() => refused(503, "Relay Everything's accounts could not be read. Try again."));
    callers.set(request, found);
  }
  return found;
}

/** The Worker's check before every route: null lets the call go on. A device key reaches only its own routes, and a
 *  service token that is not the checker is refused everywhere. */
export async function relayGate(request: Request, env: CallerEnv, identity: Identity, pathname: string): Promise<Response | null> {
  if (!KEY.test(request.headers.get("Authorization") ?? "") && identity?.kind !== "service" && !pathname.startsWith("/apps/relay/")) return null;
  const caller = await callerOf(request, env, identity);
  if (caller instanceof Response) return caller;
  if (caller?.device && !reaches(caller.device.reaches, request.method, pathname)) return refused(403, REACH[caller.device.reaches].refusal);
  // A browser sends its cookie from any site, so a change by cookie needs the page's own Origin.
  const changes = !["GET", "HEAD", "OPTIONS"].includes(request.method);
  // Access's cookie goes from any site too, so a change by Access email needs it as well.
  const byCookie = caller?.kind === "session" || caller?.kind === "access";
  if (byCookie && changes && request.headers.get("Origin") !== new URL(request.url).origin) {
    return refused(403, "This change must come from the Relay Everything page.");
  }
  return null;
}

type Call = { identity: Identity };

// A preview reaches no other Worker's objects, so it has no spaces: wiki/stack/live-line.md
const openSpace = (env: Env, caller: Caller) => env.SPACES ? spaceOf(env as SpaceEnv, caller)
  : refused(503, "This Relay Everything server has no spaces. Use the shared server.");
type Context<C> = { space: PersonSpace; caller: Caller; request: Request; env: Env; call: C };

type Run<C> = (context: Context<C>) => Promise<Response>;

/** A route for a signed-in person, or with `phone` also for a phone key, in that person's own space. */
const asSignedIn = <C extends Call>(phone: boolean, run: Run<C>) =>
  async (request: Request, env: Env, call: C): Promise<Response> => {
    const caller = await callerOf(request, env, call.identity);
    if (caller instanceof Response) return caller;
    if (!caller) return refused(401, "Sign in to Relay Everything.");
    if (caller.device && !(phone && caller.device.reaches === "phone")) return refused(403, "A device key can only send to Relay Everything.");
    const space = openSpace(env, caller);
    return space instanceof Response ? space : run({ space, caller, request, env, call });
  };

/** A route for a signed-in person: their session, Access email or the checker. A device key reads nothing. */
export const asPerson = <C extends Call>(run: Run<C>) => asSignedIn(false, run);

/** A route a phone key reaches too, as the gate lets it only for names, notes and signing out a phone: never health,
 *  places or photos. */
export const asPersonOrPhone = <C extends Call>(run: Run<C>) => asSignedIn(true, run);

/** A route for a device key: it adds data to its own person's space, named by its own device. */
export const asDevice = <C extends Call>(refusal: string, run: (context: Context<C> & { device: NonNullable<Caller["device"]> }) => Promise<Response>) =>
  async (request: Request, env: Env, call: C): Promise<Response> => {
    const caller = await callerOf(request, env, call.identity);
    if (caller instanceof Response) return caller;
    if (!caller?.device) return refused(403, refusal);
    const space = openSpace(env, caller);
    return space instanceof Response ? space : run({ space, caller, device: caller.device, request, env, call });
  };

/** The page's own device in the space: the notes a signed-in person writes on the page name it, as emailed notes name
 *  *Email*. It has no key, so the list of devices leaves it out with the inbox's. */
const WEB = { name: "Web", token: "page:web" };

/** The space's Web device's id: `make` adds it on the page's first write; a read only looks, and finds null before. */
export async function webDevice(space: PersonSpace, make: boolean): Promise<string | null> {
  if (!make) return (await space.db.prepare("SELECT id FROM relay_devices WHERE token_client_id = ?").bind(WEB.token).first<{ id: string }>())?.id ?? null;
  const row = await space.db.prepare(`INSERT INTO relay_devices (id, name, token_client_id, token_id, created_at, revoked_at, reaches)
    VALUES (?, ?, ?, '', ?, NULL, 'inbox') ON CONFLICT (token_client_id) DO UPDATE SET token_id = excluded.token_id RETURNING id`)
    .bind(crypto.randomUUID(), WEB.name, WEB.token, Date.now()).first<{ id: string }>();
  return row!.id;
}

/** A note route for a phone key, named by its own device, or for a signed-in person on the page, named by the space's
 *  Web device. A chat or API key is refused; no key gains reach. */
export const asDeviceOrPage = <C extends Call>(refusal: string, run: (context: Context<C> & { deviceId: string }) => Promise<Response>) =>
  async (request: Request, env: Env, call: C): Promise<Response> => {
    const caller = await callerOf(request, env, call.identity);
    if (caller instanceof Response) return caller;
    if (!caller) return refused(401, "Sign in to Relay Everything.");
    if (caller.device && caller.device.reaches !== "phone") return refused(403, refusal);
    const space = openSpace(env, caller);
    if (space instanceof Response) return space;
    const deviceId = caller.device?.id ?? await webDevice(space, true);
    return run({ space, caller, deviceId: deviceId!, request, env, call });
  };
