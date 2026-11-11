// Each person's knowledge web: one Artifacts repo, `p-<personId>`, made on the first ask as a copy of the namespace's
// `start` repo, which scripts/relay-knowledge-setup.mjs fills. wiki/stack/relay-knowledge-web.md
import { Refusal } from "./refusal.ts";

const START = "start";
/** A pass ends within one hour: *Turn off* can't call back a pass already given. */
const PASS_SECONDS = 3600;
export const NOT_SET_UP = "The knowledge web is not set up on this server.";
const TRIES = 4;
const WAIT = 1000;

const repoName = (personId: string) => `p-${personId}`;
const codeOf = (error: unknown) => typeof error === "object" && error !== null && "code" in error ? error.code : undefined;
const sleep = (ms: number) => new Promise(done => setTimeout(done, ms));

/** Copies the start repo into the person's own; a copy another ask began already is fine. */
async function fork(knowledge: Artifacts, name: string) {
  let start: ArtifactsRepo;
  try {
    start = await knowledge.get(START);
  } catch (error) {
    if (codeOf(error) === "NOT_FOUND") throw new Refusal(NOT_SET_UP, 501);
    throw error;
  }
  try {
    await start.fork(name, { defaultBranchOnly: true, description: "A Relay Everything knowledge web." });
  } catch (error) {
    if (codeOf(error) !== "ALREADY_EXISTS" && codeOf(error) !== "FORK_IN_PROGRESS") throw error;
  }
}

/** The person's repo, made by a fork the first time; a fork still running is waited for a few seconds. */
async function repoOf(knowledge: Artifacts, personId: string, wait: (ms: number) => Promise<unknown>) {
  const name = repoName(personId);
  for (let tries = 1; ; tries++) {
    try {
      return await knowledge.get(name);
    } catch (error) {
      if (codeOf(error) === "NOT_FOUND" && tries === 1) await fork(knowledge, name);
      else if (codeOf(error) !== "FORK_IN_PROGRESS" && codeOf(error) !== "NOT_FOUND") throw error;
      if (tries === TRIES) throw new Refusal("Your knowledge web is still being made. Try again in a minute.", 503);
      if (tries > 1) await wait(WAIT);
    }
  }
}

/** The repo's details, its git address in them. The real handle answers `remote` only through `info()`, though the
 *  generated types list it on the handle itself. */
const infoOf = (repo: ArtifactsRepo) => (repo as unknown as { info(): Promise<ArtifactsRepoInfo> }).info();

/** A one-hour write pass to the person's own web: its git address, the pass, and when it ends. No binding, as on a
 *  server without Artifacts, is 501. */
export async function knowledgeAccess(knowledge: Artifacts | undefined, personId: string, wait = sleep) {
  if (!knowledge) throw new Refusal(NOT_SET_UP, 501);
  const repo = await repoOf(knowledge, personId, wait);
  const pass = await repo.createToken("write", PASS_SECONDS);
  return { remote: (await infoOf(repo)).remote, token: pass.plaintext, expiresAt: pass.expiresAt };
}

/** Deletes the person's web with their account; a person who never opened one has none to delete. */
export async function deleteKnowledge(knowledge: Artifacts | undefined, personId: string) {
  if (knowledge) await knowledge.delete(repoName(personId));
}
