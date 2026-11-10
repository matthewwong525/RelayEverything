import { expect, it, vi } from "vitest";
import { staticPage } from "./static-page";

const assets = { fetch: vi.fn(async (request: Request) => new Response(new URL(request.url).pathname + new URL(request.url).search)) };
const answer = async (path: string) => {
  const response = staticPage(new Request(`https://relay.example.com${path}`), assets as unknown as Fetcher, ["relay"]);
  return response && (await response).text();
};

it("serves a static app's files as they are, and its index.html for an address that names no file", async () => {
  expect(await answer("/apps/relay/")).toBe("/apps/relay/");
  expect(await answer("/apps/relay/?next=%2Fapps%2Frelay%2Fsign-in%2Fconnect")).toBe("/apps/relay/?next=%2Fapps%2Frelay%2Fsign-in%2Fconnect");
  expect(await answer("/apps/relay/canvaskit/canvaskit.wasm")).toBe("/apps/relay/canvaskit/canvaskit.wasm");
  expect(await answer("/apps/relay/notes/today?signIn=failed")).toBe("/apps/relay/?signIn=failed");
});

it("leaves every other address alone", async () => {
  for (const path of ["/", "/apps/hello/", "/apps/relay", "/apps/relays/x"]) expect(await answer(path), path).toBeNull();
});
