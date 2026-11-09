// @vitest-environment jsdom

import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, expect, it } from "vitest";
import { Notes } from "./Notes";
import { sizeOf, type Note } from "./read";

afterEach(cleanup);

const file = (id: string, name: string, type: string, size: number, ready = true) => ({ id, name, type, size, ready });
const note: Note = { id: "00000000-0000-4000-8000-000000000001", source: "typed", text: "Receipt for the desk lamp", recordedAt: Date.now(),
  device: "iPhone", audio: false, place: null, attachments: [file("file-png-0001", "receipt.png", "image/png", 1_258_291),
    file("file-pdf-0001", "warranty.pdf", "application/pdf", 245_760), file("file-txt-0001", "list.txt", "text/plain", 12, false)] };

it("shows a note's picture, a download link for another file, and a file still on its way as waiting", () => {
  render(<Notes first={{ notes: [note], next: null, nextId: null }} />);
  const files = within(screen.getByLabelText("Note")).getByRole("list", { name: "Files" });
  expect(within(files).getByRole("img", { name: "receipt.png" }).getAttribute("src")).toBe("/apps/relay/api/attachment?id=file-png-0001");
  const pdf = within(files).getByRole("link", { name: "warranty.pdf · 240 KB · Download" });
  expect(pdf.getAttribute("href")).toBe("/apps/relay/api/attachment?id=file-pdf-0001");
  expect(pdf.getAttribute("download")).toBe("warranty.pdf");
  expect(within(files).getByText("list.txt · 12 B · Waiting for the file")).toBeTruthy();
  expect(within(files).queryByRole("link", { name: /list\.txt/ })).toBeNull();
});

it("shows a note of files alone with no line of missing words", () => {
  render(<Notes first={{ notes: [{ ...note, text: "", attachments: [note.attachments[1]] }], next: null, nextId: null }} />);
  expect(screen.queryByText("No words, only the recording.")).toBeNull();
  expect(screen.getByRole("link", { name: /warranty\.pdf/ })).toBeTruthy();
});

it("writes sizes in bytes, KB and MB", () => {
  expect([sizeOf(12), sizeOf(245_760), sizeOf(1_258_291)]).toEqual(["12 B", "240 KB", "1.2 MB"]);
});
