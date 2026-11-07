// Gmail's messages as the AI reads and writes them: a message's headers and its words as plain text, and a new
// email as the raw MIME text Gmail's send and draft take.
type Part = { mimeType?: string; filename?: string; headers?: { name: string; value: string }[]; body?: { data?: string }; parts?: Part[] };
export type GmailMessage = { id: string; threadId: string; labelIds?: string[]; snippet?: string; payload?: Part };

const utf8 = new TextEncoder();
const base64 = (bytes: Uint8Array) => btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join(""));
const base64url = (text: string) => base64(utf8.encode(text)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
const fromBase64url = (data: string) =>
  new TextDecoder().decode(Uint8Array.from(atob(data.replaceAll("-", "+").replaceAll("_", "/")), char => char.charCodeAt(0)));

/** A header's value, by its name in any case, or null. */
export const headerOf = (message: GmailMessage, name: string) =>
  message.payload?.headers?.find(header => header.name.toLowerCase() === name.toLowerCase())?.value ?? null;

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", apos: "'", nbsp: " " };

/** An HTML email's words: no styles, scripts or tags, a line for each block, and the common entities read. */
const htmlText = (html: string) => html
  .replace(/<(style|script|head)[\s\S]*?<\/\1>/gi, "")
  .replace(/<(?:br|\/p|\/div|\/li|\/tr|\/h\d)[^>]*>/gi, "\n")
  .replace(/<[^>]+>/g, "")
  .replace(/&(amp|lt|gt|quot|#39|apos|nbsp);/g, (_, name: string) => ENTITIES[name])
  .replace(/[ \t]+/g, " ").replace(/\n\s*\n+/g, "\n\n").trim();

const partsOf = (part: Part | undefined): Part[] => part ? [part, ...(part.parts ?? []).flatMap(partsOf)] : [];

/** A message's words: its plain text part, or its HTML part as text. Never an attachment. */
export function mailText(message: GmailMessage): string {
  const parts = partsOf(message.payload).filter(part => !part.filename && part.body?.data);
  const plain = parts.find(part => part.mimeType === "text/plain");
  if (plain) return fromBase64url(plain.body!.data!).trim();
  const html = parts.find(part => part.mimeType === "text/html");
  return html ? htmlText(fromBase64url(html.body!.data!)) : "";
}

/** The names of a message's attachments, and nothing of their contents. */
export const attachmentsOf = (message: GmailMessage) => partsOf(message.payload).flatMap(part => part.filename ? [part.filename] : []);

/** A header value that may hold any letter: an encoded word when it is not plain ASCII. */
const encoded = (text: string) => /^[\x20-\x7e]*$/.test(text) ? text : `=?UTF-8?B?${base64(utf8.encode(text))}?=`;

export type Letter = { to: string[]; cc?: string[]; bcc?: string[]; subject: string; text: string; more?: Record<string, string> };

/** A plain text email as Gmail's `raw`: base64url MIME, its body in base64 lines of 76. The inputs hold no line
 *  break, so no header can be added through them. */
export function rawOf({ to, cc, bcc, subject, text, more = {} }: Letter): string {
  const headers: [string, string | undefined][] = [["To", to.join(", ")], ["Cc", cc?.join(", ")], ["Bcc", bcc?.join(", ")],
    ["Subject", encoded(subject)], ...Object.entries(more), ["MIME-Version", "1.0"], ["Content-Type", 'text/plain; charset="UTF-8"'],
    ["Content-Transfer-Encoding", "base64"]];
  const body = base64(utf8.encode(text)).replace(/.{76}/g, "$&\r\n");
  return base64url(`${headers.filter(([, value]) => value).map(([name, value]) => `${name}: ${value}`).join("\r\n")}\r\n\r\n${body}`);
}
