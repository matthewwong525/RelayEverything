// Builds the note editor page into mobile/assets/editor/ for the phone app: the script, the style sheet, the font,
// the page, and source.sha256 of its source. Usage: npm run build (in mobile/editor-web)
import { build, transform } from 'esbuild';
import { copyFileSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { here, out, sourceHash } from './check-source.mjs';

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

await build({
  entryPoints: [join(here, 'src', 'editor.js')],
  outfile: join(out, 'editor.js'),
  bundle: true,
  minify: true,
  format: 'iife',
  // The oldest web views the app runs in: iOS 15, macOS 12, and Android's own Chrome.
  target: ['safari15', 'chrome100'],
  legalComments: 'none',
  charset: 'utf8',
  logLevel: 'warning',
});

// The page names no address outside the phone: a help address in a library's error text goes. An XML namespace,
// such as SVG's, is a name, not a place the page loads.
const script = join(out, 'editor.js');
writeFileSync(script, readFileSync(script, 'utf8').replace(/https?:\/\/(?!www\.w3\.org\/)[^\s"'`)]+/g, 'the ProseMirror guide'));

const css = await transform(readFileSync(join(here, 'src', 'editor.css'), 'utf8'), {
  loader: 'css', minify: true, target: ['safari15', 'chrome100'],
});
writeFileSync(join(out, 'editor.css'), css.code);
writeFileSync(join(out, 'index.html'), readFileSync(join(here, 'src', 'index.html'), 'utf8'));
copyFileSync(join(here, '..', 'assets', 'fonts', 'inter', 'InterVariable.ttf'), join(out, 'InterVariable.ttf'));
writeFileSync(join(out, 'source.sha256'), `${sourceHash()}\n`);

const sizes = readdirSync(out).map(name => [name, statSync(join(out, name)).size]);
for (const [name, size] of sizes) console.log(`${name} ${(size / 1024).toFixed(1)} KB`);
console.log(`total ${(sizes.reduce((sum, [, size]) => sum + size, 0) / 1024).toFixed(1)} KB`);
