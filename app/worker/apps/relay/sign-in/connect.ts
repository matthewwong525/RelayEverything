// GET connect: the AI connector's way in. A signed-in person comes back to the connector with a code that works once,
// for 5 minutes; the connector trades it for the person's id and nothing else.
import { callerOf } from "../caller.ts";
import { directory, hashToken, randomToken } from "../people.ts";
import type { Identity } from "../store.ts";
import type { SignInEnv } from "./index.ts";
import { answer, redirect } from "./session.ts";

const CODE_MS = 5 * 60_000;

export async function connect(request: Request, env: SignInEnv, identity: Identity): Promise<Response> {
  const url = new URL(request.url);
  const state = url.searchParams.get("state") ?? "";
  if (!state || state.length > 512) return answer(400, "invalid_input", "The AI app sent no sign-in state.");
  // Only the connector's own callback, never an address from the request, gets the code.
  if (!env.RELAY_MCP_CALLBACK) return answer(503, "unavailable", "This server has no AI connector.");
  const caller = await callerOf(request, env, identity);
  if (caller instanceof Response) return caller;
  if (!caller) return redirect(`/?next=${encodeURIComponent(url.pathname + url.search)}`);
  if (caller.kind !== "session" && caller.kind !== "access") return answer(403, "forbidden", "Sign in as a person to connect an AI app.");
  const code = randomToken();
  await directory(env).prepare("INSERT INTO relay_connect_codes (code_sha256, person_id, expires_at) VALUES (?, ?, ?)")
    .bind(await hashToken(code), caller.personId, Date.now() + CODE_MS).run();
  const target = new URL(env.RELAY_MCP_CALLBACK);
  target.searchParams.set("code", code);
  target.searchParams.set("state", state);
  return redirect(target.href);
}
