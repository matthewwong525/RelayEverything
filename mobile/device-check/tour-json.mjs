#!/usr/bin/env node
// Turns Maestro's JUnit file into out/tour.json: one entry per flow, in the tour's order, as finish.sh reads it.
// usage: node tour-json.mjs <tour.xml> <flow>...
import { readFileSync } from 'node:fs';
import { isMain } from '../../scripts/lib-cli.mjs';

/** Each flow's entry. A flow missing from the file, or with no file at all, did not pass. */
export function tourJson(xml, flows) {
  const passed = new Map();
  for (const [, attrs, body = ''] of (xml ?? '').matchAll(/<testcase\b([^>]*?)(?:\/>|>([\s\S]*?)<\/testcase>)/g)) {
    const name = attrs.match(/\bname="([^"]*)"/)?.[1];
    const status = attrs.match(/\bstatus="([^"]*)"/)?.[1];
    if (name) passed.set(name, status !== 'ERROR' && !/<failure\b/.test(body));
  }
  return flows.map(flow => ({ flow, passed: passed.get(flow) === true, screenshot: `tour/${flow}.png` }));
}

if (isMain(import.meta.url)) {
  const [file, ...flows] = process.argv.slice(2);
  let xml = '';
  try {
    xml = readFileSync(file, 'utf8');
  } catch {
    // No file: Maestro stopped before it wrote one, so no flow passed.
  }
  console.log(JSON.stringify(tourJson(xml, flows)));
}
