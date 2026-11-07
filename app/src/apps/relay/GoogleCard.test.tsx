// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { GoogleCard } from "./GoogleCard";

const ana = { email: "ana@gmail.example", scopes: ["https://www.googleapis.com/auth/gmail.modify"], connectedAt: Date.UTC(2026, 10, 4, 15) };

let status: () => Response | Promise<Response>;
let disconnect: () => Response;
let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  status = () => Response.json({ available: true, connected: null });
  disconnect = () => Response.json({ disconnected: true });
  fetchMock = vi.fn(async (path: string, init?: RequestInit) => {
    if (path === "/apps/relay/api/google") return status();
    if (path === "/apps/relay/api/google-disconnect" && init?.method === "POST") return disconnect();
    throw new Error(`Unexpected request: ${path}`);
  });
  vi.stubGlobal("fetch", fetchMock);
  window.history.replaceState(null, "", "/apps/relay/");
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const open = async () => { await act(async () => { render(<GoogleCard />); }); };

it("offers Connect Google, a link to the server's own connect page, when nothing is connected", async () => {
  await open();
  const link = await screen.findByRole("link", { name: "Connect Google" });
  expect(link.getAttribute("href")).toBe("/apps/relay/google/connect");
  expect(screen.getByText(/Relay Everything keeps none of them/)).toBeTruthy();
  expect(screen.queryByRole("status")).toBeNull();
});

it("shows the connected address with when, and no Connect Google", async () => {
  status = () => Response.json({ available: true, connected: ana });
  await open();
  expect(await screen.findByText("ana@gmail.example")).toBeTruthy();
  expect(screen.getByText("Connected")).toBeTruthy();
  expect(screen.getByText(/connected Nov 4/)).toBeTruthy();
  expect(screen.queryByRole("link", { name: "Connect Google" })).toBeNull();
});

it("says a permission was left out or the connect failed, once, and takes the word off the address", async () => {
  window.history.replaceState(null, "", "/apps/relay/?google=missing");
  await open();
  expect((await screen.findByRole("status")).textContent).toBe("Allow Gmail, Calendar, Drive and Contacts to connect.");
  expect(window.location.search).toBe("");
  expect(screen.getByRole("link", { name: "Connect Google" })).toBeTruthy();
  cleanup();
  window.history.replaceState(null, "", "/apps/relay/?google=failed");
  await open();
  expect((await screen.findByRole("status")).textContent).toBe("Google could not be connected. Try again.");
  cleanup();
  window.history.replaceState(null, "", "/apps/relay/?google=connected");
  await open();
  await screen.findByRole("link", { name: "Connect Google" });
  expect(screen.queryByRole("status")).toBeNull();
  expect(window.location.search).toBe("");
});

it("disconnects only after a confirm, then reads the card again", async () => {
  status = () => Response.json({ available: true, connected: ana });
  await open();
  fireEvent.click(await screen.findByRole("button", { name: "Disconnect" }));
  const dialog = await screen.findByRole("alertdialog", { name: "Disconnect Google?" });
  fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
  expect(fetchMock.mock.calls.some(([path]) => path.endsWith("disconnect"))).toBe(false);

  fireEvent.click(screen.getByRole("button", { name: "Disconnect" }));
  status = () => Response.json({ available: true, connected: null });
  await act(async () => { fireEvent.click(within(await screen.findByRole("alertdialog")).getByRole("button", { name: "Disconnect" })); });
  expect(fetchMock.mock.calls.some(([path, init]) => path.endsWith("google-disconnect") && init.method === "POST")).toBe(true);
  expect(await screen.findByRole("link", { name: "Connect Google" })).toBeTruthy();
});

it("says when a disconnect fails, and stays connected", async () => {
  status = () => Response.json({ available: true, connected: ana });
  disconnect = () => new Response("down", { status: 502 });
  await open();
  fireEvent.click(await screen.findByRole("button", { name: "Disconnect" }));
  await act(async () => { fireEvent.click(within(await screen.findByRole("alertdialog")).getByRole("button", { name: "Disconnect" })); });
  expect((await screen.findByRole("alert")).textContent).toBe("Google could not be disconnected. Try again.");
  expect(screen.getByText("ana@gmail.example")).toBeTruthy();
});

it("hides the card on a server with no Google, and offers a retry when the read fails", async () => {
  status = () => Response.json({ available: false, connected: null });
  await open();
  await act(async () => {});
  expect(screen.queryByRole("region", { name: "Google" })).toBeNull();
  expect(screen.queryByText("Google")).toBeNull();
  cleanup();

  status = () => Promise.reject(new TypeError("offline"));
  await open();
  expect((await screen.findByRole("alert")).textContent).toContain("Google could not be loaded.");
  status = () => Response.json({ available: true, connected: null });
  fireEvent.click(screen.getByRole("button", { name: "Try again" }));
  expect(await screen.findByRole("link", { name: "Connect Google" })).toBeTruthy();
});
