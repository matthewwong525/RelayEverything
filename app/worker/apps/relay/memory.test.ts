import { beforeEach, expect, it, vi } from "vitest";
import { ANA, bucket, queue } from "../../../tests/relay";
import { keyedConnector, LAPTOP, NOTE, V1_KEYS } from "../../../tests/relay-v1";
import { COMPUTER_ONLY } from "../../relay-mcp/answers";
import { v1 as route } from "../../relay-mcp/api";
import { grantAsker } from "../../relay-mcp/asker";

// The memory's columns and the topics of facts and notes, through /v1/ with each kind of key over Ana's made-up space.
let connector: Awaited<ReturnType<typeof keyedConnector>>;
beforeEach(async () => { connector = await keyedConnector(); });

const v1 = (path: string, key?: string, body?: unknown) => connector.v1(path, key, body);
const all = (sql: string) => connector.spaces.sql(ANA).prepare(sql).all();
const columns = (body: unknown, key?: string) => v1("memory/columns", key, body);
const fact = (clientId: string, fields: Record<string, unknown>) =>
  ({ clientId, tags: ["ring"], sources: [`relay:note/${NOTE(1)}`], fields: { kind: "fact", text: "A made-up fact.", ...fields } });
const names = (answer: Record<string, unknown>) => (answer.columns as { name: string }[]).map(column => column.name);
const ids = (answer: Record<string, unknown>, list = "facts") => (answer[list] as { id: string }[]).map(found => found.id);

it("reads the two first columns, and adds, changes and removes a column, each change kept with its computer", async () => {
  expect(await v1("memory/columns", V1_KEYS.api)).toEqual({ status: 200, json: { removed: [], columns: [
    { name: "kind", type: "text", required: true, note: expect.stringContaining("decision") },
    { name: "text", type: "text", required: true, note: "The fact in one short sentence." }] } });
  const added = await columns({ add: [{ name: "mood", type: "text", note: "How the person felt." }] });
  expect([added.status, names(added.json)]).toEqual([200, ["kind", "text", "mood"]]);
  const stored = await v1("memory", undefined, { facts: [fact("mood-fact-0001", { mood: "calm" })] });
  expect(stored.status).toBe(201);
  const [{ id }] = stored.json.facts as { id: string }[];
  expect(ids((await v1("memory?mood=CALM")).json)).toEqual([id]);
  expect(((await v1("memory/fd7mm")).json.fields)).toEqual({ kind: "fact", text: "Sam makes the shell of the ring." });
  await columns({ change: [{ name: "mood", required: true, note: "One word." }] });
  expect((await v1("memory/columns", V1_KEYS.api)).json.columns).toContainEqual({ name: "mood", type: "text", required: true, note: "One word." });
  const removed = await columns({ remove: ["mood"] });
  expect([names(removed.json), removed.json.removed]).toEqual([["kind", "text"], [{ name: "mood", type: "text", removedAt: expect.any(Number) }]]);
  expect((await v1(`memory/${id}`)).json.fields).toMatchObject({ mood: "calm" });
  const { changes } = (await v1("memory/columns?changes=true", V1_KEYS.api)).json as { changes: { name: string; change: string; device: string }[] };
  expect(changes.map(change => [change.name, change.change, change.device])).toEqual([["mood", "remove", "Laptop"], ["mood", "change", "Laptop"],
    ["mood", "add", "Laptop"]]);
  // A removed name comes back only with its old type.
  expect((await columns({ add: [{ name: "mood", type: "text" }] })).status).toBe(200);
});

it("refuses a type change, a kept name, a 21st column and a removed name with a new type, and changes nothing", async () => {
  const before = all("SELECT * FROM relay_memory_columns");
  const refusals = [
    [{ add: [{ name: "kind", type: "number" }] }, "The column `kind` is there already. A column's type never changes."],
    [{ add: [{ name: "tags", type: "words" }] }, "`tags` is a name Relay Everything keeps. Pick another name."],
    [{ add: Array.from({ length: 19 }, (_, at) => ({ name: `c${at}`, type: "number" })) }, "The memory has at most 20 columns. Remove one first."],
    [{ add: [{ name: "Mood", type: "text" }] }, "`Mood` is not a column name: a lower-case letter, then letters, digits or _, up to 30."],
    [{ add: [{ name: "mood", type: "text" }], remove: ["mood"] }, "Name each column once in a change."],
    [{ remove: ["colour"] }, "No live column is named `colour`."],
  ] as const;
  for (const [change, why] of refusals) expect(await columns(change), why).toEqual({ status: 400, json: { error: "invalid_request", error_description: why } });
  expect((await columns({ change: [{ name: "kind", type: "number" }] })).status).toBe(400);
  await columns({ add: [{ name: "mah", type: "number" }] });
  await columns({ remove: ["mah"] });
  expect((await columns({ add: [{ name: "mah", type: "text" }] })).json.error_description)
    .toBe("The removed column `mah` was number: add it back as number, or pick another name.");
  expect((await columns({ add: Array.from({ length: 18 }, (_, at) => ({ name: `c${at}`, type: "number" })) })).status).toBe(200);
  expect(all("SELECT name FROM relay_memory_columns WHERE removed_at IS NULL")).toHaveLength(20);
  expect(before).toEqual(all("SELECT * FROM relay_memory_columns WHERE name IN ('kind', 'text')"));
});

it("checks each new fact's values against the columns, and stores none of a batch that has one wrong", async () => {
  await columns({ add: [{ name: "mah", type: "number" }, { name: "due", type: "date" }, { name: "done", type: "yes_no" },
    { name: "parts", type: "words" }] });
  const count = () => all("SELECT id FROM relay_memory").length;
  const facts = count();
  const refusals: [Record<string, unknown>, string][] = [
    [{ mah: "fifty" }, "`mah` takes a number."], [{ due: "next week" }, "`due` takes a day, as YYYY-MM-DD."],
    [{ done: "yes" }, "`done` takes true or false."], [{ parts: Array(21).fill("pcb") }, "`parts` takes a list of up to 20 short words."],
    [{ text: "" }, "`text` takes text of up to 400 characters."], [{ colour: "red" }, "no live column is named `colour`. Add it with POST /v1/memory/columns first."],
    [{ text: null }, "the required `text` is missing."],
  ];
  for (const [fields, why] of refusals) {
    const sent = await v1("memory", undefined, { facts: [fact("good-fact-0001", {}), fact("bad-fact-0001", fields)] });
    expect([sent.status, sent.json.error_description], why).toEqual([400, expect.stringContaining(why)]);
  }
  expect(count()).toBe(facts);
  const good = await v1("memory", undefined, { facts: [fact("good-fact-0002", { mah: 50, due: "2026-12-01", done: false, parts: ["pcb", "shell"] })] });
  expect(good.status).toBe(201);
  expect(ids((await v1("memory?done=false&parts=SHELL&mah=50")).json)).toEqual([(good.json.facts as { id: string }[])[0].id]);
  expect((await v1("memory?mah=lots")).json.error_description).toBe("`mah` takes a number.");
});

it("stores a resent fact once per computer, and keeps another computer's fact with the same clientId", async () => {
  const sent = (key: string) => v1("memory", key, { facts: [fact("same-id-0001", {})] });
  const laptop = await sent(V1_KEYS.computer);
  const [{ id }] = laptop.json.facts as { id: string }[];
  expect(laptop.status).toBe(201);
  expect((await sent(V1_KEYS.computer)).json).toEqual({ facts: [{ clientId: "same-id-0001", id, added: false }] });
  const desktop = await sent(V1_KEYS.desktop);
  expect(desktop.status).toBe(201);
  expect(desktop.json).toEqual({ facts: [{ clientId: "same-id-0001", id: expect.not.stringMatching(`^${id}$`), added: true }] });
  expect(all("SELECT device_id FROM relay_memory WHERE client_id = 'same-id-0001' ORDER BY device_id"))
    .toEqual([{ device_id: "d-desktop" }, { device_id: LAPTOP }]);
});

it("lets an API key and a connected app read the columns, and refuses each a change", async () => {
  const { SPACES, WORKBENCHES } = connector.spaces;
  const app = grantAsker({ SPACES, WORKBENCHES, RELAY_BUCKET: bucket as never, RELAY_WEBHOOKS: queue as never },
    { personId: ANA, adds: true, deviceId: "e-1", name: "Claude" })!;
  const ask = async (init: RequestInit = {}) => {
    const answer = await route(new Request("https://relay-mcp.example.com/v1/memory/columns", init), app);
    return { status: answer.status, json: await answer.json() as Record<string, unknown> };
  };
  const change = { add: [{ name: "mood", type: "text" }] };
  const refused = { status: 403, json: { error: "forbidden", error_description: COMPUTER_ONLY } };
  expect(await columns(change, V1_KEYS.api)).toEqual(refused);
  expect(await ask({ method: "POST", body: JSON.stringify(change) })).toEqual(refused);
  expect(names((await ask()).json)).toEqual(["kind", "text"]);
  expect(names((await v1("memory/columns", V1_KEYS.api)).json)).toEqual(["kind", "text"]);
});

it("turns a name or a filter made to look like SQL into a refusal or an empty search, and changes nothing", async () => {
  const tables = all("SELECT name FROM sqlite_master ORDER BY name");
  const notes = all("SELECT * FROM relay_notes");
  expect((await columns({ add: [{ name: "x; DROP TABLE relay_notes", type: "text" }] })).status).toBe(400);
  expect((await v1("memory", undefined, { sql: "DROP TABLE relay_notes" })).status).toBe(400);
  for (const path of ["memory?q=%27%20OR%201%3D1%20--", "memory?kind=%27%20OR%20%271%27%3D%271", "memory?tag=%25", "memory?source=%25",
    "notes?tag=%25"]) {
    expect(await v1(path), path).toMatchObject({ status: 200, json: { [path.startsWith("notes") ? "notes" : "facts"]: [] } });
  }
  expect((await v1("memory?a%27)%20OR%201%3D1--=x")).json.error_description).toMatch(/^No live column is named/);
  expect([all("SELECT name FROM sqlite_master ORDER BY name"), all("SELECT * FROM relay_notes")]).toEqual([tables, notes]);
});

it("adds and removes a note's topics as the computer, keeps each change, and leaves the note's words as they were", async () => {
  const [before] = all(`SELECT text, edited_at FROM relay_notes WHERE id = '${NOTE(2)}'`);
  expect(await v1(`notes/${NOTE(2)}/tags`, undefined, { add: ["#ring/charging", "cable"] }))
    .toEqual({ status: 200, json: { id: NOTE(2), tags: ["cable", "ring/charging"] } });
  const tagged = async (path: string) => ids((await v1(path)).json, "notes").sort();
  expect(await tagged("notes?tag=ring/charging")).toEqual([NOTE(2), NOTE(3)]);
  expect(await tagged("notes?tag=ring")).toEqual([NOTE(1), NOTE(2), NOTE(3)]);
  expect(await tagged("notes?tag=rin")).toEqual([]);
  expect(await tagged("notes?tag=ring&q=streetcar")).toEqual([NOTE(2)]);
  await v1(`notes/${NOTE(2)}/tags`, undefined, { remove: ["cable"] });
  expect(all(`SELECT text, edited_at FROM relay_notes WHERE id = '${NOTE(2)}'`)).toEqual([before]);
  expect(all("SELECT link, tag, change, device_id FROM relay_tag_changes ORDER BY seq")).toEqual([
    { link: `relay:note/${NOTE(2)}`, tag: "ring/charging", change: "add", device_id: LAPTOP },
    { link: `relay:note/${NOTE(2)}`, tag: "cable", change: "add", device_id: LAPTOP },
    { link: `relay:note/${NOTE(2)}`, tag: "cable", change: "remove", device_id: LAPTOP }]);
  expect((await v1(`notes/${NOTE(2)}/tags`, undefined, { add: ["Ring Charging"] })).status).toBe(400);
  expect((await v1("notes/a0000000-0000-4000-8000-000000000099/tags", undefined, { add: ["ring"] })).status).toBe(404);
});

it("keeps a fact's last topic, and finds a fact by its topic's parent", async () => {
  expect((await v1("memory/fd7mm/tags", undefined, { remove: ["sam", "ring"] })).json.error_description)
    .toBe("A fact keeps at least one tag: add its new topic before you remove the last.");
  expect((await v1("memory/fd7mm/tags", undefined, { add: ["people/sam"], remove: ["sam"] })).json).toEqual({ id: "fd7mm", tags: ["people/sam", "ring"] });
  expect(ids((await v1("memory?tag=people")).json)).toEqual(["fd7mm"]);
  expect(ids((await v1("memory?tag=ring")).json)).toEqual(["fc5kk", "fd7mm"]);
  expect((await v1("memory/fzzzz/tags", undefined, { add: ["ring"] })).status).toBe(404);
});

it("refuses a topic change from a phone, an API key or a turned-off key, and leaves the topics as they were", async () => {
  const tags = all("SELECT * FROM relay_note_tags ORDER BY note_id, tag");
  expect((await v1(`notes/${NOTE(1)}/tags`, V1_KEYS.api, { add: ["errands"] })).json.error_description).toBe(COMPUTER_ONLY);
  for (const key of [V1_KEYS.phone, V1_KEYS.off, V1_KEYS.chats]) {
    expect((await v1(`notes/${NOTE(1)}/tags`, key, { add: ["errands"] })).status).toBe(403);
    expect((await v1("memory/fd7mm/tags", key, { add: ["errands"] })).status).toBe(403);
  }
  expect(all("SELECT * FROM relay_note_tags ORDER BY note_id, tag")).toEqual(tags);
  expect(all("SELECT * FROM relay_tag_changes")).toEqual([]);
});

it("drops a note's topics when the note is deleted", async () => {
  connector.spaces.sql(ANA).prepare("DELETE FROM relay_notes WHERE id = ?").run(NOTE(3));
  expect(all("SELECT note_id FROM relay_note_tags")).toEqual([{ note_id: NOTE(1) }]);
});

it("takes an empty change, a note or required alone, and refuses a bad yes or no, a bad tag, a double replace and missing columns", async () => {
  expect((await columns({})).json.columns).toHaveLength(2);
  await columns({ add: [{ name: "done", type: "yes_no", note: "Whether it is done." }] });
  await columns({ change: [{ name: "done", note: "Done or not." }] });
  await columns({ change: [{ name: "done", required: false }] });
  expect((await v1("memory/columns")).json.columns).toContainEqual({ name: "done", type: "yes_no", required: false, note: "Done or not." });
  expect((await v1("memory?done=maybe")).json.error_description).toBe("`done` takes true or false.");
  expect(ids((await v1("memory?done=yes")).json)).toEqual([]);
  const refused = async (facts: unknown[]) => (await v1("memory", undefined, { facts })).json.error_description;
  expect(await refused([{ ...fact("bad-tag-0001", {}), tags: ["Battery Life"] }]))
    .toBe("The fact bad-tag-0001: `Battery Life` is not a tag: lower-case words, digits and dashes, a / before a part.");
  expect(await refused([{ ...fact("twice-0001", {}), replaces: ["fd7mm"] }, { ...fact("twice-0002", {}), replaces: ["fd7mm"] }]))
    .toBe("Two facts replace the same fact: one fact replaces it.");
  expect(await refused([{ ...fact("bare-0001", {}), fields: {} }])).toBe("The fact bare-0001: the required `kind`, `text` are missing.");
  expect((await v1("memory/fd7mm/tags", undefined, {})).json).toEqual({ id: "fd7mm", tags: ["ring", "sam"] });
});

it("takes a longer id when a short one is taken, and asks to send again when none is free", async () => {
  const zeros = vi.spyOn(crypto, "getRandomValues").mockImplementation(array => {
    new Uint8Array(array.buffer).fill(0);
    return array;
  });
  const taken = (id: string) => connector.spaces.sql(ANA).prepare(`INSERT INTO relay_memory (id, fields, sources, replaces, device_id, client_id,
    created_at) VALUES (?, '{}', '["relay:day/2026-11-04"]', '[]', ?, ?, 1)`).run(id, LAPTOP, `taken-${id}`);
  taken("faaaa");
  expect(ids((await v1("memory", undefined, { facts: [fact("long-id-0001", {})] })).json)).toEqual(["faaaaa"]);
  taken("faaaaaa");
  expect(await v1("memory", undefined, { facts: [fact("no-id-0001", {})] }))
    .toEqual({ status: 503, json: { error: "try_again", error_description: "No new fact id was free. Send the facts again." } });
  zeros.mockRestore();
});
