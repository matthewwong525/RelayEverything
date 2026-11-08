import { expect, it } from "vitest";
import PostalMime from "postal-mime";
import { ANA, BEN, bucket, directoryDb, env, NOW, rows } from "../../../../tests/relay";
import { DOMAIN, fixture, inboxEnv, mailTo } from "../../../../tests/relay-inbox";
import { checkedSender, email, htmlText, withoutQuote } from "./email";
import { claim } from "./held";
import { addressOf, newAddress } from "./links";

const SHARED = `notes@${DOMAIN}`;
const deliver = async (to: string, name: string, more: object = {}) => {
  const message = mailTo(to, fixture(name));
  await email(message, inboxEnv(more));
  return message.setReject.mock.calls.map(([reason]) => reason);
};
const notes = (person = ANA) => rows("relay_notes", person).filter(row => row.client_id?.toString().startsWith("email:"));
const held = () => directoryDb.sql.prepare("SELECT count(*) AS count FROM relay_inbox_held").get();

it("makes a forwarded mail to a secret address a note, from any sender, with its PDF and the time it was sent", async () => {
  const address = (await addressOf(inboxEnv(), ANA))!;
  expect(await deliver(address, "forwarded-pdf.eml")).toEqual([]);
  const [note] = notes();
  expect(note.text).toBe("Fwd: Your receipt\n\n---------- Forwarded message ---------\nFrom: Corner Shop <receipts@shop.example.net>\n\n"
    + "Thank you for your order of 2 TL3312 switches.");
  expect(note.recorded_at).toBe(Date.UTC(2026, 10, 4, 15, 30));
  expect(rows("relay_attachments").map(row => [row.name, row.content_type, row.file_key !== null])).toEqual([["receipt.pdf", "application/pdf", true]]);
  // Email Routing may hand the same mail over again: it stays one note.
  await deliver(address.toUpperCase(), "forwarded-pdf.eml");
  expect(notes()).toHaveLength(1);
  expect(bucket.put).toHaveBeenCalledOnce();
  expect(notes(BEN)).toEqual([]);
});

it("keeps an HTML mail's words, and leaves out the pictures its look shows", async () => {
  await deliver((await addressOf(inboxEnv(), ANA))!, "html-newsletter.eml");
  expect(notes()[0].text).toBe("This week in rings\n\nRings & things\nSmart rings got smaller.\n- One\n- Two – three");
  expect(rows("relay_attachments")).toEqual([]);
});

it("keeps a screenshot pasted into the body as a file, and leaves out a small inline logo without naming it", async () => {
  await deliver((await addressOf(inboxEnv(), ANA))!, "pasted-screenshot.eml");
  expect(notes()[0].text).toBe("Charger idea\n\nLike this one:\n\n[image: image.png]");
  expect(rows("relay_attachments").map(row => [row.name, row.content_type, row.size])).toEqual([["image.png", "image/png", 8 + 24 * 1024]]);
});

it("makes mail to notes@ from a sign-in email a note, without the quoted mail below it", async () => {
  expect(await deliver(SHARED, "notes-sign-in.eml")).toEqual([]);
  expect(notes().map(row => row.text)).toEqual(["Re: Ring charger\n\nOrder the pogo pins too."]);
});

it("keeps mail to notes@ from a checked email with no account, and makes it a note when that email joins", async () => {
  expect(await deliver(SHARED, "notes-new-sender.eml")).toEqual([]);
  expect(held()).toEqual({ count: 1 });
  directoryDb.sql.prepare("INSERT INTO relay_people (id, email, created_at) VALUES ('p-cy', 'cy@example.com', 0)").run();
  expect(await claim(inboxEnv(), "cy@example.com")).toBe(1);
  expect(notes("p-cy").map(row => [row.text, row.recorded_at])).toEqual([["Idea: ring charger\n\nA cradle with pogo pins.", Date.UTC(2026, 10, 2, 10)]]);
  expect(rows("relay_attachments", "p-cy").map(row => row.name)).toEqual(["sketch.pdf"]);
});

it("drops mail to notes@ whose sender failed the checks, with no answer and nothing kept", async () => {
  expect(await deliver(SHARED, "notes-forged.eml")).toEqual([]);
  const unsigned = Buffer.from(fixture("notes-sign-in.eml").toString("latin1").replace(/^Authentication-Results:[\s\S]*?(?=^From:)/m, ""), "latin1");
  const message = mailTo(SHARED, unsigned);
  await email(message, inboxEnv());
  expect(message.setReject).not.toHaveBeenCalled();
  expect([notes(), held()]).toEqual([[], { count: 0 }]);
});

it("refuses mail to a replaced or made-up address, another domain, or a server with email off", async () => {
  const old = (await addressOf(inboxEnv(), ANA))!;
  await newAddress(inboxEnv(), ANA);
  expect(await deliver(old, "forwarded-pdf.eml")).toEqual(["No such address."]);
  expect(await deliver(`notes-aaaaaaaaaa@${DOMAIN}`, "forwarded-pdf.eml")).toEqual(["No such address."]);
  expect(await deliver("notes@example.com", "notes-sign-in.eml")).toEqual(["No such address."]);
  for (const off of [{ RELAY_INBOX_HMAC_KEY: undefined }, { RELAY_INBOX_MAIL_DOMAIN: undefined }, { SPACES: undefined }]) {
    expect(await deliver(SHARED, "notes-sign-in.eml", off)).toEqual(["This server takes no email."]);
  }
  const plain = mailTo(SHARED, fixture("notes-sign-in.eml"));
  await email(plain, env());
  expect(plain.setReject).toHaveBeenCalledWith("This server takes no email.");
  expect(notes()).toEqual([]);
});

it("makes a bare mail a note at the time it came, and refuses mail that can't be read", async () => {
  const address = (await addressOf(inboxEnv(), ANA))!;
  const bare = "To: someone\r\nContent-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\nContent-Type: application/octet-stream\r\n"
    + "Content-Transfer-Encoding: base64\r\n\r\nAAEC\r\n--b--\r\n";
  expect(await email(mailTo(address, bare), inboxEnv())).toBeUndefined();
  expect(notes().map(row => [row.text, row.recorded_at])).toEqual([["", NOW]]);
  expect(rows("relay_attachments").map(row => [row.name, row.size])).toEqual([["attachment", 3]]);
  const broken = { ...mailTo(address, ""), raw: new ReadableStream({ pull: control => control.error(new Error("cut off")) }) };
  await email(broken, inboxEnv());
  expect(broken.setReject).toHaveBeenCalledWith("This mail could not be read.");
});

const parsed = (headers: string) => PostalMime.parse(`${headers}From: Ana <ana@example.com>\r\nSubject: Hi\r\n\r\nHi\r\n`);

it("takes a sender only on Cloudflare's own topmost check, with DMARC or aligned SPF and DKIM passed", async () => {
  const results = (body: string, name = "Authentication-Results", by = "mx.cloudflare.net") => `${name}: ${by}; ${body}\r\n`;
  const pass = "dkim=pass header.d=example.com; spf=pass smtp.mailfrom=bounce@mail.example.com";
  expect(checkedSender(await parsed(results("dmarc=pass header.from=example.com")))).toBe("ana@example.com");
  expect(checkedSender(await parsed(results(pass)))).toBe("ana@example.com");
  expect(checkedSender(await parsed(`ARC-Authentication-Results: i=1; mx.cloudflare.net; ${pass}\r\n`))).toBe("ana@example.com");
  expect(checkedSender(await parsed(results("dkim=pass header.d=example.com; spf=fail smtp.mailfrom=ana@example.com")))).toBeNull();
  expect(checkedSender(await parsed(results("dkim=pass header.d=example.net; spf=pass smtp.mailfrom=ana@example.net")))).toBeNull();
  expect(checkedSender(await parsed(results("dmarc=pass header.from=example.com", "Authentication-Results", "mx.example.net")))).toBeNull();
  expect(checkedSender(await parsed(""))).toBeNull();
  expect(checkedSender(await parsed(`${results("dmarc=pass header.from=example.com")}From: Ben <ben@example.com>\r\n`))).toBeNull();
});

it("cuts the quoted mail a reply ends with, and keeps a forward and quotes inside the words", () => {
  expect(withoutQuote("Yes.\n\nOn Tue, Nov 3, 2026 at 9:00 AM Ana wrote:\n> Order?\n>\n> Thanks\n")).toBe("Yes.");
  expect(withoutQuote("Yes.\r\n\r\nOn Tue, Nov 3, 2026 at 9:00 AM Ana <ana@example.com>\r\nwrote:\r\n> Order?\r\n")).toBe("Yes.");
  expect(withoutQuote("> a quote\nmy answer")).toBe("> a quote\nmy answer");
  expect(withoutQuote("Yes.\n> Order?")).toBe("Yes.");
  expect(withoutQuote("> only a quote")).toBe("");
  expect(withoutQuote("See below.\n\n---------- Forwarded message ---------\nFrom: Shop\n\nThanks.")).toBe(
    "See below.\n\n---------- Forwarded message ---------\nFrom: Shop\n\nThanks.");
});

it("reads an HTML mail's words: blocks become lines, and scripts, styles and tags go", () => {
  expect(htmlText("<style>p{}</style><p>One&nbsp;two</p><script>x()</script><div>Three<br>four &lt;5&gt; &#x41;&#66;&bogus;&#0;&#x110000;</div>"))
    .toBe("One two\nThree\nfour <5> AB&bogus;");
});
