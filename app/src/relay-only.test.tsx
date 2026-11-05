// @vitest-environment jsdom

import { screen } from "@testing-library/react";
import { expect, it, vi } from "vitest";

it("shows the Relay page in a plain frame, with no WongStack name or route", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => new Response("{}", { status: 503 })));
  document.body.innerHTML = '<div id="root"></div>';
  await import("./relay-only");
  expect(await screen.findByText("Relay", { selector: "header span" })).toBeTruthy();
  expect(document.body.textContent).not.toMatch(/WongStack|Your apps/);
});
