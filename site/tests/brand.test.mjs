// Checks the built site wears the Relay Everything brand (wiki/brand.md): `npm test` builds it first.
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const dist = fileURLToPath(new URL('../dist', import.meta.url));
const files = readdirSync(dist, { withFileTypes: true, recursive: true })
  .filter(entry => entry.isFile()).map(entry => join(entry.parentPath, entry.name));
// Every style the site ships: its CSS files and the <style> blocks inside its pages.
const styles = [
  ...files.filter(file => file.endsWith('.css')).map(file => [relative(dist, file), readFileSync(file, 'utf8')]),
  ...files.filter(file => file.endsWith('.html')).flatMap(file => [...readFileSync(file, 'utf8')
    .matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map(([, css]) => [relative(dist, file), css])),
];

test('the built site has styles to check', () => {
  assert.ok(styles.length > 0, 'run `npm run build` first');
});

test('no style keeps the old blue', () => {
  const old = styles.filter(([, css]) => /#3b5bdb/i.test(css)).map(([file]) => file);
  assert.deepEqual(old, []);
});

test('every @font-face loads its font from this site', () => {
  const faces = styles.flatMap(([file, css]) => [...css.matchAll(/@font-face\s*{[^}]*}/g)].map(([face]) => [file, face]));
  assert.ok(faces.some(([, face]) => /font-family:\s*['"]?Inter/.test(face)), 'Inter has an @font-face');
  const outside = faces.flatMap(([file, face]) => [...face.matchAll(/url\(\s*['"]?([^'")]+)/g)]
    .map(([, url]) => url).filter(url => /^(?:[a-z]+:)?\/\//i.test(url)).map(url => `${file}: ${url}`));
  assert.deepEqual(outside, []);
});

test('Inter and its license are served from the site', () => {
  assert.ok(existsSync(join(dist, 'fonts/InterVariable.woff2')), 'fonts/InterVariable.woff2');
  assert.match(readFileSync(join(dist, 'fonts/OFL.txt'), 'utf8'), /SIL Open Font License/);
});

test('the browser tab shows the R mark on the accent, not the old ring', () => {
  const favicon = readFileSync(join(dist, 'favicon.svg'), 'utf8');
  assert.match(favicon, /#0E7A5A/i);
  assert.doesNotMatch(favicon, /<circle/);
});
