// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { createMemoryRouter, RouterProvider } from "react-router";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { routes } from "../../router";
import { today, when, where } from "./read";

const NOW = Date.now();
const DAY = 86_400_000;
const place = { lat: 43.6532, lon: -79.3832, accuracy: 12, name: "Queen St W", from: "phone" as const };
const note = (id: string, more: object = {}) =>
  ({ id, source: "typed", text: `Note ${id}`, recordedAt: NOW, device: "Android phone", audio: false, place: null, ...more });
const FIRST = { notes: [
  note("00000000-0000-4000-8000-000000000001", { source: "ring", audio: true, text: "", device: "Pebble app",
    place: { ...place, name: null, from: "history" } }),
  note("00000000-0000-4000-8000-000000000002", { place }),
], next: NOW, nextId: "00000000-0000-4000-8000-000000000002" };
const OLDER = { notes: [note("00000000-0000-4000-8000-000000000003", { recordedAt: NOW - 2 * DAY })], next: null, nextId: null };
const SUMMARY = { day: "2026-11-05", notes: 2, steps: 8432, sleepMinutes: 455,
  heartRate: { min: 52, max: 131, average: 74 }, workouts: { count: 1, minutes: 40 },
  places: [{ name: "Queen St W", lat: 43.65, lon: -79.38, from: NOW - 3_600_000, to: NOW }, { name: "Home", lat: 43.66, lon: -79.4, from: NOW, to: NOW }] };
const EMPTY = { day: "2026-11-05", notes: 0, steps: 0, sleepMinutes: 0, heartRate: null, workouts: { count: 0, minutes: 0 }, places: [] };

let answer: (route: string) => Response | Promise<Response>;
const ordinary = (route: string) => {
  if (route.startsWith("summary?")) return Response.json(SUMMARY);
  if (route === "timeline") return Response.json(FIRST);
  if (route === `timeline?before=${NOW}&beforeId=00000000-0000-4000-8000-000000000002`) return Response.json(OLDER);
  throw new Error(`Unexpected route: ${route}`);
};
let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  answer = ordinary;
  fetchMock = vi.fn(async (path: string) => {
    if (path === "/api/access/apps") return Response.json({ state: "current", role: "owner", revision: 1, apps: ["access", "relay"] });
    // The AI apps card has its own test: AiCard.test.tsx.
    if (path === "/apps/relay/api/ai-apps") return Response.json({ address: "https://relay-mcp.example.com/mcp", apps: [] });
    if (path.startsWith("/apps/relay/api/")) return answer(path.slice("/apps/relay/api/".length));
    throw new Error(`Unexpected request: ${path}`);
  });
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const open = async () => {
  const router = createMemoryRouter(routes, { initialEntries: ["/apps/relay/"] });
  await act(async () => { render(<RouterProvider router={router} />); });
};
const reads = () => fetchMock.mock.calls.map(([path]) => path).filter(path => path.startsWith("/apps/relay/api/"));

it("shows today's summary, every note with its place and recording, and the places", async () => {
  await open();
  expect(await screen.findByRole("heading", { level: 1, name: "Relay" })).toBeTruthy();
  const tiles = await screen.findByRole("region", { name: "Today" });
  expect(within(tiles).getByText("8,432")).toBeTruthy();
  expect(within(tiles).getByText("7 h 35 min")).toBeTruthy();
  expect(screen.getByText(/Heart rate 52 to 131 bpm, 74 on average\. 1 workout, 40 min\./)).toBeTruthy();
  const places = screen.getByRole("region", { name: "Places" });
  expect(within(places).getByText("Home")).toBeTruthy();
  expect(within(places).getByText(/ to /)).toBeTruthy();

  const notes = await screen.findByRole("region", { name: "Notes" });
  const ring = within(notes).getByLabelText("Ring note");
  expect(within(ring).getByText("No words, only the recording.")).toBeTruthy();
  expect(within(ring).getByText(/43\.6532, -79\.3832 · Pebble app/)).toBeTruthy();
  expect(within(ring).getByLabelText("The recording").getAttribute("src")).toBe("/apps/relay/api/audio?id=00000000-0000-4000-8000-000000000001");
  const typed = within(notes).getByLabelText("Typed note");
  expect(within(typed).getByText("Note 00000000-0000-4000-8000-000000000002")).toBeTruthy();
  expect(within(typed).getByText(/Queen St W · Android phone/)).toBeTruthy();
  expect(within(typed).queryByLabelText("The recording")).toBeNull();

  const { day, offset } = today();
  expect(reads()).toEqual(["/apps/relay/api/ai-apps", `/apps/relay/api/summary?day=${day}&offset=${offset}`, "/apps/relay/api/timeline"]);
  expect(await screen.findByText("No AI app connected yet.")).toBeTruthy();
});

it("loads older notes until there are none, and says when a page fails", async () => {
  let failing = true;
  answer = route => route.startsWith("timeline?") && failing ? new Response("down", { status: 502 }) : ordinary(route);
  await open();
  const more = await screen.findByRole("button", { name: "Show older notes" });
  fireEvent.click(more);
  expect((await screen.findByRole("alert")).textContent).toBe("Older notes could not be loaded.");
  failing = false;
  fireEvent.click(more);
  expect(await screen.findByText("Note 00000000-0000-4000-8000-000000000003")).toBeTruthy();
  expect(screen.queryByRole("alert")).toBeNull();
  expect(screen.queryByRole("button", { name: "Show older notes" })).toBeNull();
});

it("shows an empty day and an empty timeline in words", async () => {
  answer = route => route === "timeline" ? Response.json({ notes: [], next: null, nextId: null }) : Response.json(EMPTY);
  await open();
  expect(await screen.findByText("None yet")).toBeTruthy();
  expect(screen.getByText("No heart rate yet today. No workouts yet today.")).toBeTruthy();
  expect(screen.getByText(/No places yet today/)).toBeTruthy();
  expect(await screen.findByText(/No notes yet/)).toBeTruthy();
  answer = route => route === "timeline" ? Response.json({ notes: [], next: null, nextId: null }) : Response.json({ ...EMPTY, workouts: { count: 3, minutes: 95 } });
});

it("says when the summary or the notes fail, and tries each again", async () => {
  let failing = true;
  answer = route => failing ? Promise.reject(new TypeError("offline")) : ordinary(route);
  await open();
  await screen.findByText("Today's summary could not be loaded.");
  expect(screen.getByText("Notes could not be loaded.")).toBeTruthy();
  failing = false;
  answer = route => route.startsWith("summary?") ? Response.json({ ...SUMMARY, workouts: { count: 3, minutes: 95 } }) : ordinary(route);
  const [summary, notes] = screen.getAllByRole("button", { name: "Try again" });
  fireEvent.click(summary);
  expect(await screen.findByText(/3 workouts, 95 min\./)).toBeTruthy();
  fireEvent.click(notes);
  expect(await screen.findByLabelText("Ring note")).toBeTruthy();
});

it("drops an answer that comes after the page closed", async () => {
  let late = (_answer: Response) => {};
  answer = () => new Promise(resolve => { late = resolve; });
  await open();
  expect(await screen.findByText("Loading today")).toBeTruthy();
  cleanup();
  await act(async () => { late(Response.json(FIRST)); });
});

it("tells how to set up a phone and the Pebble app", async () => {
  await open();
  fireEvent.click(await screen.findByRole("button", { name: "Set up a phone" }));
  const phone = await screen.findByRole("dialog", { name: "Set up a phone" });
  expect(within(phone).getByText(/relay-device-key\.mjs create --name "Android phone"/)).toBeTruthy();
  expect(within(phone).getByRole("link", { name: "Relay's releases" }).getAttribute("href")).toBe("https://github.com/matthewwong525/RelayEverything/releases/latest");
  expect(within(phone).getByLabelText("The message to copy")).toHaveProperty("value", window.location.origin);
  // The app opens on its Connect screen, so the steps name that screen's button.
  expect(within(phone).getByText("Scan the QR code").tagName).toBe("B");
  fireEvent.keyDown(phone, { key: "Escape" });
  fireEvent.click(await screen.findByRole("button", { name: "Pebble webhook" }));
  const pebble = await screen.findByRole("dialog", { name: "Pebble webhook" });
  expect(within(pebble).getByLabelText("The message to copy")).toHaveProperty("value", `${window.location.origin}/apps/relay/api/pebble`);
  expect(within(pebble).getByText("CF-Access-Client-Secret")).toBeTruthy();
});

it("writes times, places and the day as the page shows them", () => {
  const morning = new Date(2026, 10, 5, 9, 5);
  expect(when(morning.getTime(), morning.getTime())).not.toContain(",");
  expect(when(morning.getTime(), morning.getTime() + 2 * DAY)).toContain(",");
  expect(where(null)).toBeNull();
  expect(where(place)).toBe("Queen St W");
  expect(today(morning).day).toBe("2026-11-05");
  expect(today(morning).offset).toBe(-morning.getTimezoneOffset());
});
