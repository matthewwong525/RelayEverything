// GET audio?id=: a ring note's recording, streamed from R2 for the site page and the phones to play. It answers one
// byte range too, as Safari asks for one before it plays anything.
import type { ActionCall } from "../../api/contract.ts";
import { refused, session, type Env } from "./store.ts";

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

export async function audio(request: Request, env: Env, { url }: Pick<ActionCall, "url">): Promise<Response> {
  const id = url.searchParams.get("id") ?? "";
  if (!ID.test(id)) return refused(400, "Give a note's id");
  const note = await session(env).prepare("SELECT audio_key FROM relay_notes WHERE id = ?").bind(id).first<{ audio_key: string | null }>();
  const key = note?.audio_key;
  const notFound = () => Response.json({ error: "Not found" }, { status: 404 });
  if (!key) return notFound();
  const headers = { "Content-Type": "audio/mp4", "Accept-Ranges": "bytes", "Cache-Control": "private, max-age=3600" };
  const wanted = rangeOf(request.headers.get("Range"));
  if (!wanted) {
    const object = await env.RELAY_BUCKET.get(key);
    return object ? new Response(object.body, { headers: { ...headers, "Content-Length": String(object.size) } }) : notFound();
  }
  const head = await env.RELAY_BUCKET.head(key);
  if (!head) return notFound();
  const bytes = bytesOf(wanted, head.size);
  if (!bytes) return new Response(null, { status: 416, headers: { ...headers, "Content-Range": `bytes */${head.size}` } });
  const [first, last] = bytes;
  // The object was there a moment ago, at head().
  const object = (await env.RELAY_BUCKET.get(key, { range: { offset: first, length: last - first + 1 } }))!;
  return new Response(object.body, { status: 206, headers: { ...headers, "Content-Length": String(last - first + 1),
    "Content-Range": `bytes ${first}-${last}/${head.size}` } });
}
