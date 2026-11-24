// Checks that mobile/assets/editor/ was built from this source, by the SHA-256 the last build wrote in source.sha256.
// It needs no npm install. Usage: node mobile/editor-web/check-source.mjs
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

export const here = dirname(fileURLToPath(import.meta.url));
export const out = join(here, '..', 'assets', 'editor');

function filesIn(folder) {
  return readdirSync(folder, { withFileTypes: true }).flatMap(entry =>
    entry.isDirectory() ? filesIn(join(folder, entry.name)) : [join(folder, entry.name)]);
}

/// The SHA-256 of the page's source: each file's path and its own SHA-256, in a fixed order. Line ends count as \n,
/// so a checkout with Windows line ends gives the same value.
export function sourceHash() {
  const files = [...filesIn(join(here, 'src')), ...['package.json', 'package-lock.json', 'build.mjs'].map(name => join(here, name))]
    .map(file => relative(here, file).split('\\').join('/'))
    .sort();
  const all = createHash('sha256');
  for (const file of files) {
    const text = readFileSync(join(here, file)).toString('utf8').replace(/\r\n/g, '\n');
    all.update(`${file} ${createHash('sha256').update(text).digest('hex')}\n`);
  }
  return all.digest('hex');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const file = join(out, 'source.sha256');
  const want = sourceHash();
  const have = existsSync(file) ? readFileSync(file, 'utf8').trim() : '';
  if (have !== want) {
    console.error('result=refused');
    console.error('The note editor page in mobile/assets/editor/ is not built from the source in mobile/editor-web/.');
    console.error('Build it again: cd mobile/editor-web && npm ci && npm run build');
    process.exit(1);
  }
  console.log('result=ok');
}
