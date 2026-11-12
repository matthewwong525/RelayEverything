// WongStack memory's store and its one-time import on the web API, before /v1/'s own routes: only a computer's key
// reaches them, and only its own person's space. design §2 and §10 of relay-memory-plugin
import { serve, StoreError } from "../../../.agents/skills/memory/store/interface.mjs";
import { importTranscript, memoryImport } from "../relay-memory/import.ts";
import { ownOlderFacts, relayStore } from "../relay-memory/store.ts";
import { Refusal } from "../apps/relay/refusal.ts";
import { COMPUTER_ONLY, type Asker } from "./answers.ts";
import { problem } from "./api.ts";

const STORE = "/v1/memory/v2/";
const IMPORT = "/v1/memory/import";

/** The memory store's or the import's answer, or null for any other route. */
export async function memoryRoute(request: Request, asker: Asker): Promise<Response | null> {
  const { pathname, searchParams } = new URL(request.url);
  const store = pathname.startsWith(STORE);
  if (!store && pathname !== IMPORT && pathname !== `${IMPORT}/transcript`) return null;
  if (asker.adder?.kind !== "agent") return problem(403, COMPUTER_ONLY);
  const { space } = asker, device = asker.adder.deviceId;
  if (store) {
    await ownOlderFacts(space);
    const caller = { role: "admin" as const, subject: space.personId, email: asker.email ?? null };
    return serve(request, { prefix: STORE, caller, store: relayStore(space, caller, device) });
  }
  if (request.method !== "POST") return problem(405, "The import only takes a POST.", { Allow: "POST" });
  try {
    const answer = pathname === IMPORT ? await memoryImport(space, device, await request.json().catch(() => null))
      : await importTranscript(space, searchParams.get("session") ?? "", new Uint8Array(await request.arrayBuffer()));
    return Response.json(answer, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    if (error instanceof Refusal) return problem(error.status, error.message);
    if (error instanceof StoreError) return problem(400, error.message);
    throw error;
  }
}
