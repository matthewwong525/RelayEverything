// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { Photos } from "./Photos";

type Call = { route: string; input: Record<string, unknown> | null };
let calls: Call[];
let answer: (call: Call) => Response | Promise<Response>;
let count: number;
const ordinary = (call: Call) => {
  if (call.route === "photos" && !call.input) return Response.json({ count });
  if (call.route === "photos/delete") { const deleted = count; count = 0; return Response.json({ deleted }); }
  throw new Error(`Unexpected route: ${call.route}`);
};
beforeEach(() => {
  calls = [];
  count = 312;
  answer = ordinary;
  vi.stubGlobal("fetch", vi.fn(async (path: string, init?: RequestInit) => {
    const call = { route: path.slice("/apps/relay/api/".length), input: init?.body ? JSON.parse(String(init.body)) : null };
    calls.push(call);
    return answer(call);
  }));
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const open = async () => { await act(async () => { render(<Photos />); }); };
const card = () => within(screen.getByRole("region", { name: "Photos" }));
const press = async (name: string, where: Pick<typeof screen, "getByRole"> = screen) => {
  await act(async () => { fireEvent.click(where.getByRole("button", { name })); });
};

it("shows the card while the count loads", async () => {
  answer = () => new Promise(() => {});
  await open();
  expect(card().getByText("Loading photos…")).toBeTruthy();
});

it("says when the count could not load, and tries again", async () => {
  answer = () => Promise.reject(new TypeError("offline"));
  await open();
  expect(card().getByRole("alert").textContent).toContain("Photos could not be loaded.");
  answer = ordinary;
  await press("Try again", card());
  expect(card().getByText("312 photos sent from your phones.")).toBeTruthy();
});

it("counts the photos in words, and says the AI can see them", async () => {
  count = 1234;
  await open();
  expect(card().getByText("1,234 photos sent from your phones.")).toBeTruthy();
  expect(card().getByText("Your AI can see them. Turn photos off in the phone app's Settings.")).toBeTruthy();
  cleanup();
  count = 1;
  await open();
  expect(card().getByText("1 photo sent from your phones.")).toBeTruthy();
  cleanup();
  count = 0;
  await open();
  expect(card().getByText("No photos yet")).toBeTruthy();
  expect(card().queryByRole("button", { name: "Delete all photos" })).toBeNull();
});

it("deletes all photos after a confirm that says it can't be undone, and keeps the count when that fails", async () => {
  await open();
  await press("Delete all photos", card());
  const confirm = within(screen.getByRole("alertdialog", { name: "Delete all photos?" }));
  expect(confirm.getByText(/Ring recordings, notes, health and places stay\. You can't undo it\./)).toBeTruthy();
  await press("Cancel", confirm);
  expect(calls.filter(call => call.input)).toEqual([]);

  answer = call => call.input ? new Response("down", { status: 502 }) : ordinary(call);
  await press("Delete all photos", card());
  await press("Delete all photos", within(screen.getByRole("alertdialog")));
  expect(card().getByRole("alert").textContent).toBe("The photos could not be deleted. Try again.");
  expect(card().getByText("312 photos sent from your phones.")).toBeTruthy();

  answer = ordinary;
  await press("Delete all photos", card());
  await press("Delete all photos", within(screen.getByRole("alertdialog")));
  expect(screen.queryByRole("alertdialog")).toBeNull();
  expect(card().getByText("No photos yet")).toBeTruthy();
  expect(card().queryByRole("alert")).toBeNull();
  expect(calls.filter(call => call.input)).toEqual(Array(2).fill({ route: "photos/delete", input: { confirm: "delete" } }));
});
