// GET audio?id=: a ring note's recording from the caller's own space, opened with its file key, for the site page and
// the phones to play. It answers one byte range too, as Safari asks for one before it plays anything.
import type { ActionCall } from "../../api/contract.ts";
import { asPersonOrPhone } from "./caller.ts";
import { refused, type Env } from "./store.ts";

const ID = /^[0-9a-f-]{36}$/;
const RANGE = /^bytes=(\d*)-(\d*)$/;

type Wanted = { start: number; end?: number } | { suffix: number };

/** One range from a Range header, or null to send the whole file: no header, several ranges, or words it can't read. */
function rangeOf(header: string | null): Wanted | null {
  const [, start, end] = RANGE.exec(header?.trim() ?? "") ?? [];
  if (start === undefined || (start === "" && end === "")) return null;
  if (start === "") return { suffix: Number(end) };
  if (end !== "" && Number(end) < Number(start)) return null;
  return end === "" ? { start: Number(start) } : { start: Number(start), end: Number(end) };
}

/** The first and last byte to send, or null when the file holds none of them. */
function bytesOf(wanted: Wanted, size: number): [number, number] | null {
  const [first, last] = "suffix" in wanted ? [Math.max(size - wanted.suffix, 0), size - 1] : [wanted.start, Math.min(wanted.end ?? size - 1, size - 1)];
  return first <= last ? [first, last] : null;
}

type Call = Pick<ActionCall, "url" | "identity">;

// A sealed file opens only whole, so a range is cut from the opened bytes: a ring note's recording is small.
export const audio: (request: Request, env: Env, call: Call) => Promise<Response> = asPersonOrPhone<Call>(async ({ space, request, call }) => {
  const id = call.url.searchParams.get("id") ?? "";
  if (!ID.test(id)) return refused(400, "Give a note's id");
  const note = await space.db.prepare("SELECT audio_key FROM relay_notes WHERE id = ?").bind(id).first<{ audio_key: string | null }>();
  const data = note?.audio_key ? await space.files.open(note.audio_key) : null;
  if (!data) return Response.json({ error: "Not found" }, { status: 404 });
  const headers = { "Content-Type": "audio/mp4", "Accept-Ranges": "bytes", "Cache-Control": "private, max-age=3600" };
  const wanted = rangeOf(request.headers.get("Range"));
  if (!wanted) return new Response(data, { headers: { ...headers, "Content-Length": String(data.byteLength) } });
  const bytes = bytesOf(wanted, data.byteLength);
  if (!bytes) return new Response(null, { status: 416, headers: { ...headers, "Content-Range": `bytes */${data.byteLength}` } });
  const [first, last] = bytes;
  return new Response(data.slice(first, last + 1), { status: 206, headers: { ...headers, "Content-Length": String(last - first + 1),
    "Content-Range": `bytes ${first}-${last}/${data.byteLength}` } });
});
