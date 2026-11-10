#!/usr/bin/env node
// Builds the Relay Everything page, the phone app built for the web, with its fallback fonts, into an app's
// public/apps/relay/. --zip also writes the file a self-hosted install downloads. wiki/stack/mini-apps.md
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { delimiter, dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isMain, parseCli } from './lib-cli.mjs';
import { zip } from './lib-zip.mjs';

const USAGE = `usage: node scripts/build-relay-web.mjs [--app <folder>] [--zip <folder>]

Builds mobile/lib/main_web.dart with Flutter for the address /apps/relay/, adds the fallback fonts its engine asks
for (emoji and other scripts, fetched once into mobile/build/fallback-fonts/), then puts the build in
<folder>/public/apps/relay/ in place of the one there (default: the app/ folder beside this script). --zip also
writes relay-web-<commit>.zip and relay-web-<commit>.zip.sha256 into its folder, where <commit> is the newest commit
that changed mobile/. Prints one result= line.`;

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
/** Where an app folder keeps the built page; its Worker serves it at /apps/relay/. */
export const PAGE = join('public', 'apps', 'relay');
export const FLUTTER = ['build', 'web', '-t', 'lib/main_web.dart', '--base-href', '/apps/relay/', '--no-web-resources-cdn', '--release'];

/** Where the built page keeps the fallback fonts: mobile/web/flutter_bootstrap.js points the engine here. */
export const FONTS = 'fallback-fonts';
/** Where the engine gets them by default, and where the build fetches them, at the same paths. */
export const FONT_SOURCE = 'https://fonts.gstatic.com/s/';

/** The fallback fonts the built engine asks for, as paths under its `fontFallbackBaseUrl`, such as
 *  `roboto/v32/….woff2`. They are read from the built main.dart.js, so the list is always the engine's own. */
export const fallbackFontPaths = js =>
  [...new Set([...js.matchAll(/["']([a-z0-9]+\/v\d+\/[\w.-]+\.(?:woff2|ttf|otf))["']/g)].map(match => match[1]))].sort();

/** True for a font file's bytes: WOFF2, TrueType or OpenType. An error page is none of them. */
const isFont = data => ['wOF2', 'true', 'OTTO', '\0\x01\0\0'].includes(data.subarray(0, 4).toString('latin1'));

const defaultGet = async url => {
  for (let tries = 1; ; tries++) {
    try {
      const answer = await fetch(url);
      if (!answer.ok) throw new Error(`${url} answered ${answer.status}`);
      return Buffer.from(await answer.arrayBuffer());
    } catch (error) {
      if (tries >= 3) throw error;
    }
  }
};

/** Puts each fallback font the build's engine asks for in `built`/fallback-fonts/, from `cache` when it is there: a
 *  font's path names its version, so a kept file never changes. Throws when the engine's list or a font is missing. */
export async function addFallbackFonts(built, { cache, get = defaultGet, at = 8 }) {
  if (!readFileSync(join(built, 'flutter_bootstrap.js'), 'utf8').includes(`'${FONTS}/'`)) {
    throw new Error(`flutter_bootstrap.js does not point the engine at ${FONTS}/: mobile/web/flutter_bootstrap.js is missing`);
  }
  const paths = fallbackFontPaths(readFileSync(join(built, 'main.dart.js'), 'utf8'));
  if (!paths.length) throw new Error('main.dart.js names no fallback font: the engine keeps its list somewhere new');
  const waiting = [...paths];
  const fetchOne = async () => {
    for (let path; (path = waiting.shift()); ) {
      const kept = join(cache, path);
      if (!existsSync(kept)) {
        const data = await get(new URL(path, FONT_SOURCE).href);
        if (!isFont(data)) throw new Error(`${path} is not a font`);
        mkdirSync(dirname(kept), { recursive: true });
        writeFileSync(kept, data);
      }
      cpSync(kept, join(built, FONTS, path));
    }
  };
  await Promise.all(Array.from({ length: at }, fetchOne));
  return paths.length;
}

/** The commit the page is built from: the newest that changed mobile/, so a later change elsewhere keeps its file. */
export const webCommit = (root = ROOT) =>
  execFileSync('git', ['-C', root, 'log', '-1', '--format=%H', 'HEAD', '--', 'mobile'], { encoding: 'utf8', stdio: 'pipe' }).trim();
export const zipName = commit => `relay-web-${commit}.zip`;
export const sha256 = data => createHash('sha256').update(data).digest('hex');

/** Every file under `dir`, as `[relative path with forward slashes, data]`, in a fixed order. */
const filesOf = dir => readdirSync(dir, { recursive: true }).sort()
  .filter(name => statSync(join(dir, name)).isFile())
  .map(name => [name.split(sep).join('/'), readFileSync(join(dir, name))]);

// Flutter from the PATH, else where this computer keeps it.
const defaultRun = (cmd, args, opts) => execFileSync(cmd, args, { stdio: ['ignore', 2, 2], ...opts,
  env: { ...process.env, PATH: [process.env.PATH, '/opt/flutter/bin'].filter(Boolean).join(delimiter) } });

/** Builds and copies the page, and zips it when `zipTo` names a folder. Resolves to the one result line. */
export async function buildWeb({ root = ROOT, app = join(root, 'app'), zipTo, run = defaultRun, commit = webCommit, get }) {
  let step = 'flutter';
  try {
    run('flutter', FLUTTER, { cwd: join(root, 'mobile') });
    step = 'fonts';
    const built = join(root, 'mobile', 'build', 'web');
    await addFallbackFonts(built, { cache: join(root, 'mobile', 'build', FONTS), get });
    step = 'copy';
    const page = join(app, PAGE);
    rmSync(page, { recursive: true, force: true });
    cpSync(built, page, { recursive: true });
    if (!zipTo) return `result=ok page=${page}`;
    step = 'zip';
    const name = zipName(commit(root));
    const data = zip(filesOf(built));
    mkdirSync(zipTo, { recursive: true });
    writeFileSync(join(zipTo, name), data);
    writeFileSync(join(zipTo, `${name}.sha256`), `${sha256(data)}  ${name}\n`);
    return `result=ok page=${page} zip=${join(zipTo, name)} sha256=${sha256(data)}`;
  } catch (error) {
    process.stderr.write(`build-relay-web: ${step}: ${error.message}\n`);
    return `result=failed step=${step}`;
  }
}

if (isMain(import.meta.url)) {
  const { values } = parseCli({ usage: USAGE, options: { app: { type: 'string' }, zip: { type: 'string' } } });
  const line = await buildWeb({ ...values.app && { app: resolve(values.app) }, zipTo: values.zip && resolve(values.zip) });
  console.log(line);
  if (!line.startsWith('result=ok')) process.exit(1);
}
