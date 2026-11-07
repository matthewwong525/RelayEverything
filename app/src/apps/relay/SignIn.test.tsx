// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { createMemoryRouter, RouterProvider } from "react-router";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { routes } from "../../router";

// The sign-in, the devices and the account, with a stand-in server that keeps one person signed in or out.
const NOW = Date.now();
const EMAIL = "ana@example.com";
const KEY = `rek_${"a".repeat(43)}`;
const QR = JSON.stringify({ relay: 1, server: "https://relay.example.com", key: KEY });
const PHONE = { id: "d1", name: "Ana's phone", reaches: "phone", createdAt: NOW, revokedAt: null };
const OLD = { id: "d2", name: "Old laptop", reaches: "chats", createdAt: NOW, revokedAt: NOW };

type Handler = (body: Record<string, unknown>) => Response;
let signedIn: boolean;
let methods: () => Response;
let devices: () => Response;
let account: () => Response;
let posts: Record<string, Handler>;
let fetchMock: ReturnType<typeof vi.fn>;
const assign = vi.fn();

const refused = (status: number, message: string) => Response.json({ error: { code: "forbidden", message } }, { status });
const EMPTY_DAY = { day: "2026-11-05", notes: 0, steps: 0, sleepMinutes: 0, heartRate: null, workouts: { count: 0, minutes: 0 }, places: [] };

function api(route: string): Response {
  if (!signedIn) return refused(401, "Sign in to Relay Everything.");
  if (route === "account") return account();
  if (route === "devices") return devices();
  if (route.startsWith("summary?")) return Response.json(EMPTY_DAY);
  if (route === "timeline" || route === "chats") return Response.json({ notes: [], chats: [], next: null, nextId: null });
  if (route === "webhooks") return Response.json({ webhooks: [] });
  if (route === "photos") return Response.json({ count: 0 });
  if (route === "ai-apps") return Response.json({ address: "https://relay-mcp.example.com/mcp", apps: [] });
  throw new Error(`Unexpected route: ${route}`);
}

beforeEach(() => {
  signedIn = false;
  methods = () => Response.json({ email: true, apple: true, google: true, signUp: true });
  devices = () => Response.json({ devices: [PHONE, OLD] });
  account = () => Response.json({ email: EMAIL });
  posts = {
    "/apps/relay/sign-in/email": () => Response.json({ sent: true }),
    "/apps/relay/sign-in/code": ({ code }) => code === "123456" ? (signedIn = true, Response.json({ ok: true })) : refused(401, "That code is wrong."),
    "/apps/relay/sign-in/out": () => (signedIn = false, Response.json({ ok: true })),
    "/apps/relay/api/devices": ({ name, reaches }) => Response.json({ id: "d3", name, reaches, key: KEY, qr: QR, pebbleSecret: reaches === "phone" ? "pebble-secret" : null }),
    "/apps/relay/api/devices/off": ({ id }) => Response.json({ id, revokedAt: NOW }),
    "/apps/relay/api/account-delete": () => (signedIn = false, Response.json({ deleted: true })),
  };
  fetchMock = vi.fn(async (path: string, init?: RequestInit) => {
    if (path === "/api/access/apps") return Response.json({ state: "current", role: "owner", revision: 1, apps: ["access", "relay"] });
    if (path === "/apps/relay/sign-in/methods") return methods();
    if (init?.method === "POST") return posts[path](JSON.parse(String(init.body)));
    if (path.startsWith("/apps/relay/api/")) return api(path.slice("/apps/relay/api/".length));
    throw new Error(`Unexpected request: ${path}`);
  });
  vi.stubGlobal("fetch", fetchMock);
  assign.mockClear();
  vi.spyOn(window, "location", "get").mockReturnValue({ ...window.location, origin: "https://relay.example.com", assign });
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

const open = async (entry = "/apps/relay/") => {
  const { search } = new URL(entry, "https://relay.example.com");
  vi.spyOn(window, "location", "get").mockReturnValue({ ...window.location, origin: "https://relay.example.com", search, assign });
  const router = createMemoryRouter(routes, { initialEntries: [entry] });
  await act(async () => { render(<RouterProvider router={router} />); });
};
const sent = (path: string) => fetchMock.mock.calls.filter(([called, init]) => called === path && init?.method === "POST")
  .map(([, init]) => JSON.parse(String(init.body)));

const signInWithCode = async (code = "123456") => {
  fireEvent.change(await screen.findByLabelText("Email"), { target: { value: ` ${EMAIL} ` } });
  fireEvent.click(screen.getByRole("button", { name: "Email me a code" }));
  fireEvent.change(await screen.findByLabelText("Code"), { target: { value: `${code}x` } });
  await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Sign in" })); });
};

it("shows the sign-in when nobody is signed in, then the page after an email code", async () => {
  await open();
  expect(await screen.findByText("Sign in or make an account")).toBeTruthy();
  expect(screen.getByRole("link", { name: "Continue with Apple" }).getAttribute("href")).toBe("/apps/relay/sign-in/apple");
  expect(screen.getByRole("link", { name: "Continue with Google" }).getAttribute("href")).toBe("/apps/relay/sign-in/google");
  expect(screen.getByText("New here? The same steps make your account.")).toBeTruthy();
  expect(screen.getByRole("button", { name: "Email me a code" }).hasAttribute("disabled")).toBe(true);
  await signInWithCode("654321");
  expect(await screen.findByRole("alert")).toHaveProperty("textContent", "That code is wrong.");
  fireEvent.click(screen.getByRole("button", { name: "Use another email" }));
  await signInWithCode();
  expect(await screen.findByText(`Signed in as ${EMAIL}`)).toBeTruthy();
  expect(sent("/apps/relay/sign-in/email")).toEqual([{ email: EMAIL }, { email: EMAIL }]);
  expect(sent("/apps/relay/sign-in/code")).toEqual([{ email: EMAIL, code: "654321" }, { email: EMAIL, code: "123456" }]);
  expect(assign).not.toHaveBeenCalled();
});

it("hides Apple, Google and sign-up when the server has them off, and shows the server's refusal", async () => {
  methods = () => Response.json({ email: true, apple: false, google: false, signUp: false });
  posts["/apps/relay/sign-in/email"] = () => refused(403, "Sign-up is closed on this server.");
  await open("/apps/relay/?signIn=failed");
  expect(await screen.findByText("That sign-in did not work. Try again.")).toBeTruthy();
  expect(screen.queryByRole("link", { name: "Continue with Apple" })).toBeNull();
  expect(screen.queryByRole("link", { name: "Continue with Google" })).toBeNull();
  expect(screen.queryByText(/New here/)).toBeNull();
  fireEvent.change(screen.getByLabelText("Email"), { target: { value: EMAIL } });
  await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Email me a code" })); });
  expect(await screen.findByText("Sign-up is closed on this server.")).toBeTruthy();
  expect(screen.queryByLabelText("Code")).toBeNull();
});

it("goes back to the AI connector's own page after signing in, and never to another site", async () => {
  const next = "/apps/relay/sign-in/connect?state=s1";
  await open(`/apps/relay/?next=${encodeURIComponent(next)}`);
  expect((await screen.findByRole("link", { name: "Continue with Apple" })).getAttribute("href"))
    .toBe(`/apps/relay/sign-in/apple?next=${encodeURIComponent(next)}`);
  await signInWithCode();
  expect(assign).toHaveBeenCalledWith(next);
  cleanup();
  signedIn = false;
  await open("/apps/relay/?next=https%3A%2F%2Fevil.example.com%2F");
  expect((await screen.findByRole("link", { name: "Continue with Google" })).getAttribute("href")).toBe("/apps/relay/sign-in/google");
});

it("shows a plain sign-in message where Access signs people in", async () => {
  methods = () => new Response("Not found", { status: 404 });
  await open();
  expect(await screen.findByText("Sign in to see Relay Everything.")).toBeTruthy();
  expect(screen.queryByLabelText("Email")).toBeNull();
  cleanup();
  methods = () => { throw new TypeError("offline"); };
  await open();
  expect(await screen.findByText("Sign in to see Relay Everything.")).toBeTruthy();
});

it("says when the account can't be read, and reads it again", async () => {
  signedIn = true;
  account = () => new Response("down", { status: 502 });
  await open();
  expect(await screen.findByText(/Your account could not be loaded/)).toBeTruthy();
  account = () => Response.json({ email: EMAIL });
  fireEvent.click(screen.getByRole("button", { name: "Try again" }));
  expect(await screen.findByText(`Signed in as ${EMAIL}`)).toBeTruthy();
});

it("shows the sign-in again when a route says the session ended", async () => {
  signedIn = true;
  await open();
  const list = await screen.findByRole("region", { name: "Devices" });
  devices = () => refused(401, "Sign in to Relay Everything.");
  await act(async () => { fireEvent.click(await within(list).findByRole("button", { name: "Turn off" })); });
  await act(async () => { fireEvent.click(within(screen.getByRole("alertdialog")).getByRole("button", { name: "Turn off" })); });
  expect(await screen.findByText("Sign in or make an account")).toBeTruthy();
});

it("adds a phone and shows its key and QR code once", async () => {
  signedIn = true;
  await open();
  const list = await screen.findByRole("region", { name: "Devices" });
  expect(await within(list).findByText("Ana's phone")).toBeTruthy();
  expect(within(list).getByText("Off")).toBeTruthy();
  fireEvent.click(within(list).getByRole("button", { name: "Add a device" }));
  let dialog = await screen.findByRole("dialog", { name: "Add a device" });
  fireEvent.change(within(dialog).getByLabelText("Name"), { target: { value: " Ana's Pixel " } });
  await act(async () => { fireEvent.click(within(dialog).getByRole("button", { name: "Make the key" })); });
  dialog = await screen.findByRole("dialog", { name: "Connect Ana's Pixel" });
  expect(within(dialog).getByText(/shows this key once/)).toBeTruthy();
  expect(within(dialog).getByRole("img", { name: "QR code for Ana's Pixel" }).querySelector("path")?.getAttribute("d")).toMatch(/^M\d/);
  expect(within(dialog).getByLabelText("The message to copy")).toHaveProperty("value", QR);
  expect(sent("/apps/relay/api/devices")).toEqual([{ name: "Ana's Pixel", reaches: "phone" }]);
  expect(fetchMock.mock.calls.filter(([path, init]) => path === "/apps/relay/api/devices" && !init)).toHaveLength(2);
  fireEvent.click(within(dialog).getByRole("button", { name: "Done" }));
  fireEvent.click(within(list).getByRole("button", { name: "Add a device" }));
  dialog = await screen.findByRole("dialog", { name: "Add a device" });
  expect(within(dialog).queryByText(KEY)).toBeNull();
  fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
});

it("gives the Pebble app its address, header and signing secret, and Claude Code its connect code", async () => {
  signedIn = true;
  await open();
  const list = await screen.findByRole("region", { name: "Devices" });
  fireEvent.click(within(list).getByRole("button", { name: "Add a device" }));
  let dialog = await screen.findByRole("dialog", { name: "Add a device" });
  fireEvent.change(within(dialog).getByLabelText("Device"), { target: { value: "pebble" } });
  await act(async () => { fireEvent.click(within(dialog).getByRole("button", { name: "Make the key" })); });
  dialog = await screen.findByRole("dialog", { name: "Connect Pebble app" });
  const copies = within(dialog).getAllByLabelText("The message to copy").map(field => (field as HTMLTextAreaElement).value);
  expect(copies).toEqual(["https://relay.example.com/apps/relay/api/pebble", `Bearer ${KEY}`, "pebble-secret"]);
  fireEvent.click(within(dialog).getByRole("button", { name: "Done" }));
  fireEvent.click(within(list).getByRole("button", { name: "Add a device" }));
  dialog = await screen.findByRole("dialog", { name: "Add a device" });
  fireEvent.change(within(dialog).getByLabelText("Device"), { target: { value: "claude" } });
  await act(async () => { fireEvent.click(within(dialog).getByRole("button", { name: "Make the key" })); });
  dialog = await screen.findByRole("dialog", { name: "Connect Laptop" });
  expect(within(dialog).getByLabelText("The message to copy")).toHaveProperty("value", QR);
  expect(within(dialog).queryByRole("img")).toBeNull();
  expect(sent("/apps/relay/api/devices")).toEqual([{ name: "Pebble app", reaches: "phone" }, { name: "Laptop", reaches: "chats" }]);
});

it("says why a key was not made, and lists no devices in words", async () => {
  signedIn = true;
  devices = () => Response.json({ devices: [] });
  posts["/apps/relay/api/devices"] = () => refused(400, "Give the device a name.");
  await open();
  const list = await screen.findByRole("region", { name: "Devices" });
  expect(await within(list).findByText(/No devices yet/)).toBeTruthy();
  fireEvent.click(within(list).getByRole("button", { name: "Add a device" }));
  const dialog = await screen.findByRole("dialog", { name: "Add a device" });
  await act(async () => { fireEvent.click(within(dialog).getByRole("button", { name: "Make the key" })); });
  expect(await within(dialog).findByText("Give the device a name.")).toBeTruthy();
});

it("turns a device off after a confirm, and says when it could not", async () => {
  signedIn = true;
  posts["/apps/relay/api/devices/off"] = () => refused(503, "The key could not be turned off. Try again.");
  await open();
  const list = await screen.findByRole("region", { name: "Devices" });
  fireEvent.click(await within(list).findByRole("button", { name: "Turn off" }));
  let confirm = await screen.findByRole("alertdialog", { name: "Turn off Ana's phone?" });
  expect(within(confirm).getByText(/stops working at once/)).toBeTruthy();
  await act(async () => { fireEvent.click(within(confirm).getByRole("button", { name: "Turn off" })); });
  expect(await within(list).findByText("The key could not be turned off. Try again.")).toBeTruthy();
  posts["/apps/relay/api/devices/off"] = ({ id }) => Response.json({ id, revokedAt: NOW });
  devices = () => Response.json({ devices: [{ ...PHONE, revokedAt: NOW }, OLD] });
  fireEvent.click(await within(list).findByRole("button", { name: "Turn off" }));
  confirm = await screen.findByRole("alertdialog", { name: "Turn off Ana's phone?" });
  await act(async () => { fireEvent.click(within(confirm).getByRole("button", { name: "Turn off" })); });
  await waitFor(() => expect(within(list).getAllByText("Off")).toHaveLength(2));
  expect(within(list).queryByRole("alert")).toBeNull();
  expect(sent("/apps/relay/api/devices/off")).toEqual([{ id: "d1" }, { id: "d1" }]);
});

it("says when the devices can't be read", async () => {
  signedIn = true;
  devices = () => new Response("down", { status: 502 });
  await open();
  expect(await screen.findByText(/Devices could not be loaded/)).toBeTruthy();
});

it("deletes the account only after the email is typed, then shows the sign-in", async () => {
  signedIn = true;
  await open();
  fireEvent.click(await screen.findByRole("button", { name: "Delete my account" }));
  fireEvent.change(within(await screen.findByRole("dialog")).getByLabelText(/Type your email/), { target: { value: EMAIL } });
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Cancel" }));
  await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  fireEvent.click(screen.getByRole("button", { name: "Delete my account" }));
  const dialog = await screen.findByRole("dialog", { name: "Delete your account?" });
  expect(within(dialog).getByLabelText(/Type your email/)).toHaveProperty("value", "");
  expect(within(dialog).getByText(/notes, recordings, photos, health, places, chats, devices, webhooks and connected AI apps/)).toBeTruthy();
  const remove = within(dialog).getByRole("button", { name: "Delete everything" });
  expect(remove.hasAttribute("disabled")).toBe(true);
  fireEvent.change(within(dialog).getByLabelText(/Type your email/), { target: { value: "ben@example.com" } });
  expect(remove.hasAttribute("disabled")).toBe(true);
  fireEvent.change(within(dialog).getByLabelText(/Type your email/), { target: { value: " ANA@example.com " } });
  expect(remove.hasAttribute("disabled")).toBe(false);
  posts["/apps/relay/api/account-delete"] = () => refused(503, "The account could not be deleted. Try again.");
  await act(async () => { fireEvent.click(remove); });
  expect(await within(dialog).findByText("The account could not be deleted. Try again.")).toBeTruthy();
  posts["/apps/relay/api/account-delete"] = () => (signedIn = false, Response.json({ deleted: true }));
  await act(async () => { fireEvent.click(remove); });
  expect(await screen.findByText("Sign in or make an account")).toBeTruthy();
  expect(sent("/apps/relay/api/account-delete")).toEqual([{ email: "ANA@example.com" }, { email: "ANA@example.com" }]);
});

it("signs out, and says when it could not", async () => {
  signedIn = true;
  posts["/apps/relay/sign-in/out"] = () => new Response("down", { status: 502 });
  await open();
  await act(async () => { fireEvent.click(await screen.findByRole("button", { name: "Sign out" })); });
  expect(await screen.findByText("/apps/relay/sign-in/out: 502")).toBeTruthy();
  posts["/apps/relay/sign-in/out"] = () => (signedIn = false, Response.json({ ok: true }));
  await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Sign out" })); });
  expect(await screen.findByText("Sign in or make an account")).toBeTruthy();
});
