// The person's topics, from this computer's copy of their knowledge web: each `topics/<name>.md`, or
// `topics/<name>/README.md` for a topic that grew into a folder, with its frontmatter summary and the topics it links.
// Plain file reads, no git and no network, so a hook stays well within its time limit.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, posix, relative, sep } from 'node:path';

/** A topic's name, as the server takes a tag: lower-case words, digits and dashes, a / before a part. */
export const TOPIC = /^[a-z0-9]+(?:-[a-z0-9]+)*(?:\/[a-z0-9]+(?:-[a-z0-9]+)*)*$/;
/** The most topics a message adds, because more would crowd it. */
export const MOST_MATCHES = 3;
/** The shortest message word that may start a topic's name. */
const WEAK_LETTERS = 4;

/** The topic a page's path names, such as `topics/bike/charging.md` → `bike/charging`, or null for another file. */
function topicOf(path) {
  const parts = path.split('/');
  if (parts[0] !== 'topics' || parts.length < 2 || !parts.at(-1).endsWith('.md')) return null;
  const name = (parts.at(-1) === 'README.md' ? parts.slice(1, -1) : [...parts.slice(1, -1), parts.at(-1).slice(0, -3)]).join('/');
  return TOPIC.test(name) ? name : null;
}

/** Each topic's name and its page's path in the copy, a folder's `README.md` before a page beside it. */
export function topicPages(dir) {
  const root = join(dir, 'topics');
  if (!existsSync(root)) return new Map();
  const pages = new Map();
  let entries;
  try {
    entries = readdirSync(root, { withFileTypes: true, recursive: true });
  } catch {
    return pages;
  }
  for (const entry of entries) {
    if (!entry.isFile()) continue;
    const path = relative(dir, join(entry.parentPath ?? entry.path, entry.name)).split(sep).join('/');
    const name = topicOf(path);
    if (name && (!pages.has(name) || path.endsWith('/README.md'))) pages.set(name, path);
  }
  return pages;
}

/** A page's frontmatter, as plain `key: value` lines, and its text after it. */
export function frontmatter(text) {
  const found = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(text);
  if (!found) return { fields: {}, body: text };
  const fields = {};
  for (const line of found[1].split(/\r?\n/)) {
    const pair = /^([A-Za-z][\w-]*):\s*(.*)$/.exec(line);
    if (pair) fields[pair[1]] = pair[2].trim().replace(/^(["'])(.*)\1$/, '$2');
  }
  return { fields, body: text.slice(found[0].length) };
}

/** The topics a page links, by its Markdown links to other pages in `topics/`. */
function linksOf(body, path, pages) {
  const names = new Set();
  for (const [, target] of body.matchAll(/\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/g)) {
    if (/^[a-z][\w+.-]*:/i.test(target) || target.startsWith('#')) continue;
    const file = decodeURI(target.split('#')[0]);
    const full = file.startsWith('/') ? file.slice(1) : posix.normalize(posix.join(posix.dirname(path), file));
    const name = topicOf(full) ?? topicOf(posix.join(full, 'README.md'));
    if (name && pages.has(name) && pages.get(name) !== path) names.add(name);
  }
  return [...names].sort();
}

/** One topic's page: `{ name, path, title, summary, updated, text, links }`, or null when the copy has no page for it. */
export function readTopic(dir, name, pages = topicPages(dir)) {
  const path = pages.get(name);
  if (!path) return null;
  let text;
  try {
    text = readFileSync(join(dir, path), 'utf8');
  } catch {
    return null;
  }
  const { fields, body } = frontmatter(text);
  return { name, path, title: fields.title ?? null, summary: fields.summary || null, updated: fields.updated ?? null, text,
    links: linksOf(body, path, pages) };
}

/** The topics whose pages link this one: a scan of every page in the copy. */
export function linksIn(dir, name, pages = topicPages(dir)) {
  return [...pages.keys()].filter(other => other !== name && readTopic(dir, other, pages)?.links.includes(name)).sort();
}

/** The top-level topics, each `{ name, summary, updated }`, by name. */
export function topLevel(dir) {
  const pages = topicPages(dir);
  return [...pages.keys()].filter(name => !name.includes('/')).sort()
    .map(name => readTopic(dir, name, pages)).filter(Boolean)
    .map(({ name, summary, updated }) => ({ name, summary, updated }));
}

/** A project's folder name as a topic name: `WongOS` → `wongos`, `my_app` → `my-app`. */
export const topicName = project => String(project ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');

/** The topic named as the project: a whole name, else a last part, such as `work/wongos`. */
export function projectTopic(dir, project) {
  const wanted = topicName(project);
  if (!wanted) return null;
  const pages = topicPages(dir);
  const name = pages.has(wanted) ? wanted : [...pages.keys()].sort().find(other => other.split('/').at(-1) === wanted);
  return name ? readTopic(dir, name, pages) : null;
}

/** A text's words, lower-case letters and digits. */
export const wordsOf = text => String(text ?? '').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);

/** Whether `words` holds `phrase` as words in a row. */
function holds(words, phrase) {
  for (let at = 0; at + phrase.length <= words.length; at++) if (phrase.every((word, index) => words[at + index] === word)) return true;
  return false;
}

/**
 * The topics a message names, at most MOST_MATCHES, each `{ name, clear }`. A clear match holds the topic's whole
 * name (with `/` and `-` as spaces) or its last part as words; a weak one has a word of 4 or more letters that starts
 * a word of the topic's name. Clear matches come first, the longest name first; a weak match inside a clear one is left
 * out, because the clear one's page leads to it.
 */
export function matchTopics(names, message) {
  const words = wordsOf(message);
  if (!words.length) return [];
  const long = [...new Set(words.filter(word => word.length >= WEAK_LETTERS))];
  const clear = [];
  const weak = [];
  for (const name of names) {
    const parts = name.split('/');
    if (holds(words, wordsOf(name)) || holds(words, wordsOf(parts.at(-1)))) clear.push(name);
    else if (wordsOf(name).some(part => long.some(word => part.startsWith(word)))) weak.push(name);
  }
  clear.sort((a, b) => wordsOf(b).length - wordsOf(a).length || a.localeCompare(b));
  const inside = name => clear.some(found => name.startsWith(`${found}/`));
  return [...clear.map(name => ({ name, clear: true })), ...weak.filter(name => !inside(name)).sort().map(name => ({ name, clear: false }))]
    .slice(0, MOST_MATCHES);
}
