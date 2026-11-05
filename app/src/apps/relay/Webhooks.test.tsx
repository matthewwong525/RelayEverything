// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { Webhook } from "./read";
import { Webhooks } from "./Webhooks";

const NOW = Date.now();
const DAY = 86_400_000;
const hook = (id: string, more: Partial<Webhook> = {}): Webhook => ({ id, name: `Database ${id}`, url: `https://db${id}.example.com/relay`,
  kinds: ["notes"], state: "working", waiting: 0, lastStatus: null, lastError: null, lastSentAt: null, nextTryAt: null, failingSince: null,
  createdAt: NOW, attempts: [], ...more });
const WORKING = hook("1", { kinds: ["notes", "health", "locations"], waiting: 3, lastStatus: 200, lastSentAt: NOW });
const FAILING = hook("2", { state: "failing", waiting: 12, lastStatus: 503, lastError: "Answered 503.", failingSince: NOW, nextTryAt: NOW + DAY });
const PAUSED = hook("3", { state: "paused" });

type Call = { route: string; input: Record<string, unknown> | null };
let calls: Call[];
let answer: (call: Call) => Response | Promise<Response>;
const list = (webhooks: Webhook[]) => (call: Call) => call.route === "webhooks" && !call.input ? Response.json({ webhooks }) : refuse(call);
const refuse = (call: Call): Response => { throw new Error(`Unexpected route: ${call.route}`); };
beforeEach(() => {
  calls = [];
  answer = list([WORKING, FAILING, PAUSED]);
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

const open = async () => { await act(async () => { render(<Webhooks />); }); };
const card = (name: string) => within(screen.getByLabelText(name));
const posts = () => calls.filter(call => call.input);
const press = async (name: string, where = screen as Pick<typeof screen, "getByRole">) => {
  await act(async () => { fireEvent.click(where.getByRole("button", { name })); });
};
/** Answers each POST with `reply`, and the list as before. */
const replying = (reply: (call: Call) => Response) => {
  const before = answer;
  answer = call => call.input ? reply(call) : before(call);
};

it("says when webhooks could not load, tries again, and shows that there are none", async () => {
  answer = () => Promise.reject(new TypeError("offline"));
  await open();
  expect(screen.getByRole("alert").textContent).toContain("Webhooks could not be loaded.");
  answer = list([]);
  await press("Try again");
  expect(screen.getByText(/No webhooks yet/)).toBeTruthy();
});

it("shows each webhook's state, what it takes, what waits and its last answer", async () => {
  await open();
  const working = card("Database 1");
  expect(working.getByText("Working")).toBeTruthy();
  expect(working.getByText(/^db1\.example\.com · notes, health, location history · 3 waiting · last sent .+ · last answer: answered 200$/)).toBeTruthy();
  expect(card("Database 2").getByText(/12 waiting · next try .+ · failing since .+ · last answer: Answered 503\.$/)).toBeTruthy();
  expect(card("Database 2").getByText("Failing")).toBeTruthy();
  expect(card("Database 3").getByText(/· nothing sent yet$/)).toBeTruthy();
  expect(card("Database 3").getByRole("button", { name: "Resume" })).toBeTruthy();
});

it("adds a webhook with the kinds ticked, shows its secret once, and starts fresh the next time", async () => {
  answer = () => Promise.reject(new TypeError("offline"));
  await open();
  await press("Add a webhook");
  const dialog = within(screen.getByRole("dialog", { name: "Add a webhook" }));
  fireEvent.change(dialog.getByLabelText("Address"), { target: { value: "https://db.example.com/relay" } });
  fireEvent.click(dialog.getByRole("checkbox", { name: /Health/ }));
  fireEvent.click(dialog.getByRole("checkbox", { name: "Location history" }));
  fireEvent.click(dialog.getByRole("checkbox", { name: "Location history" }));
  answer = () => Response.json({ error: { code: "address_private", message: "The address can't be this computer or a private network." } }, { status: 400 });
  await press("Add", dialog);
  expect(dialog.getByRole("alert").textContent).toBe("The address can't be this computer or a private network.");
  answer = () => Response.json({ webhook: hook("9", { name: "My database" }), secret: "whsec_example" });
  await press("Add", dialog);
  expect(posts().at(-1)).toEqual({ route: "webhooks", input: { name: "My database", url: "https://db.example.com/relay", kinds: ["health"] } });
  const added = within(screen.getByRole("dialog", { name: "Webhook added" }));
  expect((added.getByLabelText("The secret") as HTMLInputElement).value).toBe("whsec_example");
  await press("Done", added);
  expect(screen.getByLabelText("My database")).toBeTruthy();
  await press("Add a webhook");
  const again = within(screen.getByRole("dialog", { name: "Add a webhook" }));
  expect((again.getByLabelText("Address") as HTMLInputElement).value).toBe("https://");
  fireEvent.change(again.getByLabelText("Name"), { target: { value: "  Archive " } });
  fireEvent.click(again.getByRole("checkbox", { name: "Location history" }));
  answer = () => Response.json({ webhook: hook("10", { name: "Archive" }), secret: "whsec_second" });
  await press("Add", again);
  expect(posts().at(-1)?.input).toMatchObject({ name: "Archive", kinds: ["locations"] });
  await press("Done");
  await press("Add a webhook");
  await press("Cancel");
  expect(screen.queryByRole("dialog")).toBeNull();
});

it("sends a test and says what came back, or why nothing did", async () => {
  await open();
  const working = card("Database 1");
  for (const [reply, line] of [[{ status: 200, ms: 180, error: null }, "Answered 200 in 180 ms."],
    [{ status: 302, ms: 1500, error: "Answered with a redirect, which Relay does not follow." },
      "Answered 302 in 1.5 s. Answered with a redirect, which Relay does not follow."],
    [{ status: null, ms: 15000, error: "No answer in 15 seconds." }, "No answer: No answer in 15 seconds."]] as const) {
    replying(() => Response.json(reply));
    await press("Send a test", working);
    expect(working.getByRole("status").textContent).toBe(line);
  }
  answer = () => new Response("down", { status: 500 });
  await press("Send a test", working);
  expect(working.getByRole("status").textContent).toBe("webhooks/test: 500");
  expect(posts().map(call => call.input)).toEqual(Array(4).fill({ id: "1" }));
});

it("sends past data from a day, and keeps the dialog open when that fails", async () => {
  await open();
  const working = card("Database 1");
  await press("Send past data", working);
  const dialog = within(screen.getByRole("dialog", { name: "Send past data" }));
  const day = dialog.getByLabelText("From") as HTMLInputElement;
  expect(day.value).toBe(new Date(NOW - 7 * DAY - new Date().getTimezoneOffset() * 60_000).toISOString().slice(0, 10));
  fireEvent.change(day, { target: { value: "" } });
  expect((dialog.getByRole("button", { name: "Send" }) as HTMLButtonElement).disabled).toBe(true);
  fireEvent.change(day, { target: { value: "2026-10-01" } });
  replying(() => Response.json({ error: { code: "not_found", message: "No webhook has this id." } }, { status: 404 }));
  await press("Send", dialog);
  expect(screen.getByRole("dialog", { name: "Send past data" })).toBeTruthy();
  expect(working.getByText("No webhook has this id.")).toBeTruthy();
  replying(() => Response.json({ webhook: { ...WORKING, state: "backfilling" } }));
  await press("Send", dialog);
  expect(posts().at(-1)).toEqual({ route: "webhooks/resend", input: { id: "1", since: new Date("2026-10-01T00:00").getTime() } });
  expect(screen.queryByRole("dialog")).toBeNull();
  expect(working.getByText("Sending past data")).toBeTruthy();
});

it("tries a failing webhook again, pauses and resumes, makes a new secret and removes", async () => {
  await open();
  replying(call => Response.json({ webhook: call.route === "webhooks/retry" ? { ...FAILING, state: "working", failingSince: null }
    : { ...(call.input!.id === "1" ? WORKING : PAUSED), state: call.input!.active ? "working" : "paused" } }));
  await press("Try again now", card("Database 2"));
  expect(card("Database 2").getByText("Working")).toBeTruthy();
  await press("Pause", card("Database 1"));
  await press("Resume", card("Database 3"));
  expect(posts().slice(1).map(call => call.input)).toEqual([{ id: "1", active: false }, { id: "3", active: true }]);
  expect(card("Database 1").getByText("Paused")).toBeTruthy();
  expect(card("Database 3").getByText("Working")).toBeTruthy();

  replying(call => call.route === "webhooks/secret" ? Response.json({ secret: "whsec_new" }) : Response.json({ removed: true }));
  await press("New secret", card("Database 1"));
  await press("New secret", within(screen.getByRole("alertdialog")));
  const secret = within(screen.getByRole("dialog", { name: "New secret" }));
  expect((secret.getByLabelText("The secret") as HTMLInputElement).value).toBe("whsec_new");
  await press("Done", secret);
  await press("New secret", card("Database 1"));
  await press("New secret", within(screen.getByRole("alertdialog")));
  await act(async () => { fireEvent.keyDown(screen.getByRole("dialog", { name: "New secret" }), { key: "Escape" }); });
  expect(screen.queryByRole("dialog")).toBeNull();

  await press("Remove", card("Database 3"));
  await press("Remove", within(screen.getByRole("alertdialog")));
  expect(screen.queryByLabelText("Database 3")).toBeNull();
  expect(posts().at(-1)).toEqual({ route: "webhooks/remove", input: { id: "3" } });
});
