// The two signed tokens of Sign in with Apple and Google: the ID token a provider signs, checked against its published
// keys, and the short client secret Apple asks Relay Everything to sign with its own key.
const encoder = new TextEncoder();

const base64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
const bytesOf = (text: string) => Uint8Array.from(atob(text.replaceAll("-", "+").replaceAll("_", "/")), char => char.charCodeAt(0));
const jsonOf = (text: string): unknown => JSON.parse(new TextDecoder().decode(bytesOf(text)));
const part = (value: unknown) => base64url(encoder.encode(JSON.stringify(value)));

/** The S256 PKCE challenge for a verifier. */
export const challenge = async (verifier: string) =>
  base64url(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(verifier))));

type Claims = { sub: string; email: string };
type Expect = { jwks: string; issuers: string[]; audience: string; nonce: string };
type Raw = { iss?: unknown; aud?: unknown; exp?: unknown; nonce?: unknown; sub?: unknown; email?: unknown; email_verified?: unknown };

/** True when the claims are this provider's, for this client and sign-in, current, and the email is checked. */
function trusted(claims: Raw, expect: Expect): claims is Raw & Claims {
  return expect.issuers.includes(claims.iss as string) && claims.aud === expect.audience && claims.nonce === expect.nonce &&
    typeof claims.exp === "number" && claims.exp * 1000 > Date.now() && typeof claims.sub === "string" &&
    typeof claims.email === "string" && (claims.email_verified === true || claims.email_verified === "true");
}

/** The ID token's person, or null for a token that is not signed by the provider or not meant for this sign-in. */
export async function verifyIdToken(token: string, expect: Expect): Promise<Claims | null> {
  const [head, body, signature] = token.split(".");
  try {
    const header = jsonOf(head) as { alg?: string; kid?: string };
    if (header.alg !== "RS256" || signature === undefined) return null;
    const { keys } = await (await fetch(expect.jwks)).json<{ keys: (JsonWebKey & { kid?: string })[] }>();
    const jwk = keys.find(key => key.kid === header.kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    if (!await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, bytesOf(signature), encoder.encode(`${head}.${body}`))) return null;
    const claims = jsonOf(body) as Raw;
    return trusted(claims, expect) ? { sub: claims.sub, email: claims.email } : null;
  } catch {
    return null;
  }
}

type AppleKey = { team: string; services: string; keyId: string; pem: string };

/** Apple's client secret: a JWT for 5 minutes, signed ES256 with the Sign in with Apple key. */
export async function appleSecret({ team, services, keyId, pem }: AppleKey): Promise<string> {
  // A .p8 file pasted into one line keeps its line breaks as the two letters \n.
  const der = bytesOf(pem.replace(/-----[^-]+-----|\\n|\s/g, ""));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const data = `${part({ alg: "ES256", kid: keyId })}.${part({ iss: team, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: services })}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(data));
  return `${data}.${base64url(new Uint8Array(signature))}`;
}
