// Run with: node --test scripts/build-relay-web.test.mjs
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { deflateRawSync } from 'node:zlib';
import { buildWeb, fallbackFontPaths, FLUTTER, FONT_SOURCE, sha256, webCommit, zipName } from './build-relay-web.mjs';
import { unzip, zip } from './lib-zip.mjs';

const COMMIT = 'c'.repeat(40);
// The engine's list in main.dart.js, as dart2js writes it: one font joined to the base address, the rest as paths.
const ENGINE = `A.d(s.fontFallbackBaseUrl)+"roboto/v32/KFOm.woff2";B.n=[A.N("Noto Color Emoji 0","notocoloremoji/v32/Yq6P.0.woff2"),`
  + `A.N("Noto Sans SC 1",'notosanssc/v37/k3kC.1.woff2'),A.N("Noto Color Emoji 0","notocoloremoji/v32/Yq6P.0.woff2")]`;
const FONTS = ['notocoloremoji/v32/Yq6P.0.woff2', 'notosanssc/v37/k3kC.1.woff2', 'roboto/v32/KFOm.woff2'];
const BOOTSTRAP = "_flutter.loader.load({config: {fontFallbackBaseUrl: new URL('fallback-fonts/', document.baseURI).href}});";
const BUILT = { 'index.html': '<base href="/apps/relay/">', 'main.dart.js': `main();${ENGINE}`, 'flutter_bootstrap.js': BOOTSTRAP,
  'canvaskit/canvaskit.wasm': 'wasm' };
const fontData = path => Buffer.from(`wOF2${path}`);
const WITH_FONTS = { ...BUILT, ...Object.fromEntries(FONTS.map(path => [`fallback-fonts/${path}`, fontData(path).toString()])) };

/** A fonts server that answers each font at its Google address, and keeps each address asked. */
function fonts({ answer = url => fontData(url.slice(FONT_SOURCE.length)) } = {}) {
  const asked = [];
  return { asked, get: async url => { asked.push(url); return answer(url); } };
}

/** A repository with a Flutter that writes BUILT, and an old page in app/ that the build replaces. */
function place({ fails = false, built = BUILT } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'relay-web-'));
  mkdirSync(join(root, 'app/public/apps/relay'), { recursive: true });
  writeFileSync(join(root, 'app/public/apps/relay/old.js'), 'old');
  const calls = [];
  const run = (cmd, args, { cwd }) => {
    calls.push({ line: [cmd, ...args].join(' '), cwd });
    if (fails) throw new Error('exit 1');
    for (const [name, text] of Object.entries(built)) {
      mkdirSync(dirname(join(cwd, 'build/web', name)), { recursive: true });
      writeFileSync(join(cwd, 'build/web', name), text);
    }
  };
  return { root, calls, run };
}

test('builds the web entry for /apps/relay/ with no CDN, and puts it in place of the old page', async () => {
  const { root, calls, run } = place();
  assert.equal(await buildWeb({ root, run, get: fonts().get }), `result=ok page=${join(root, 'app/public/apps/relay')}`);
  assert.deepEqual(calls, [{ line: `flutter ${FLUTTER.join(' ')}`, cwd: join(root, 'mobile') }]);
  assert.match(calls[0].line, /-t lib\/main_web\.dart --base-href \/apps\/relay\/ --no-web-resources-cdn --release/);
  assert.equal(readFileSync(join(root, 'app/public/apps/relay/canvaskit/canvaskit.wasm'), 'utf8'), 'wasm');
  assert.equal(existsSync(join(root, 'app/public/apps/relay/old.js')), false, 'the old build goes');
});

test('--zip writes the release file named for its commit, with its SHA-256, and the zip holds every built file', async () => {
  const { root, run } = place();
  const out = join(root, 'out');
  const line = await buildWeb({ root, run, zipTo: out, commit: () => COMMIT, get: fonts().get });
  const data = readFileSync(join(out, zipName(COMMIT)));
  assert.equal(line, `result=ok page=${join(root, 'app/public/apps/relay')} zip=${join(out, `relay-web-${COMMIT}.zip`)} sha256=${sha256(data)}`);
  assert.equal(readFileSync(join(out, `relay-web-${COMMIT}.zip.sha256`), 'utf8'), `${sha256(data)}  relay-web-${COMMIT}.zip\n`);
  assert.deepEqual(Object.fromEntries(unzip(data).map(([name, file]) => [name, file.toString()])), WITH_FONTS);
});

test("the engine's fallback fonts come from the page's own folder, fetched once at their Google paths", async () => {
  const { root, run } = place();
  const server = fonts();
  assert.match(await buildWeb({ root, run, get: server.get }), /^result=ok/);
  assert.deepEqual(server.asked.sort(), FONTS.map(path => `https://fonts.gstatic.com/s/${path}`));
  for (const path of FONTS) {
    assert.equal(readFileSync(join(root, 'app/public/apps/relay/fallback-fonts', path), 'utf8'), fontData(path).toString(), path);
  }
  server.asked.length = 0;
  assert.match(await buildWeb({ root, run, get: server.get }), /^result=ok/);
  assert.deepEqual(server.asked, [], 'a kept font is not fetched again');
  assert.equal(readFileSync(join(root, 'app/public/apps/relay/fallback-fonts', FONTS[0]), 'utf8'), fontData(FONTS[0]).toString());
});

test('reads the fallback font list as the engine writes it, each path once', () => {
  assert.deepEqual(fallbackFontPaths(ENGINE), FONTS);
  assert.deepEqual(fallbackFontPaths('"https://example.com/a.woff2" "notes/v1.txt"'), []);
});

test("the page's own bootstrap points the engine at its fallback fonts, and starts no service worker", () => {
  const bootstrap = readFileSync(new URL('../mobile/web/flutter_bootstrap.js', import.meta.url), 'utf8');
  assert.match(bootstrap, /\{\{flutter_js\}\}/);
  assert.match(bootstrap, /\{\{flutter_build_config\}\}/);
  assert.match(bootstrap, /fontFallbackBaseUrl: new URL\('fallback-fonts\/', document\.baseURI\)\.href/);
  assert.doesNotMatch(bootstrap, /serviceWorker/);
  assert.doesNotMatch(bootstrap, /gstatic|googleapis/);
});

test('a missing font, an answer that is no font, no font list or no bootstrap stops the build and leaves the old page',
  async () => {
    const cases = [
      ['offline', {}, { answer: () => { throw new Error('offline'); } }],
      ['error page', {}, { answer: () => Buffer.from('<html>Not found</html>') }],
      ['no list', { built: { ...BUILT, 'main.dart.js': 'main()' } }, {}],
      ['old bootstrap', { built: { ...BUILT, 'flutter_bootstrap.js': '_flutter.loader.load({});' } }, {}],
    ];
    for (const [what, placed, served] of cases) {
      const { root, run } = place(placed);
      assert.equal(await buildWeb({ root, run, get: fonts(served).get }), 'result=failed step=fonts', what);
      assert.equal(readFileSync(join(root, 'app/public/apps/relay/old.js'), 'utf8'), 'old', what);
    }
  });

test('a failed Flutter build names its step and leaves the old page', async () => {
  const { root, run } = place({ fails: true });
  assert.equal(await buildWeb({ root, run }), 'result=failed step=flutter');
  assert.equal(readFileSync(join(root, 'app/public/apps/relay/old.js'), 'utf8'), 'old');
});

test('the page\'s commit is the newest that changed mobile/', () => {
  assert.match(webCommit(), /^[0-9a-f]{40}$/);
});

test('unzip refuses a name outside its folder, an unknown compression, a damaged file and a file that is no zip', () => {
  const plain = zip([['a.txt', Buffer.from('hello')]]);
  // The central directory starts after the one local header, its name and its deflated bytes.
  const central = 30 + 'a.txt'.length + deflateRawSync(Buffer.from('hello')).length;
  for (const name of ['../a', '/etc/a', 'a/../../b', 'a\\b']) assert.throws(() => unzip(zip([[name, Buffer.from('x')]])), /outside its folder/, name);
  const method = Buffer.from(plain);
  method.writeUInt16LE(0, central + 10);
  assert.throws(() => unzip(method), /compression/);
  const damaged = Buffer.from(plain);
  damaged.writeUInt32LE(1, central + 16);
  assert.throws(() => unzip(damaged), /damaged/);
  assert.throws(() => unzip(Buffer.from('no zip here')), /not a zip/);
  assert.throws(() => unzip(Buffer.concat([Buffer.alloc(4), plain.subarray(central)])), /broken/);
});
