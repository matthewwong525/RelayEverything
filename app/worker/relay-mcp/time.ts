// Times as the AI reads and writes them: ISO text in a named time zone, Toronto unless a question names another.
const MINUTE = 60_000;
export const HOUR = 60 * MINUTE;
export const ZONE = "America/Toronto";

/** The zone's offset from UTC at that instant, in minutes east. */
function offset(zone: string, at: number): number {
  const name = new Intl.DateTimeFormat("en-US", { timeZone: zone, timeZoneName: "longOffset" }).formatToParts(at)
    .find(part => part.type === "timeZoneName")!.value;
  // Some runtimes write UTC as a bare "GMT".
  const [, sign = "+", hours = "0", minutes = "0"] = /^GMT(?:([+-])(\d\d):(\d\d))?$/.exec(name)!;
  return Number(`${sign}1`) * (Number(hours) * 60 + Number(minutes));
}

/** True for a zone name the runtime knows, such as `Europe/London`. */
export function knownZone(zone: string): boolean {
  try { new Intl.DateTimeFormat("en-US", { timeZone: zone }); return true; } catch { return false; }
}

/** A wall-clock time in the zone, written as if it were UTC, to the instant it names. Twice, so a time near a
 *  daylight-saving change takes the offset in force at the answer, not at the guess. */
const fromWall = (wall: number, zone: string) =>
  Number.isNaN(wall) ? NaN : wall - offset(zone, wall - offset(zone, wall) * MINUTE) * MINUTE;

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const ZONED = /(?:Z|[+-]\d\d:\d\d)$/i;

/** An instant from the AI's text: a day is its first moment in the zone, a time with no offset is the zone's
 *  wall clock, and a time with one is taken as written. NaN when it is none of them. */
export function instant(text: string, zone: string): number {
  if (DAY.test(text)) return startOfDay(text, zone);
  if (ZONED.test(text)) return Date.parse(text);
  return fromWall(Date.parse(`${text}Z`), zone);
}

export const startOfDay = (day: string, zone: string) => fromWall(Date.parse(`${day}T00:00:00Z`), zone);

/** The day after, as YYYY-MM-DD. */
export const nextDay = (day: string) => new Date(Date.parse(`${day}T00:00:00Z`) + 24 * HOUR).toISOString().slice(0, 10);

/** An instant as ISO text in the zone, with its offset: 2026-11-04T09:01:00-05:00. */
export function local(at: number, zone: string): string {
  const minutes = offset(zone, at);
  const sign = minutes < 0 ? "-" : "+";
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${new Date(at + minutes * MINUTE).toISOString().slice(0, 19)}${sign}${pad(Math.floor(Math.abs(minutes) / 60))}:${pad(Math.abs(minutes) % 60)}`;
}

/** The zone's day an instant falls on. */
export const dayOf = (at: number, zone: string) => local(at, zone).slice(0, 10);
