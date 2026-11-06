// The directory: who has an account, by a random id, and their email to sign in with. It holds nothing else about a
// person: their data is in their own space. wiki/relay-spaces.md
export type DirectoryEnv = { DB: D1Database; WONG_OWNER_EMAIL?: string; RELAY_SIGN_UP?: string };
export type Person = { id: string; email: string };

export const directory = (env: Pick<DirectoryEnv, "DB">) => env.DB.withSession("first-primary");

/** A token's SHA-256 in hex: the directory keeps only this of each key, session and code. */
export const hashToken = async (text: string): Promise<string> =>
  Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))), hex).join("");
const hex = (byte: number) => byte.toString(16).padStart(2, "0");

/** 32 random bytes as base64url: a key, a session or a code to exchange. */
export function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export const normalEmail = (email: string) => email.trim().toLowerCase();

/** Anyone may make an account while sign-up is open; else only the server's owner. */
export const mayJoin = (env: Omit<DirectoryEnv, "DB">, email: string) =>
  env.RELAY_SIGN_UP === "open" || (!!env.WONG_OWNER_EMAIL && normalEmail(email) === normalEmail(env.WONG_OWNER_EMAIL));

export const personByEmail = (env: Pick<DirectoryEnv, "DB">, email: string) =>
  directory(env).prepare("SELECT id, email FROM relay_people WHERE email = ?").bind(normalEmail(email)).first<Person>();

/** The person with this email, made with a new space when they may join; null when they may not. */
export async function joinPerson(env: DirectoryEnv, email: string): Promise<Person | null> {
  const found = await personByEmail(env, email);
  if (found || !mayJoin(env, email)) return found;
  await directory(env).prepare("INSERT INTO relay_people (id, email, created_at) VALUES (?, ?, ?) ON CONFLICT (email) DO NOTHING")
    .bind(crypto.randomUUID(), normalEmail(email), Date.now()).run();
  return personByEmail(env, email);
}
