#!/usr/bin/env node
// Makes every logo file, app icon and launch mark from brand/mark.svg: run `node brand/make-icons.mjs` after the mark
// or the brand colors change, and commit what it writes. wiki/brand.md says when.
//
// It writes brand/icon.svg (the mark on the accent, full bleed: each platform rounds its own corners), brand/logo.svg
// (the mark beside the wordmark), the website's top-bar marks and its favicon, then draws each
// picture once at 1024 px with headless Chromium, and sizes it with ImageMagick (`magick`) into every size the iOS
// AppIcon set lists and every Android density, with the Android adaptive icon and the launch marks. Output is the same
// on each run: PNG date chunks are left out. ImageMagick's own SVG renderer drops paths and stroke colors, so
// Chromium draws: set RELAY_CHROME to its path, or the script finds Playwright's headless shell or a chromium on PATH.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const at = (...parts) => join(root, ...parts);

// The Emerald set (wiki/brand.md): the icon is the mark in on-accent on the accent; the launch mark and the website's
// light mark are the mark in accent-text on paper. The waves are spark: mark.svg draws them in the light spark.
const accent = '#0E7A5A';
const onAccent = '#FFFFFF';
const accentText = '#0E7A5A';
const paper = '#F7F8F4';
const spark = '#F5A524';
const ink = '#121614';
const dark = { accentText: '#4CC79A', spark: '#FFC24D', ink: '#ECF3EE' };

// The mark's drawing: each path, with its stroke on the path itself (ImageMagick's renderer ignores a stroke set on
// the root <svg>).
const paths = [...readFileSync(at('brand/mark.svg'), 'utf8').matchAll(/<path\b[^>]*\/>/g)].map(([path]) => path);
if (paths.length === 0) throw new Error('brand/mark.svg has no <path/> elements');
if (!paths.some(path => path.includes('currentColor')) || !paths.some(path => path.includes(spark))) {
  throw new Error(`brand/mark.svg must draw the R in currentColor and the waves in ${spark}`);
}
/** The mark's paths, the R in [color] and the waves in [waves], each on its own line at [indent]. */
const markIn = (color, waves = spark, indent = '    ') =>
  paths.map(path => path.replaceAll('currentColor', color).replaceAll(spark, waves)).join(`\n${indent}`);
const title = '\n  <title>Relay Everything</title>';

/**
 * An SVG of [box] units, [size] pixels square: an optional [background] with corners of [rx], and the 48-unit mark at
 * [x],[y], [scale], in [color] with [waves]. [titled] names it for screen readers.
 */
function svg({ box, size, background, rx, color, waves, x, y, scale, titled = false }) {
  const corner = rx ? ` rx="${rx}"` : '';
  const fill = background ? `\n  <rect width="${box}" height="${box}"${corner} fill="${background}"/>` : '';
  const px = size ? ` width="${size}" height="${size}"` : '';
  const head = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${box} ${box}"${px} fill="none">${titled ? title : ''}`;
  if (x === 0 && y === 0 && scale === 1) return `${head}${fill}\n  ${markIn(color, waves, '  ')}\n</svg>\n`;
  return `${head}${fill}
  <g transform="translate(${x} ${y}) scale(${scale})">
    ${markIn(color, waves)}
  </g>
</svg>
`;
}

// The icon: the board's 46-unit mark on a 72-unit tile.
const icon = size => svg({ box: 72, size, background: accent, color: onAccent, x: 13, y: 13, scale: 46 / 48 });
// Android's adaptive foreground: 108 units, of which a circle 66 across always shows. The mark is 52 units, so its
// waves stay inside that circle.
const foreground = size => svg({ box: 108, size, color: onAccent, x: 28, y: 28, scale: 52 / 48 });
// The launch mark: the mark alone, accent text on the launch screen's paper.
const launch = size => svg({ box: 48, size, color: accentText, x: 0, y: 0, scale: 1 });
// The website's top-bar marks, light and dark, and its favicon: the icon with rounded corners, as a browser tab shows
// it as it is.
const siteMark = colors => svg({ box: 48, size: 48, color: colors.accentText, waves: colors.spark, x: 0, y: 0, scale: 1,
  titled: true });
const favicon = svg({ box: 72, background: accent, rx: 16, color: onAccent, x: 13, y: 13, scale: 46 / 48, titled: true });

/**
 * brand/logo.svg: the mark beside the wordmark, in the light colors with a dark set for a reader's dark setting. The
 * wordmark's outlines (Inter Bold) have no other source: the script keeps the one already in logo.svg.
 */
function logo() {
  const [wordmark] = readFileSync(at('brand/logo.svg'), 'utf8').match(/<path class="w"[^>]*\/>/) ?? [];
  if (!wordmark) throw new Error('brand/logo.svg has no <path class="w" .../> wordmark to keep');
  const mark = paths.map(path => {
    const wave = path.includes(spark);
    return path.replace('<path ', `<path class="${wave ? 's' : 'r'}" `).replaceAll('currentColor', accentText);
  }).join('\n  ');
  const word = wordmark.replace(/ fill="[^"]*"/, ` fill="${ink}"`);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 353 48" width="353" height="48" fill="none">${title}
  <style>
    .r { stroke: ${accentText}; } .s { stroke: ${spark}; } .w { fill: ${ink}; }
    @media (prefers-color-scheme: dark) { .r { stroke: ${dark.accentText}; } .s { stroke: ${dark.spark}; } .w { fill: ${dark.ink}; } }
  </style>
  ${mark}
  ${word}
</svg>
`;
}

/** The headless Chromium that draws the SVGs. */
function findChrome() {
  if (process.env.RELAY_CHROME) return process.env.RELAY_CHROME;
  const cache = join(homedir(), '.cache/ms-playwright');
  if (existsSync(cache)) {
    for (const dir of readdirSync(cache).filter(name => name.startsWith('chromium')).sort().reverse()) {
      for (const sub of readdirSync(join(cache, dir))) {
        for (const name of ['chrome-headless-shell', 'chrome']) {
          if (existsSync(join(cache, dir, sub, name))) return join(cache, dir, sub, name);
        }
      }
    }
  }
  for (const name of ['chromium', 'chromium-browser', 'google-chrome']) {
    try {
      return execFileSync('which', [name], { encoding: 'utf8' }).trim();
    } catch { /* try the next */ }
  }
  throw new Error('no Chromium found: set RELAY_CHROME to a Chrome or chrome-headless-shell');
}

const chrome = findChrome();
const work = mkdtempSync(join(tmpdir(), 'relay-icons-'));
const written = [];
const big = 1024;
const drawn = new Map();

/** Draws [picture] (a function of pixel size to SVG) once at 1024 px, see-through where it has no background. */
function draw(picture) {
  if (drawn.has(picture)) return drawn.get(picture);
  const input = join(work, `${drawn.size}.svg`);
  const output = join(work, `${drawn.size}.png`);
  writeFileSync(input, picture(big));
  execFileSync(chrome, ['--headless', '--no-sandbox', '--hide-scrollbars', '--default-background-color=00000000',
    `--window-size=${big},${big}`, `--screenshot=${output}`, `file://${input}`], { stdio: 'ignore' });
  drawn.set(picture, output);
  return output;
}

/** Writes [picture] as a [size] px PNG at [path]; [opaque] flattens it on the accent with no alpha (App Store rule). */
function render(picture, size, path, { opaque = false } = {}) {
  mkdirSync(dirname(at(path)), { recursive: true });
  const flat = opaque ? ['-background', accent, '-alpha', 'remove', '-alpha', 'off'] : [];
  execFileSync('magick', [draw(picture), '-resize', `${size}x${size}`, ...flat, '-strip',
    '-define', 'png:exclude-chunks=date,time', `${opaque ? 'PNG24' : 'PNG32'}:${at(path)}`]);
  written.push(path);
}

function write(path, text) {
  mkdirSync(dirname(at(path)), { recursive: true });
  writeFileSync(at(path), text);
  written.push(path);
}

try {
  write('brand/icon.svg', icon(null));
  write('brand/logo.svg', logo());
  write('site/src/assets/relay-mark.svg', siteMark({ accentText, spark }));
  write('site/src/assets/relay-mark-dark.svg', siteMark(dark));
  write('site/public/favicon.svg', favicon);

  // iOS: every image the AppIcon set lists, opaque.
  const iconSet = 'mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset';
  const { images } = JSON.parse(readFileSync(at(iconSet, 'Contents.json'), 'utf8'));
  const done = new Set();
  for (const image of images) {
    if (done.has(image.filename)) continue;
    done.add(image.filename);
    const size = Math.round(parseFloat(image.size) * parseFloat(image.scale));
    render(icon, size, `${iconSet}/${image.filename}`, { opaque: true });
  }

  // iOS launch mark: 96 points at 1x, 2x and 3x.
  const launchSet = 'mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset';
  for (const [scale, name] of [[1, 'LaunchImage.png'], [2, 'LaunchImage@2x.png'], [3, 'LaunchImage@3x.png']]) {
    render(launch, 96 * scale, `${launchSet}/${name}`);
  }

  // Android: the full icon (shown where adaptive icons are not), the adaptive foreground, and the launch mark.
  const res = 'mobile/android/app/src/main/res';
  for (const [density, scale] of [['mdpi', 1], ['hdpi', 1.5], ['xhdpi', 2], ['xxhdpi', 3], ['xxxhdpi', 4]]) {
    render(icon, 48 * scale, `${res}/mipmap-${density}/ic_launcher.png`, { opaque: true });
    render(foreground, 108 * scale, `${res}/mipmap-${density}/ic_launcher_foreground.png`);
    render(launch, 96 * scale, `${res}/mipmap-${density}/launch_image.png`);
  }
  write(`${res}/mipmap-anydpi-v26/ic_launcher.xml`, `<?xml version="1.0" encoding="utf-8"?>
<!-- Written by brand/make-icons.mjs: the accent behind the mark. The phone cuts it to its own shape. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
`);
  write(`${res}/values/brand_colors.xml`, `<?xml version="1.0" encoding="utf-8"?>
<!-- Written by brand/make-icons.mjs from the brand colors in wiki/brand.md. -->
<resources>
    <color name="ic_launcher_background">${accent}</color>
    <color name="launch_paper">${paper}</color>
</resources>
`);
} finally {
  rmSync(work, { recursive: true, force: true });
}

console.log(`result=made files=${written.length}`);
