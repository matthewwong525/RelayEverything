// Mail from Cloudflare Email Routing, by its envelope's recipient: a person's secret notes address takes mail from
// anyone; notes@ takes it only from a sender the checks proved. No mail is ever sent back. wiki/relay-spaces.md#ways-in
import PostalMime, { type Email } from "postal-mime";
import { hashToken, normalEmail } from "../people.ts";
import { base64 } from "../webhooks/sign.ts";
import { hold, type HeldEnv } from "./held.ts";
import { byAddress, bySignIn, inboxOf, SHARED } from "./links.ts";
import { receive, type InboxFile, type InboxItem } from "./receive.ts";

type Mail = Pick<ForwardableEmailMessage, "to" | "raw" | "setReject">;
type Result = { method: string; result: string; props: Record<string, string> };

const DAY = 24 * 60 * 60_000;
/** The size from which a picture in the mail's body is a file, such as a pasted screenshot; a smaller one, such as a
 *  logo or a tracking pixel, is part of the mail's look. */
const INLINE_FILE_BYTES = 20 * 1024;
/** Cloudflare's own name in the sender check it adds on top of the mail, above any header the sender wrote. */
const CLOUDFLARE = "mx.cloudflare.net";
const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " };

/** A server's bindings, where a preview has no spaces. */
type MailEnv = Omit<HeldEnv, "SPACES" | "WORKBENCHES"> & Partial<Pick<HeldEnv, "SPACES" | "WORKBENCHES">>;
const hasSpaces = (env: MailEnv): env is HeldEnv => !!env.SPACES && !!env.WORKBENCHES;

/** Mail for this server's mail domain: a note, kept mail, or a refusal. Off, the server refuses all mail. */
export async function email(message: Mail, env: MailEnv): Promise<void> {
  const inbox = inboxOf(env);
  if (!inbox || !hasSpaces(env)) return message.setReject("This server takes no email.");
  const at = message.to.lastIndexOf("@");
  const [local, domain] = [message.to.slice(0, at).toLowerCase(), message.to.slice(at + 1).toLowerCase()];
  const caller = domain === inbox.domain && local !== SHARED ? await byAddress(env, local) : null;
  if (domain !== inbox.domain || (local !== SHARED && !caller)) return message.setReject("No such address.");
  const read = await readMail(message.raw).catch(() => null);
  if (!read) return message.setReject("This mail could not be read.");
  const item = await itemOf(read.mail, read.raw);
  if (caller) {
    await receive(env, caller, item);
    return;
  }
  // notes@: mail that fails the checks can't be tied to anyone safely, so it is dropped with no answer.
  const from = checkedSender(read.mail);
  if (!from) return;
  const person = await bySignIn(env, from);
  await (person ? receive(env, person, item) : hold(env, from, item));
}

async function readMail(stream: Mail["raw"]): Promise<{ raw: Uint8Array; mail: Email }> {
  const raw = new Uint8Array(await new Response(stream).arrayBuffer());
  return { raw, mail: await PostalMime.parse(raw) };
}

/** The mail as one inbox message: its subject and words, its files, and when it was sent. */
async function itemOf(mail: Email, raw: Uint8Array): Promise<InboxItem> {
  const words = mail.text?.trim() ? mail.text : mail.html ? htmlText(mail.html) : "";
  const text = [mail.subject?.trim(), withoutQuote(words)].filter(Boolean).join("\n\n");
  const id = await hashToken(mail.messageId?.trim() || base64(new Uint8Array(await crypto.subtle.digest("SHA-256", raw))));
  const sent = Date.parse(mail.date ?? "");
  const sentAt = sent > 1e12 && sent < Date.now() + DAY ? sent : Date.now();
  // postal-mime gives each file as an ArrayBuffer unless asked for text. A part the body shows by its Content-ID is a
  // file only from 20 KB: the server can't tell a pasted photo from a logo by its place, so it goes by size.
  const files: InboxFile[] = mail.attachments.filter(file => !file.related || (file.content as ArrayBuffer).byteLength >= INLINE_FILE_BYTES)
    .map(file => ({ name: file.filename ?? "attachment", type: file.mimeType, bytes: new Uint8Array(file.content as ArrayBuffer) }));
  return { channel: "email", id, sentAt, text, files };
}

/** The words without the quoted mail a reply ends with: its `>` lines, and the *On … wrote:* line above them. A
 *  forwarded mail is not quoted, so it stays. */
export function withoutQuote(text: string): string {
  const plain = text.replace(/\r\n?/g, "\n");
  const lines = plain.split("\n");
  let end = lines.length;
  while (end > 0 && (lines[end - 1].trim() === "" || lines[end - 1].startsWith(">"))) end--;
  if (!lines.slice(end).some(line => line.startsWith(">"))) return plain.trim();
  const attribution = [1, 2].find(count => end >= count && /^On .+wrote:\s*$/s.test(lines.slice(end - count, end).join(" ")));
  return lines.slice(0, end - (attribution ?? 0)).join("\n").trim();
}

const character = (code: string) => {
  const point = code[1].toLowerCase() === "x" ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
  return point > 0 && point <= 0x10ffff ? String.fromCodePoint(point) : "";
};

/** An HTML mail's words, for a mail with no plain part: block ends become lines, tags go, entities become letters. */
export function htmlText(html: string): string {
  return html.replace(/<(script|style|head)\b[\s\S]*?<\/\1\s*>/gi, "").replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(?:p|div|li|tr|h[1-6]|blockquote|table)\s*>/gi, "\n").replace(/<li\b[^>]*>/gi, "- ").replace(/<[^>]*>/g, "")
    .replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, code: string) => code.startsWith("#") ? character(code) : ENTITIES[code.toLowerCase()] ?? whole)
    .replace(/[ \t ]+/g, " ").replace(/ *\n */g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

/** The From email when the mail has one From and Cloudflare's check passed for its domain, else null. */
export function checkedSender(mail: Pick<Email, "from" | "headers">): string | null {
  const address = mail.from?.address;
  if (!address || mail.headers.filter(header => header.key === "from").length !== 1) return null;
  const from = normalEmail(address);
  const results = resultsOf(mail.headers);
  return results && passes(results, from.slice(from.lastIndexOf("@") + 1)) ? from : null;
}

/** Each result in the topmost sender check, which only Cloudflare can have written; null when not Cloudflare's. */
function resultsOf(headers: Email["headers"]): Result[] | null {
  const header = headers.find(item => item.key === "authentication-results" || item.key === "arc-authentication-results");
  const parts = (header?.value ?? "").replace(/\([^()]*\)/g, " ").split(";").map(part => part.trim());
  if (/^i=\d+$/.test(parts[0])) parts.shift();
  if (parts[0]?.toLowerCase() !== CLOUDFLARE) return null;
  return parts.slice(1).map(part => {
    const [first = "", ...rest] = part.split(/\s+/);
    const [method = "", result = ""] = first.toLowerCase().split("=");
    const props = Object.fromEntries(rest.map(item => item.toLowerCase().split("=")).filter(pair => pair.length === 2)
      .map(([name, value]) => [name, value.replace(/^"|"$/g, "")]));
    return { method, result, props };
  });
}

const domainOf = (value?: string) => value?.slice(value.lastIndexOf("@") + 1);

/** DMARC passed for the From domain, or SPF and DKIM both passed for a domain aligned with it. */
function passes(results: Result[], domain: string): boolean {
  const aligned = (other?: string) => !!other && (other === domain || domain.endsWith(`.${other}`) || other.endsWith(`.${domain}`));
  const passed = (method: string, aligns: (props: Record<string, string>) => string | undefined) =>
    results.some(item => item.method === method && item.result === "pass" && aligned(aligns(item.props)));
  return passed("dmarc", props => props["header.from"])
    || (passed("spf", props => domainOf(props["smtp.mailfrom"])) && passed("dkim", props => props["header.d"] ?? domainOf(props["header.i"])));
}
