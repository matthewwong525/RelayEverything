// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { AiCard } from "./AiCard";

const ADDRESS = "https://relay-mcp.example.com/mcp";
const claude = { id: "grant-claude", name: "Claude", connectedAt: Date.UTC(2026, 10, 4, 15) };
const chatgpt = { id: "grant-chatgpt", name: "ChatGPT", connectedAt: Date.now() };

let apps: (typeof claude)[];
let list: () => Response | Promise<Response>;
let disconnect: () => Response;
let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  apps = [chatgpt, claude];
  list = () => Response.json({ address: ADDRESS, apps });
  disconnect = () => Response.json({ id: "grant-claude" });
  fetchMock = vi.fn(async (path: string, init?: RequestInit) => {
    if (path === "/apps/relay/api/ai-apps") return list();
    if (path === "/apps/relay/api/ai-apps-disconnect" && init?.method === "POST") return disconnect();
    throw new Error(`Unexpected request: ${path}`);
  });
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const open = async () => { await act(async () => { render(<AiCard />); }); };
const row = (name: string) => screen.getByText(name).closest("li") as HTMLElement;

it("shows the address to add and each connected app with when it connected", async () => {
  await open();
  expect(await screen.findByLabelText("The connector's address")).toHaveProperty("value", ADDRESS);
  expect(screen.getByRole("button", { name: "Copy" })).toBeTruthy();
  expect(screen.getByText("2 connected")).toBeTruthy();
  expect(within(row("Claude")).getByText(/Connected Nov 4/)).toBeTruthy();
  expect(within(row("ChatGPT")).getByText(/^Connected/)).toBeTruthy();
  expect(screen.getByText(/same sign-in opens the web API/)).toBeTruthy();
  expect(screen.getByRole("link", { name: "Connect a service" }).getAttribute("href")).toBe("https://relayeverything.com/api/connect-a-service/");
});

it("disconnects an app only after a confirm, then reads the list again", async () => {
  await open();
  fireEvent.click(within(await screen.findByText("Claude").then(() => row("Claude"))).getByRole("button", { name: "Disconnect" }));
  const dialog = await screen.findByRole("alertdialog", { name: "Disconnect Claude?" });
  fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
  expect(fetchMock.mock.calls.some(([path]) => path.endsWith("disconnect"))).toBe(false);

  fireEvent.click(within(row("Claude")).getByRole("button", { name: "Disconnect" }));
  apps = [chatgpt];
  await act(async () => { fireEvent.click(within(await screen.findByRole("alertdialog")).getByRole("button", { name: "Disconnect" })); });
  const sent = fetchMock.mock.calls.find(([path]) => path.endsWith("disconnect"))!;
  expect(JSON.parse(sent[1].body)).toEqual({ id: "grant-claude" });
  expect(await screen.findByText("1 connected")).toBeTruthy();
  expect(screen.queryByText("Claude")).toBeNull();
});

it("says when a disconnect fails, and keeps the app listed", async () => {
  disconnect = () => new Response("down", { status: 502 });
  await open();
  fireEvent.click(within(await screen.findByText("Claude").then(() => row("Claude"))).getByRole("button", { name: "Disconnect" }));
  await act(async () => { fireEvent.click(within(await screen.findByRole("alertdialog")).getByRole("button", { name: "Disconnect" })); });
  expect((await screen.findByRole("alert")).textContent).toBe("Claude could not be disconnected. Try again.");
  expect(screen.getByText("Claude")).toBeTruthy();
  fireEvent.click(within(row("Claude")).getByRole("button", { name: "Disconnect" }));
  expect(screen.queryByRole("alert")).toBeNull();
});

it("shows no app connected yet, a connector not set up, and a failed read with a retry", async () => {
  apps = [];
  await open();
  expect(await screen.findByText("No AI app connected yet.")).toBeTruthy();
  expect(screen.getByText("0 connected")).toBeTruthy();
  cleanup();

  list = () => Response.json({ error: { code: "unavailable" } }, { status: 503 });
  await open();
  expect(await screen.findByText("The AI connector is not set up here yet.")).toBeTruthy();
  expect(screen.queryByRole("button", { name: "Try again" })).toBeNull();
  cleanup();

  list = () => Promise.reject(new TypeError("offline"));
  await open();
  expect((await screen.findByRole("alert")).textContent).toContain("The AI apps could not be loaded.");
  list = () => Response.json({ address: ADDRESS, apps: [claude] });
  fireEvent.click(screen.getByRole("button", { name: "Try again" }));
  expect(await screen.findByText("Claude")).toBeTruthy();
});
