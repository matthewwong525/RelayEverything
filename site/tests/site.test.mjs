// Checks the built site in dist/: `npm test` builds it first.
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { sidebar } from '../sidebar.mjs';

const site = fileURLToPath(new URL('..', import.meta.url));
const dist = join(site, 'dist');
const walk = dir => readdirSync(dir, { withFileTypes: true, recursive: true })
  .filter(entry => entry.isFile()).map(entry => join(entry.parentPath, entry.name));
const pages = walk(dist).filter(file => file.endsWith('.html'));
const html = new Map(pages.map(file => [file, readFileSync(file, 'utf8')]));

/** The built file an address opens, or null. */
function fileFor(pathname) {
  const path = join(dist, decodeURIComponent(pathname));
  for (const file of [path, join(path, 'index.html')]) if (existsSync(file) && statSync(file).isFile()) return file;
  return null;
}

/** Why a site address doesn't open, or null when it does: its page must exist, and its #anchor on that page. */
function broken(href, from) {
  const url = new URL(href, `https://site/${relative(dist, from).replace(/index\.html$/, '')}`);
  const file = fileFor(url.pathname);
  if (!file) return `no page at ${url.pathname}`;
  const id = decodeURIComponent(url.hash.slice(1));
  if (id && !html.get(file)?.includes(`id="${id}"`)) return `no #${id} on ${url.pathname}`;
  return null;
}

const entries = groups => groups.flatMap(group => group.items ?? [group]);
const addressOf = entry => typeof entry === 'string' ? `/${entry}/` : entry.link ?? `/${entry.slug}/`;

test('the site is built', () => {
  assert.ok(html.has(join(dist, 'index.html')), 'run `npm run build` first');
});

test('every menu entry opens a built page', () => {
  const problems = entries(sidebar).map(entry => broken(addressOf(entry), join(dist, 'index.html'))).filter(Boolean);
  assert.deepEqual(problems, []);
});

// The Markdown a person edits, by the slug of the page it builds.
const docs = join(site, 'src/content/docs');
const sources = new Map(walk(docs).filter(file => /\.mdx?$/.test(file))
  .map(file => [relative(docs, file).replace(/\.mdx?$/, '').replace(/(^|\/)index$/, ''), readFileSync(file, 'utf8')]));
const GAP = '[LEGAL-TODO';
const DRAFT = ':::caution[Draft: not in force]';
const opensAsDraft = text => text.replace(/^---\n[\s\S]*?\n---\n/, '').trimStart().startsWith(DRAFT);
const drafts = new Set([...sources].filter(([, text]) => opensAsDraft(text)).map(([slug]) => join(dist, slug, 'index.html')));
const slugOf = address => new URL(address, 'https://site/').pathname.replace(/^\/|\/$/g, '');

// Addresses that the change texting-toll-free-pages adds. terms-draft.md copies its Texting terms word for word, links
// and all, so a draft may link to them until they are built. A test below fails once they are, and this list goes then.
const coming = ['/terms/', '/texting/', '/texting/#the-replies', '/privacy/#texting'];

test('every link inside the site opens a page', () => {
  const problems = [...html].flatMap(([file, text]) => [...text.matchAll(/href="([^"]*)"/g)]
    .map(([, href]) => href.replaceAll('&amp;', '&'))
    .filter(href => !/^[a-z]+:|^\/\//i.test(href))
    .filter(href => !(drafts.has(file) && coming.includes(decodeURI(new URL(href, `https://site/${relative(dist, file)}`).href.slice('https://site'.length)))))
    .map(href => broken(href, file) && `${relative(dist, file)}: ${href} (${broken(href, file)})`))
    .filter(Boolean);
  assert.deepEqual(problems, []);
});

test('a draft links only to addresses still to come, so the list of them stays short', () => {
  assert.deepEqual(coming.filter(address => !broken(address, join(dist, 'index.html'))), [],
    'these are built now: take them out of `coming` in site/tests/site.test.mjs');
});

// A legal page with a gap is a draft: it opens with the draft box, and no menu entry or home page link reaches it.
test('no page with a [LEGAL-TODO gap is in the menu or linked from the home page, and each one opens as a draft', () => {
  const home = [...html.get(join(dist, 'index.html')).matchAll(/href="([^"]*)"/g)].map(([, href]) => href)
    .filter(href => !/^[a-z]+:|^\/\//i.test(href)).map(slugOf);
  const shown = new Set([...entries(sidebar).map(entry => slugOf(addressOf(entry))), ...home]);
  const withGaps = [...sources].filter(([, text]) => text.includes(GAP));
  assert.ok(withGaps.length, 'no page holds a gap: the draft check reads no draft');
  assert.deepEqual(withGaps.filter(([slug]) => shown.has(slug)).map(([slug]) => `${slug}: has a gap, and the menu or the home page links it`), []);
  assert.deepEqual(withGaps.filter(([, text]) => !opensAsDraft(text)).map(([slug]) => `${slug}: has a gap, and does not open with ${DRAFT}`), []);
});

test('the fuller terms keep the Terms page\'s Texting terms word for word', t => {
  const part = text => /^## Texting terms\n[\s\S]*?(?=^## )/m.exec(text)?.[0];
  assert.ok(part(sources.get('terms-draft')), 'terms-draft.md has no ## Texting terms part');
  if (!sources.has('terms')) return t.skip('no terms.md yet: it comes with the change texting-toll-free-pages');
  assert.equal(part(sources.get('terms-draft')), part(sources.get('terms')));
});

test('no page names a private address', () => {
  const sources = walk(join(site, 'src')).filter(file => /\.(md|mdx|astro|ts|css)$/.test(file));
  const named = [...pages, ...sources].filter(file => {
    const text = readFileSync(file, 'utf8');
    const hosts = [...text.matchAll(/([a-z0-9-]+)\.[a-z0-9-]+\.workers\.dev/gi)].map(([, name]) => name);
    return /cloudflareaccess\.com/i.test(text) || hosts.some(name => !['relay', 'relay-staging'].includes(name));
  });
  assert.deepEqual(named.map(file => relative(site, file)), []);
});

test('the home page links to both apps, the code and the docs', () => {
  const home = html.get(join(dist, 'index.html'));
  for (const link of ['https://github.com/matthewwong525/RelayEverything/releases/latest', 'https://apps.apple.com/app/testflight/id899247664',
    'https://github.com/matthewwong525/RelayEverything/tree/main/mobile', 'start/what-you-need/']) assert.ok(home.includes(`href="${link}"`), link);
  assert.match(home, />\s*Get started\s*</);
});
