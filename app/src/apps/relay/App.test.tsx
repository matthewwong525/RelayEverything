// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { createMemoryRouter, RouterProvider } from "react-router";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { routes } from "../../router";
import { today, when, where } from "./read";

const NOW = Date.now();
const DAY = 86_400_000;
const place = { lat: 43.6532, lon: -79.3832, accuracy: 12, name: "Queen St W", from: "phone" as const };
const note = (id: string, more: object = {}) =>
  ({ id, source: "typed", text: `Note ${id}`, recordedAt: NOW, device: "Android phone", audio: false, place: null, attachments: [], ...more });
const FIRST = { notes: [
  note("00000000-0000-4000-8000-000000000001", { source: "ring", audio: true, text: "", device: "iPad",
    place: { ...place, name: null, from: "history" } }),
  note("00000000-0000-4000-8000-000000000002", { place }),
], next: NOW, nextId: "00000000-0000-4000-8000-000000000002" };
const OLDER = { notes: [note("00000000-0000-4000-8000-000000000003", { recordedAt: NOW - 2 * DAY })], next: null, nextId: null };
const SUMMARY = { day: "2026-11-05", notes: 2, steps: 8432, sleepMinutes: 455,
  heartRate: { min: 52, max: 131, average: 74 }, workouts: { count: 1, minutes: 40 },
  weightKg: 71.2, hrvSdnn: 48, bloodPressure: [{ at: NOW, upper: 118, lower: 76 }], waterMl: 1500,
  places: [{ name: "Queen St W", lat: 43.65, lon: -79.38, from: NOW - 3_600_000, to: NOW }, { name: "Home", lat: 43.66, lon: -79.4, from: NOW, to: NOW }],
  events: [{ title: "Board meeting", start: NOW, end: NOW + 3_600_000, allDay: false, people: ["Sam Lee", "Ana"] },
    { title: "US Holiday", start: NOW, end: NOW + DAY, allDay: true, people: [] }] };
const EMPTY = { day: "2026-11-05", notes: 0, steps: 0, sleepMinutes: 0, heartRate: null, workouts: { count: 0, minutes: 0 }, places: [], events: [] };

const CHAT_1 = "c0000000-0000-4000-8000-000000000001";
const CHAT_2 = "c0000000-0000-4000-8000-000000000002";
const listed = (id: string, title: string, more: object = {}) =>
  ({ id, title, project: "relay-ring", app: "claude-code", startedAt: NOW, lastAt: NOW, messages: 4, savedByAi: false, ...more });
const CHATS = { chats: [listed(CHAT_1, "Stiffener plan", { savedByAi: true }), listed(CHAT_2, "Fix the webhook signature", { messages: 1 })], next: null, nextId: null };
const ONE_CHAT = { chat: CHATS.chats[0], next: 2, saves: [{ id: "e1", title: "Stiffener plan", text: "Use a 0.2 mm steel stiffener.", createdAt: NOW }],
  messages: [{ seq: 0, role: "you", text: "How thick should the stiffener be?", at: NOW }, { seq: 1, role: "step", text: "Read pcb/relay.kicad_pcb", at: NOW },
    { seq: 2, role: "ai", text: "0.2 mm is enough.", at: NOW }] };
const MORE = { ...ONE_CHAT, saves: [], next: null, messages: [{ seq: 3, role: "you", text: "Save the plan to Relay", at: NOW }] };

let answer: (route: string, init?: RequestInit) => Response | Promise<Response>;
const ordinary = (route: string, init?: RequestInit) => {
  if (route === "chats") return Response.json(CHATS);
  if (route === "chats?q=webhook") return Response.json({ ...CHATS, chats: [CHATS.chats[1]] });
  if (route === "chats?q=nothing") return Response.json({ chats: [], next: null, nextId: null });
  if (route === `chat?id=${CHAT_1}` && init?.method === "DELETE") return Response.json({ id: CHAT_1 });
  if (route === `chat?id=${CHAT_1}`) return Response.json(ONE_CHAT);
  if (route === `chat?id=${CHAT_1}&after=2`) return Response.json(MORE);
  if (route.startsWith("summary?")) return Response.json(SUMMARY);
  if (route === "timeline") return Response.json(FIRST);
  if (route === "webhooks") return Response.json({ webhooks: [] });
  if (route === `timeline?before=${NOW}&beforeId=00000000-0000-4000-8000-000000000002`) return Response.json(OLDER);
  throw new Error(`Unexpected route: ${route}`);
};
let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  answer = ordinary;
  fetchMock = vi.fn(async (path: string, init?: RequestInit) => {
    if (path === "/api/access/apps") return Response.json({ state: "current", role: "owner", revision: 1, apps: ["access", "relay"] });
    // The AI apps card has its own test: AiCard.test.tsx.
    if (path === "/apps/relay/api/ai-apps") return Response.json({ address: "https://relay-mcp.example.com/mcp", apps: [] });
    // The sign-in, devices and account have their own test: SignIn.test.tsx.
    if (path === "/apps/relay/api/account") return Response.json({ email: "ana@example.com" });
    if (path === "/apps/relay/api/devices") return Response.json({ devices: [] });
    // The photos card has its own test: Photos.test.tsx.
    if (path === "/apps/relay/api/photos") return Response.json({ count: 0 });
    // The Email card has its own test: Inbox.test.tsx.
    if (path === "/apps/relay/api/inbox") return Response.json({ email: { on: false, address: null, shared: null } });
    if (path.startsWith("/apps/relay/api/")) return answer(path.slice("/apps/relay/api/".length), init);
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
  expect(await screen.findByRole("heading", { level: 1, name: "Relay Everything" })).toBeTruthy();
  const tiles = await screen.findByRole("region", { name: "Today" });
  expect(within(tiles).getByText("8,432")).toBeTruthy();
  expect(within(tiles).getByText("7 h 35 min")).toBeTruthy();
  expect(screen.getByText(/Heart rate 52 to 131 bpm, 74 on average\. 1 workout, 40 min\. Weight 71\.2 kg\. Heart rate variability 48 ms\. Blood pressure 118\/76 mmHg\. Water 1,500 ml\./))
    .toBeTruthy();
  const calendar = screen.getByRole("region", { name: "Calendar" });
  expect(within(calendar).getByText("Board meeting")).toBeTruthy();
  expect(within(calendar).getByText(/Sam Lee, Ana/)).toBeTruthy();
  expect(within(calendar).getByText("All day")).toBeTruthy();
  const places = screen.getByRole("region", { name: "Places" });
  expect(within(places).getByText("Home")).toBeTruthy();
  expect(within(places).getByText(/ to /)).toBeTruthy();

  const notes = await screen.findByRole("region", { name: "Notes" });
  const ring = within(notes).getByLabelText("Ring note");
  expect(within(ring).getByText("No words, only the recording.")).toBeTruthy();
  expect(within(ring).getByText(/43\.6532, -79\.3832 · iPad/)).toBeTruthy();
  expect(within(ring).getByLabelText("The recording").getAttribute("src")).toBe("/apps/relay/api/audio?id=00000000-0000-4000-8000-000000000001");
  const typed = within(notes).getByLabelText("Typed note");
  expect(within(typed).getByText("Note 00000000-0000-4000-8000-000000000002")).toBeTruthy();
  expect(within(typed).getByText(/Queen St W · Android phone/)).toBeTruthy();
  expect(within(typed).queryByLabelText("The recording")).toBeNull();

  const { day, offset } = today();
  expect(reads()).toEqual(["/apps/relay/api/account", "/apps/relay/api/chats", "/apps/relay/api/webhooks", "/apps/relay/api/ai-apps",
    "/apps/relay/api/photos", "/apps/relay/api/inbox", "/apps/relay/api/devices", `/apps/relay/api/summary?day=${day}&offset=${offset}`, "/apps/relay/api/timeline"]);
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
  answer = route => route === "timeline" ? Response.json({ notes: [], next: null, nextId: null })
    : route === "chats" ? Response.json({ chats: [], next: null, nextId: null }) : Response.json(EMPTY);
  await open();
  expect(await screen.findByText("None yet")).toBeTruthy();
  expect(screen.getByText("No heart rate yet today. No workouts yet today.")).toBeTruthy();
  expect(screen.getByText(/No places yet today/)).toBeTruthy();
  expect(screen.getByText(/No events today/)).toBeTruthy();
  expect(await screen.findByText(/No notes yet/)).toBeTruthy();
  expect(await screen.findByText(/No chats yet/)).toBeTruthy();
  answer = route => route === "timeline" ? Response.json({ notes: [], next: null, nextId: null }) : Response.json({ ...EMPTY, workouts: { count: 3, minutes: 95 } });
});

it("says when the summary or the notes fail, and tries each again", async () => {
  let failing = true;
  answer = route => failing ? Promise.reject(new TypeError("offline")) : ordinary(route);
  await open();
  await screen.findByText("Today's summary could not be loaded.");
  expect(screen.getByText("Notes could not be loaded.")).toBeTruthy();
  failing = false;
  const other = { workouts: { count: 3, minutes: 95 }, hrvSdnn: undefined, hrvRmssd: 40, restingHeartRate: 55, bloodOxygen: { min: 94, average: 97 },
    cycleFlow: 2, mindfulMinutes: 10, events: [{ title: "", start: NOW, end: NOW + 60_000, allDay: false, people: [] }] };
  answer = route => route.startsWith("summary?") ? Response.json({ ...SUMMARY, ...other }) : ordinary(route);
  const [summary, notes] = screen.getAllByRole("button", { name: "Try again" });
  fireEvent.click(summary);
  expect(await screen.findByText(/3 workouts, 95 min\. Weight 71\.2 kg\. Resting heart rate 55 bpm\. Heart rate variability 40 ms\. Blood oxygen 94% lowest, 97% on average\..* Cycle flow medium\. 10 mindful min\./))
    .toBeTruthy();
  expect(screen.getByText("No title")).toBeTruthy();
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

it("lists saved chats, finds them by a word, and says when none match", async () => {
  await open();
  const chats = await screen.findByRole("region", { name: "Chats" });
  expect(await within(chats).findByRole("button", { name: "Stiffener plan" })).toBeTruthy();
  expect(within(chats).getByText("Saved by the AI")).toBeTruthy();
  expect(within(chats).getByText(/relay-ring · .* · 1 message$/)).toBeTruthy();
  const search = within(chats).getByLabelText("Search your chats");
  fireEvent.change(search, { target: { value: " webhook " } });
  fireEvent.submit(search);
  await waitFor(() => expect(within(chats).queryByText("Stiffener plan")).toBeNull());
  expect(within(chats).getByText("Fix the webhook signature")).toBeTruthy();
  fireEvent.change(search, { target: { value: "nothing" } });
  fireEvent.submit(search);
  expect(await within(chats).findByText("No chat holds those words.")).toBeTruthy();
});

it("opens a chat with the AI's summary above its messages, steps muted, and reads on", async () => {
  await open();
  const chats = await screen.findByRole("region", { name: "Chats" });
  fireEvent.click(await within(chats).findByRole("button", { name: "Stiffener plan" }));
  expect(await within(chats).findByRole("heading", { level: 3, name: "Stiffener plan" })).toBeTruthy();
  const summary = within(chats).getByLabelText("Written by the AI");
  expect(within(summary).getByText("Use a 0.2 mm steel stiffener.")).toBeTruthy();
  expect(within(chats).getByText("How thick should the stiffener be?")).toBeTruthy();
  expect(within(chats).getByText("Read pcb/relay.kicad_pcb").className).toContain("text-muted-foreground");
  expect(summary.compareDocumentPosition(within(chats).getByText("0.2 mm is enough.")) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  fireEvent.click(within(chats).getByRole("button", { name: "Show more messages" }));
  expect(await within(chats).findByText("Save the plan to Relay")).toBeTruthy();
  expect(within(chats).queryByRole("button", { name: "Show more messages" })).toBeNull();
  fireEvent.click(within(chats).getByRole("button", { name: "Back" }));
  expect(await within(chats).findByRole("button", { name: "Fix the webhook signature" })).toBeTruthy();
});

it("loads older chats and more messages, and says when a part could not load", async () => {
  let failing = true;
  const older = `chats?q=&before=${NOW}&beforeId=${CHAT_2}`;
  answer = (route, init) => {
    if ((route === older || route.endsWith("&after=2") || route === `chat?id=${CHAT_2}`) && failing) return new Response("down", { status: 502 });
    if (route === `chat?id=${CHAT_2}`) return Response.json({ ...MORE, chat: CHATS.chats[1] });
    if (route === "chats") return Response.json({ ...CHATS, next: NOW, nextId: CHAT_2 });
    if (route === older) return Response.json({ chats: [listed("c0000000-0000-4000-8000-000000000003", "Battery choice")], next: null, nextId: null });
    return ordinary(route, init);
  };
  await open();
  const chats = await screen.findByRole("region", { name: "Chats" });
  fireEvent.click(await within(chats).findByRole("button", { name: "Show older chats" }));
  expect((await within(chats).findByRole("alert")).textContent).toBe("Older chats could not be loaded.");
  failing = false;
  fireEvent.click(within(chats).getByRole("button", { name: "Show older chats" }));
  expect(await within(chats).findByRole("button", { name: "Battery choice" })).toBeTruthy();
  expect(within(chats).queryByRole("alert")).toBeNull();
  failing = true;
  fireEvent.click(within(chats).getByRole("button", { name: "Stiffener plan" }));
  fireEvent.click(await within(chats).findByRole("button", { name: "Show more messages" }));
  expect((await within(chats).findByRole("alert")).textContent).toBe("More messages could not be loaded.");
  failing = false;
  fireEvent.click(within(chats).getByRole("button", { name: "Show more messages" }));
  expect(await within(chats).findByText("Save the plan to Relay")).toBeTruthy();
  expect(within(chats).queryByRole("alert")).toBeNull();
  // A chat that can't be read offers to try again.
  failing = true;
  fireEvent.click(within(chats).getByRole("button", { name: "Back" }));
  fireEvent.click(await within(chats).findByRole("button", { name: "Fix the webhook signature" }));
  expect((await within(chats).findByRole("alert")).textContent).toContain("The chat could not be loaded.");
  failing = false;
  fireEvent.click(within(chats).getByRole("button", { name: "Try again" }));
  expect(await within(chats).findByRole("heading", { level: 3, name: "Fix the webhook signature" })).toBeTruthy();
});

it("deletes a chat after a confirm that says it can't be undone, and reads the list again", async () => {
  let failing = true;
  answer = (route, init) => init?.method === "DELETE" && failing ? new Response("down", { status: 502 }) : ordinary(route, init);
  await open();
  const chats = await screen.findByRole("region", { name: "Chats" });
  fireEvent.click(await within(chats).findByRole("button", { name: "Stiffener plan" }));
  fireEvent.click(await within(chats).findByRole("button", { name: "Delete" }));
  const confirm = await screen.findByRole("alertdialog");
  expect(within(confirm).getByText(/You can't undo it\./)).toBeTruthy();
  fireEvent.click(within(confirm).getByRole("button", { name: "Delete" }));
  expect((await within(chats).findByRole("alert")).textContent).toBe("The chat could not be deleted. Try again.");
  failing = false;
  fireEvent.click(within(chats).getByRole("button", { name: "Delete" }));
  fireEvent.click(within(await screen.findByRole("alertdialog")).getByRole("button", { name: "Delete" }));
  expect(await within(chats).findByLabelText("Search your chats")).toBeTruthy();
  const deletes = fetchMock.mock.calls.filter(([, init]) => init?.method === "DELETE").map(([path]) => path);
  expect(deletes).toEqual([`/apps/relay/api/chat?id=${CHAT_1}`, `/apps/relay/api/chat?id=${CHAT_1}`]);
  expect(reads().filter(path => path === "/apps/relay/api/chats")).toHaveLength(2);
});

it("tells how to connect Claude Code, that its key only adds chats, and that you can run your own server", async () => {
  await open();
  fireEvent.click(await screen.findByRole("button", { name: "Connect Claude Code" }));
  const dialog = await screen.findByRole("dialog", { name: "Connect Claude Code" });
  expect(within(dialog).getByText(/can only add chats/)).toBeTruthy();
  expect(within(dialog).getByText(/tap/).textContent).toContain("Add a device and choose Claude Code");
  expect(within(dialog).getByText("/plugin marketplace add matthewwong525/RelayEverything")).toBeTruthy();
  expect(within(dialog).getByText("/plugin install relay@relay")).toBeTruthy();
  expect(within(dialog).getByText(/run your own Relay Everything server/)).toBeTruthy();
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
