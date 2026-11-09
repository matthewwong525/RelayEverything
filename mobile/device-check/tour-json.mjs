#!/usr/bin/env node
// Writes out/tour.json from Maestro's JUnit files, the tour's run and each failed flow's second try, and copies each
// flow's own picture to out/tour/<flow>.png. usage: node tour-json.mjs <out> <flow>...
import { copyFileSync, mkdirSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { isMain } from '../../scripts/lib-cli.mjs';

/** Each flow named in a JUnit file, and whether it passed. */
export function junitResults(xml) {
  const passed = new Map();
  for (const [, attrs, body = ''] of (xml ?? '').matchAll(/<testcase\b([^>]*?)(?:\/>|>([\s\S]*?)<\/testcase>)/g)) {
    const name = attrs.match(/\bname="([^"]*)"/)?.[1];
    const status = attrs.match(/\bstatus="([^"]*)"/)?.[1];
    if (name) passed.set(name, status !== 'ERROR' && !/<failure\b/.test(body));
  }
  return passed;
}

/** Each flow's entry, in the tour's order. `retries` maps a flow that ran again to its second JUnit file ('' when
 * that run left none). A flow missing from its file, or with no file at all, did not pass. */
export function tourJson(xml, flows, retries = new Map()) {
  const first = junitResults(xml);
  return flows.map(flow => {
    const tried = retries.has(flow);
    const passed = (tried ? junitResults(retries.get(flow)).get(flow) : first.get(flow)) === true;
    return { flow, passed, tries: tried ? 2 : 1, screenshot: `tour/${flow}.png` };
  });
}

const newest = files => [...files].sort((a, b) => a.mtimeMs - b.mtimeMs || a.path.localeCompare(b.path)).at(-1)?.path;

/** The flow's own picture among `files` ({ path, mtimeMs }, under one run's folder), or undefined. A failed flow
 * shows the screen where it stopped; a passed one its takeScreenshot named as the flow, else its newest one. */
export function pickPicture(files, flow, passed) {
  const inFolder = folder => files.filter(file => file.path.split(/[\\/]/).slice(-3, -1).join('/') === `${flow}/${folder}`);
  const shots = inFolder('takeScreenshot');
  if (!passed) return newest(inFolder('screenshots'));
  return shots.find(file => file.path.endsWith(`/${flow}.png`))?.path ?? newest(shots);
}

/** Every .png under `root`, skipping the folders named in `skip`. */
function pictures(root, skip = []) {
  const found = [];
  const walk = folder => {
    let entries = [];
    try {
      entries = readdirSync(folder, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const path = join(folder, entry.name);
      if (entry.isDirectory() && !skip.includes(relative(root, path))) walk(path);
      else if (entry.isFile() && entry.name.endsWith('.png')) found.push({ path: path.split(sep).join('/'), mtimeMs: statSync(path).mtimeMs });
    }
  };
  walk(root);
  return found;
}

const readOr = (file, fallback) => {
  try {
    return readFileSync(file, 'utf8');
  } catch {
    return fallback;
  }
};

/** Builds tour.json from `<out>/maestro/` and copies the pictures; an entry with no picture from either try gets
 * screenshot_live. */
export function writeTour(out, flows) {
  const maestro = join(out, 'maestro');
  const retries = new Map();
  for (const flow of flows) {
    // tour.sh makes the file empty before the second try, so a try that hung still counts.
    const xml = readOr(join(maestro, 'retry', `${flow}.xml`), null);
    if (xml !== null) retries.set(flow, xml);
  }
  const firstPictures = pictures(maestro, ['retry']);
  mkdirSync(join(out, 'tour'), { recursive: true });
  return tourJson(readOr(join(maestro, 'tour.xml'), ''), flows, retries).map(entry => {
    // A second try that left no picture, such as one that hung, shows where the first try stopped.
    const second = entry.tries === 2 && pickPicture(pictures(join(maestro, 'retry', entry.flow)), entry.flow, entry.passed);
    const picture = second || pickPicture(firstPictures, entry.flow, entry.tries === 2 ? false : entry.passed);
    if (!picture) return { ...entry, screenshot_live: true };
    copyFileSync(picture, join(out, entry.screenshot));
    return entry;
  });
}

if (isMain(import.meta.url)) {
  const [out, ...flows] = process.argv.slice(2);
  console.log(JSON.stringify(writeTour(out, flows)));
}
