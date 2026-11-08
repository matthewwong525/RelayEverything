// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { Inbox } from "./Inbox";

// Made-up addresses on a reserved example domain: never a real person's notes address.
const ON = { on: true, address: "notes-k7q2m9xwab@in.example.com", shared: "notes@in.example.com" };
const NEW = { ...ON, address: "notes-zz2233ffgg@in.example.com" };

let read: () => Response;
let made: () => Response;
let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  read = () => Response.json({ email: ON });
  made = () => Response.json({ email: NEW });
  fetchMock = vi.fn(async (path: string, init?: RequestInit) => {
    if (path === "/apps/relay/api/inbox") return read();
    if (path === "/apps/relay/api/inbox/address" && init?.method === "POST") return made();
    throw new Error(`Unexpected request: ${path}`);
  });
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const open = async () => { await act(async () => { render(<Inbox />); }); };
const address = () => screen.getByLabelText("Your notes address");

it("shows the notes address with Copy, the shared address and the warning", async () => {
  await open();
  const card = screen.getByRole("region", { name: "Email" });
  expect(address()).toHaveProperty("value", ON.address);
  expect(within(card).getByRole("button", { name: "Copy" })).toBeTruthy();
  expect(within(card).getByText("Anything sent here becomes a note.")).toBeTruthy();
  expect(within(card).getByText(`You can also write to ${ON.shared} from your sign-in email.`)).toBeTruthy();
  expect(within(card).getByText("Email is not sealed on the way. Don't send health or location details this way.")).toBeTruthy();
});

it("makes a new address only after the confirm, and shows it", async () => {
  await open();
  fireEvent.click(screen.getByRole("button", { name: "New address" }));
  fireEvent.click(within(await screen.findByRole("alertdialog")).getByRole("button", { name: "Cancel" }));
  expect(fetchMock).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole("button", { name: "New address" }));
  await act(async () => { fireEvent.click(within(await screen.findByRole("alertdialog")).getByRole("button", { name: "New address" })); });
  expect(fetchMock.mock.calls.map(([path]) => path)).toEqual(["/apps/relay/api/inbox", "/apps/relay/api/inbox/address"]);
  expect(address()).toHaveProperty("value", NEW.address);
});

it("says when a new address could not be made, and keeps the old one", async () => {
  made = () => Response.json({ error: { code: "unavailable", message: "No." } }, { status: 503 });
  await open();
  fireEvent.click(screen.getByRole("button", { name: "New address" }));
  await act(async () => { fireEvent.click(within(await screen.findByRole("alertdialog")).getByRole("button", { name: "New address" })); });
  expect(screen.getByRole("alert").textContent).toBe("A new address could not be made. Try again.");
  expect(address()).toHaveProperty("value", ON.address);
});

it("shows no card when the server takes no email, or has no spaces", async () => {
  read = () => Response.json({ email: { on: false, address: null, shared: null } });
  await open();
  expect(screen.queryByRole("region", { name: "Email" })).toBeNull();
  cleanup();
  read = () => Response.json({ error: { code: "unavailable", message: "No spaces." } }, { status: 503 });
  await open();
  expect(screen.queryByRole("region", { name: "Email" })).toBeNull();
});

it("says when the address could not be read, and reads it again", async () => {
  read = () => Response.json({ error: { code: "internal" } }, { status: 500 });
  await open();
  expect(screen.getByRole("alert").textContent).toMatch(/^Your notes address could not be loaded\./);
  read = () => Response.json({ email: ON });
  await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Try again" })); });
  expect(address()).toHaveProperty("value", ON.address);
});
