// Opens the built note editor page in Chromium and talks to it as the app does.
// CHROME may name a Chromium to use; else Playwright's own, from `npx playwright-core install chromium`.
import { chromium } from 'playwright-core';
import { pathToFileURL } from 'node:url';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const built = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'assets', 'editor');

export const light = {
  paper: '#F7F8F4', card: '#FFFFFF', line: '#E3E6DF', ink: '#121614', muted: '#5E6660', accent: '#0E7A5A',
  onAccent: '#FFFFFF', accentText: '#0E7A5A', accentSoft: '#E1F2EA', spark: '#F5A524', danger: '#C9302C',
  select: 'rgba(14, 122, 90, 0.25)', 'hl-purple': 'rgba(155, 107, 224, 0.3)', 'hl-pink': 'rgba(229, 80, 140, 0.3)',
  'hl-orange': 'rgba(245, 165, 36, 0.3)', 'hl-green': 'rgba(47, 179, 122, 0.3)', 'hl-blue': 'rgba(59, 130, 246, 0.3)',
  scheme: 'light',
};

export const dark = {
  paper: '#0C110F', card: '#161D1A', line: '#26302B', ink: '#ECF3EE', muted: '#9AA8A0', accent: '#4CC79A',
  onAccent: '#06281A', accentText: '#4CC79A', accentSoft: '#133328', spark: '#FFC24D', danger: '#FF8A80',
  select: 'rgba(76, 199, 154, 0.35)', 'hl-purple': 'rgba(155, 107, 224, 0.45)', 'hl-pink': 'rgba(229, 80, 140, 0.45)',
  'hl-orange': 'rgba(245, 165, 36, 0.45)', 'hl-green': 'rgba(47, 179, 122, 0.45)', 'hl-blue': 'rgba(59, 130, 246, 0.45)',
  scheme: 'dark',
};

// Builders for the note's document JSON.
export const t = (text, ...marks) => marks.length
  ? { type: 'text', text, marks: marks.map(m => typeof m === 'string' ? { type: m } : m) } : { type: 'text', text };
export const p = (text, indent = 0) => ({ type: 'paragraph', attrs: { indent },
  ...(text ? { content: typeof text === 'string' ? [t(text)] : text } : {}) });
export const h = (level, text, indent = 0) => ({ type: 'heading', attrs: { level, indent, title: false }, content: [t(text)] });
export const item = (kind, lines, { indent = 0, checked = false } = {}) => ({
  type: 'item', attrs: { kind, checked, indent },
  content: (Array.isArray(lines) ? lines : [lines]).map(line => p(line)),
});
export const quote = (text, indent = 0) => ({ type: 'blockquote', attrs: { indent }, content: [t(text)] });
export const code = text => ({ type: 'codeBlock', content: [t(text)] });
export const file = (id, name = id) => ({ type: 'attachment', attrs: { id, name } });
export const table = rows => ({ type: 'table', attrs: { source: null }, content: rows.map((row, r) => ({
  type: 'tableRow',
  content: row.map(cell => ({ type: r ? 'tableCell' : 'tableHeader', content: [p(cell || null)] })),
})) });
export const doc = (...content) => ({ type: 'doc', content });
export const link = (href, auto = false) => ({ type: 'link', attrs: { href, auto } });
export const hl = colour => ({ type: 'highlight', attrs: { colour } });

export const sample = doc(
  { type: 'heading', attrs: { level: 1, indent: 0, title: true }, content: [t('Weekend plan')] },
  p([t('Call the hall about '), t('the booking', 'bold'), t(', '), t('kindly', 'italic'), t(', '), t('today', 'underline'),
    t(', '), t('not Sunday', 'strike'), t(', '), t('before noon', hl('green')), t('. See '),
    t('the menu', link('https://example.com/menu')), t(' or www.relay.example/hall.')]),
  item('task', 'Book the van', { checked: true }),
  item('task', ['Buy oat milk', 'Why: the shop shuts at six']),
  h(2, 'To pack'),
  item('numbered', 'Tape and scissors'),
  item('numbered', 'The blue folder'),
  item('numbered', 'Its labels', { indent: 1 }),
  item('bullet', 'Spare pens', { indent: 1 }),
  item('dashed', 'Snacks'),
  quote('Pack light.'),
  code('van: 9:00\nhall: 10:00'),
  table([['Who', 'What'], ['Ana', 'Chairs']]),
  file('pic1', 'hall.png'),
  p(''),
);

export async function launch() {
  return chromium.launch({
    executablePath: process.env.CHROME || undefined,
    args: ['--use-angle=swiftshader', '--disable-gpu'],
  });
}

/// A page of the editor in [browser], as a phone (390 by 760, touch) unless [desktop].
export async function openPage(browser, { desktop = false } = {}) {
  const context = await browser.newContext(desktop
    ? { viewport: { width: 1000, height: 800 } }
    : { viewport: { width: 390, height: 760 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error));
  await page.goto(pathToFileURL(join(built, 'index.html')).href);
  await page.waitForFunction(() => window.__sent?.some(m => m.is === 'boot'));
  const api = {
    page,
    errors,
    close: () => context.close(),
    send: message => page.evaluate(m => window.relayReceive(m), message),
    run: (action, value) => page.evaluate(([a, v]) => window.relayReceive({ do: 'run', action: a, value: v }), [action, value]),
    sent: () => page.evaluate(() => window.__sent),
    clearSent: () => page.evaluate(() => { window.__sent.length = 0; }),
    json: () => page.evaluate(() => window.editor.getJSON()),
    state: () => page.evaluate(() => window.__sent.filter(m => m.is === 'state').at(-1)),
    texts: () => page.evaluate(() => {
      const lines = [];
      window.editor.state.doc.forEach(node => lines.push(`${node.type.name}${node.attrs.kind ? `:${node.attrs.kind}` : ''}${node.attrs.indent ? `@${node.attrs.indent}` : ''}|${node.textContent}`));
      return lines;
    }),
    /// Loads [content] and waits for `ready`.
    async load(content, options = {}) {
      await page.evaluate(() => { window.__sent.length = 0; });
      await page.evaluate(m => window.relayReceive(m), {
        do: 'load', doc: content, theme: light, editable: true, fromElsewhere: false, focus: false, bottom: 0, keys: false,
        appKeys: [], mac: false, placeholder: 'Start writing', highlight: 'purple', head: { date: '', above: [], below: [] },
        files: {}, ...options,
      });
      await page.waitForFunction(() => window.__sent.some(m => m.is === 'ready'));
    },
    /// The next `changed` message, once it comes.
    async changed() {
      await page.waitForFunction(() => window.__sent.some(m => m.is === 'changed'));
      return page.evaluate(() => window.__sent.filter(m => m.is === 'changed').at(-1));
    },
    /// Puts the caret [offset] letters into the words of the textblock holding [text].
    async caret(text, offset = text.length, end = offset) {
      await page.evaluate(([words, at, to]) => {
        const editor = window.editor;
        let pos = null;
        editor.state.doc.descendants((node, p) => {
          if (pos === null && node.isTextblock && node.textContent.includes(words)) {
            pos = p + 1 + node.textContent.indexOf(words);
            return false;
          }
          return pos === null;
        });
        if (pos === null) throw new Error(`no line holds ${words}`);
        window.relayReceive({ do: 'run', action: 'focus' });
        editor.commands.setTextSelection({ from: pos + at, to: pos + to });
      }, [text, offset, end]);
      await page.evaluate(() => new Promise(r => requestAnimationFrame(() => r())));
    },
  };
  return api;
}
