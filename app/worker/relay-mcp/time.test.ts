import { expect, it } from "vitest";
import { dayOf, instant, knownZone, local, nextDay, startOfDay } from "./time";

it("reads a day, a wall-clock time and a time with an offset in the zone", () => {
  expect(instant("2026-11-04", "America/Toronto")).toBe(Date.UTC(2026, 10, 4, 5));
  expect(instant("2026-11-04T09:00", "America/Toronto")).toBe(Date.UTC(2026, 10, 4, 14));
  expect(instant("2026-07-04T09:00:00", "America/Toronto")).toBe(Date.UTC(2026, 6, 4, 13));
  expect(instant("2026-11-04T09:00Z", "America/Toronto")).toBe(Date.UTC(2026, 10, 4, 9));
  expect(instant("2026-11-04T09:00+05:30", "UTC")).toBe(Date.UTC(2026, 10, 4, 3, 30));
  for (const wrong of ["yesterday", "2026-11-04T25:00", "2026-13-45T00:00Z"]) expect(instant(wrong, "America/Toronto")).toBeNaN();
});

it("takes the offset in force at the answer near a clock change", () => {
  // Toronto's clocks went back at 02:00 on 1 November 2026: the day is 25 hours long.
  expect(nextDay("2026-11-01")).toBe("2026-11-02");
  expect(startOfDay("2026-11-02", "America/Toronto") - startOfDay("2026-11-01", "America/Toronto")).toBe(25 * 3600_000);
  expect(instant("2026-11-01T12:00", "America/Toronto")).toBe(Date.UTC(2026, 10, 1, 17));
});

it("writes an instant in the zone, with its offset", () => {
  expect(local(Date.UTC(2026, 10, 4, 13, 1), "America/Toronto")).toBe("2026-11-04T08:01:00-05:00");
  expect(local(Date.UTC(2026, 10, 4, 13, 1), "Asia/Kolkata")).toBe("2026-11-04T18:31:00+05:30");
  expect(local(Date.UTC(2026, 10, 4, 13, 1), "UTC")).toBe("2026-11-04T13:01:00+00:00");
  expect(dayOf(Date.UTC(2026, 10, 5, 3), "America/Toronto")).toBe("2026-11-04");
});

it("knows a time zone by its name", () => {
  expect(knownZone("Europe/London")).toBe(true);
  expect(knownZone("Mars/Olympus")).toBe(false);
});
