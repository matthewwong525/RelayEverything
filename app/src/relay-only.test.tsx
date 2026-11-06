// @vitest-environment jsdom

import { screen } from "@testing-library/react";
import { expect, it, vi } from "vitest";

it("shows the Relay page in a plain frame, with no WongStack name or route", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => new Response("{}", { status: 503 })));
  document.body.innerHTML = '<div id="root"></div>';
  await import("./relay-only");
  expect(await screen.findByText("Relay Everything", { selector: "header span" })).toBeTruthy();
  expect(document.body.textContent).not.toMatch(/WongStack|Your apps/);
});

it("shows the sign-in with no router around it, as the shared server serves it", async () => {
  vi.resetModules();
  vi.stubGlobal("fetch", vi.fn(async (path: string) => path.endsWith("/sign-in/methods")
    ? Response.json({ email: true, apple: false, google: false, signUp: true }) : new Response("{}", { status: 401 })));
  document.body.innerHTML = '<div id="root"></div>';
  await import("./relay-only");
  expect(await screen.findByRole("button", { name: "Email me a code" })).toBeTruthy();
});
