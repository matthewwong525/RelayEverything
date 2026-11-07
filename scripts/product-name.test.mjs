// Run with: node --test scripts/product-name.test.mjs
// A bare "Relay" in a file people read fails with its file and line; lower-case code names and commands pass.
import assert from 'node:assert/strict';
import test from 'node:test';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const BARE = /\bRelay\b(?!\s+Everything\b)/g;

// Phrases that keep a bare "Relay" on purpose, each one a literal.
const ALLOWED = [];

// The files people read. A folder takes every file under it; `*.md` in a folder takes only that kind.
const PLACES = [
  'site/src/content',
  'site/astro.config.mjs',
  'site/public/webhooks',
  'mobile/lib',
  'mobile/ios/Runner/Info.plist',
  'mobile/android/app/src/main/AndroidManifest.xml',
  'app/src/apps/relay/app.json',
  'app/worker/relay-mcp/auth.ts',
  'app/worker/relay-mcp/index.ts',
  'app/worker/relay-mcp/tools.ts',
  'app/vite.config.ts',
  '.claude-plugin/marketplace.json',
  'plugin/.claude-plugin/plugin.json',
  'plugin/bin',
  'plugin/hooks/hooks.json',
  'plugin/lib/state.mjs',
  'plugin/skills',
  'scripts/relay-mcp-trial.mjs',
  'self-host/SETUP.md',
  'wiki',
];
const SKIP_DIRS = new Set(['node_modules', '.git', 'vendor', 'dist', 'build', '.dart_tool', '.astro', '.wrangler']);

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      if (!SKIP_DIRS.has(name)) walk(path, out);
    } else out.push(path);
  }
  return out;
}

/** Every file people read, as paths from the repository root. */
export function userFacingFiles(root = ROOT) {
  const files = new Set();
  for (const place of PLACES) {
    const path = join(root, place);
    if (!existsSync(path)) continue;
    for (const file of statSync(path).isDirectory() ? walk(path) : [path]) files.add(relative(root, file));
  }
  // The server page's screens, not their tests.
  const page = join(root, 'app/src/apps/relay');
  if (existsSync(page)) {
    for (const name of readdirSync(page)) {
      if (name.endsWith('.tsx') && !name.endsWith('.test.tsx')) files.add(`app/src/apps/relay/${name}`);
    }
  }
  // Every README, but not copied libraries or the OpenSpec archive.
  for (const file of walk(root)) {
    const path = relative(root, file);
    if (path.endsWith('README.md') && !path.startsWith('openspec/') && !path.startsWith('.agents/')
      && !path.startsWith('.claude/')) files.add(path);
  }
  return [...files].filter((path) => !/\.(test|spec)\.[a-z]+$/.test(path) && kind(path) !== null).sort();
}

/** How a file is read: its prose, its markup, or only the quoted strings of its code. */
function kind(path) {
  if (/\.(md|mdx)$/.test(path)) return 'markdown';
  if (/\.(xml|plist|html)$/.test(path)) return 'markup';
  if (/\.json$/.test(path)) return 'all';
  if (/\.tsx$/.test(path)) return 'jsx';
  if (/\.(ts|mjs|js|cjs)$/.test(path)) return 'js';
  if (/\.dart$/.test(path)) return 'dart';
  return null;
}

/** Blanks every character but newlines, so line numbers stay. */
const blank = (text) => text.replace(/[^\n]/g, ' ');

// `code` is the source with comments blanked; `strings` keeps only string contents. Newlines stay in both.
export function scanCode(source, { dart = false } = {}) {
  let code = '';
  let strings = '';
  let i = 0;
  let last = ''; // the last non-space code character, to tell a regular expression from a division
  const keep = (text, isString) => {
    code += text;
    strings += isString ? text : blank(text);
  };
  while (i < source.length) {
    const c = source[i];
    const next = source[i + 1];
    if (c === '/' && next === '/') {
      const end = source.indexOf('\n', i);
      const stop = end === -1 ? source.length : end;
      const text = blank(source.slice(i, stop));
      code += text;
      strings += text;
      i = stop;
    } else if (c === '/' && next === '*') {
      const end = source.indexOf('*/', i + 2);
      const stop = end === -1 ? source.length : end + 2;
      const text = blank(source.slice(i, stop));
      code += text;
      strings += text;
      i = stop;
    } else if (!dart && c === '/' && (last === '' || '(,=:[!&|?{};+-*%<>~^'.includes(last))) {
      let j = i + 1;
      let inClass = false;
      while (j < source.length && source[j] !== '\n') {
        if (source[j] === '\\') j += 1;
        else if (source[j] === '[') inClass = true;
        else if (source[j] === ']') inClass = false;
        else if (source[j] === '/' && !inClass) break;
        j += 1;
      }
      keep(source.slice(i, j + 1), false);
      last = '/';
      i = j + 1;
    } else if (c === '"' || c === "'" || c === '`') {
      const triple = dart && source.startsWith(c.repeat(3), i);
      const quote = triple ? c.repeat(3) : c;
      const raw = dart && source[i - 1] === 'r';
      let j = i + quote.length;
      while (j < source.length && !source.startsWith(quote, j)) {
        if (source[j] === '\\' && !raw) j += 1;
        else if (!triple && c !== '`' && source[j] === '\n') break;
        j += 1;
      }
      keep(quote, false);
      keep(source.slice(i + quote.length, j), true);
      keep(source.slice(j, j + quote.length), false);
      last = c;
      i = j + quote.length;
    } else {
      keep(c, false);
      if (!/\s/.test(c)) last = c;
      i += 1;
    }
  }
  return { code, strings };
}

/** The text of a file that a person reads, with every newline kept. */
export function readable(path, text) {
  switch (kind(path)) {
    case 'markdown':
      return text
        .replace(/^(```|~~~)[^\n]*\n[\s\S]*?^\1[^\n]*$/gm, blank)
        .replace(/<!--[\s\S]*?-->/g, blank)
        .replace(/`[^`\n]+`/g, blank)
        .replace(/\]\([^)\n]*\)/g, blank);
    case 'markup':
      return text.replace(/<!--[\s\S]*?-->/g, blank);
    case 'jsx':
      return scanCode(text).code;
    case 'js':
      return scanCode(text).strings;
    case 'dart':
      return scanCode(text, { dart: true }).strings;
    default:
      return text;
  }
}

/** Each bare "Relay" in a file people read, as `path:line: text`. */
export function bareNames(path, text) {
  let seen = readable(path, text);
  for (const phrase of ALLOWED) seen = seen.split(phrase).join(blank(phrase));
  const lines = text.split('\n');
  const found = [];
  for (const match of seen.matchAll(BARE)) {
    const line = seen.slice(0, match.index).split('\n').length;
    found.push(`${path}:${line}: ${lines[line - 1].trim()}`);
  }
  return found;
}

test('a bare Relay in a docs page fails, with its file and line', () => {
  const page = '# Start\n\nOpen your Relay page.\n';
  assert.deepEqual(bareNames('site/src/content/docs/start.md', page), ['site/src/content/docs/start.md:3: Open your Relay page.']);
  assert.equal(bareNames('wiki/a.md', "Relay's page").length, 1);
});

test('Relay Everything, commands, variables and paths pass', () => {
  const page = [
    'Open your Relay Everything page, or your Relay',
    'Everything server.',
    'Type `/relay:saving off`, or /relay:saving on, or set RELAY_SAVE=0.',
    'The page is at https://<your-relay-server>/apps/relay/, in [RelayEverything](https://github.com/x/RelayEverything).',
  ].join('\n');
  assert.deepEqual(bareNames('site/src/content/docs/a.md', page), []);
});

test('in code, only a quoted string counts: names and comments pass', () => {
  const dart = [
    '/// The one Relay.',
    'class RelayController extends Relay {',
    "  final title = 'Relay Everything'; // not Relay",
    "  final bad = 'Open your Relay page';",
    '}',
  ].join('\n');
  assert.deepEqual(bareNames('mobile/lib/a.dart', dart), ["mobile/lib/a.dart:4: final bad = 'Open your Relay page';"]);
  const js = "// Relay's tool\nconst re = /it's/; const said = `Saved to Relay: ${title}`; const url = 'https://x/y';";
  assert.equal(bareNames('plugin/bin/a.mjs', js).length, 1);
  assert.deepEqual(bareNames('plugin/bin/a.mjs', "const env = process.env.RELAY_SAVE; // Relay"), []);
});

test('in a screen, the text between tags counts too', () => {
  const tsx = '// Relay\'s page\nexport const A = () => <h1>Relay</h1>;\nexport const B = () => <h1>Relay Everything</h1>;';
  assert.deepEqual(bareNames('app/src/apps/relay/A.tsx', tsx), ['app/src/apps/relay/A.tsx:2: export const A = () => <h1>Relay</h1>;']);
});

test('markup comments pass, markup text fails', () => {
  const xml = '<!-- Why Relay asks. -->\n<application android:label="Relay"/>';
  assert.deepEqual(bareNames('mobile/a/AndroidManifest.xml', xml), ['mobile/a/AndroidManifest.xml:2: <application android:label="Relay"/>']);
});

test('every file people read names the product Relay Everything', () => {
  const files = userFacingFiles();
  assert.ok(files.includes('site/astro.config.mjs') && files.includes('mobile/ios/Runner/Info.plist'), 'the file list is empty');
  const found = files.flatMap((path) => bareNames(path, readFileSync(join(ROOT, path), 'utf8')));
  assert.deepEqual(found, [], `Say Relay Everything, not Relay, in:\n${found.join('\n')}`);
});
