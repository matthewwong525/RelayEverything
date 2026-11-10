#!/usr/bin/env node
// Sums up the app's crash reports for report.md: the first crash's exception, signal, termination and the crashed
// thread's first 8 frames. usage: node crash.mjs <crashes folder>. Prints nothing when the folder has no report.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { isMain } from '../../scripts/lib-cli.mjs';

export const FRAMES = 8;

/** An .ips file is a JSON header line, then a JSON body. Null when the text is not one. */
export function readIps(text) {
  const newline = text.indexOf('\n');
  try {
    return { header: JSON.parse(text.slice(0, newline)), body: JSON.parse(text.slice(newline + 1)) };
  } catch {
    return null;
  }
}

function frameLine(frame, images, index) {
  const image = images[frame.imageIndex]?.name ?? '???';
  const where = frame.symbol ?? `0x${Number(frame.imageOffset ?? 0).toString(16)}`;
  const source = frame.sourceFile ? ` (${frame.sourceFile}:${frame.sourceLine})` : '';
  return `  ${index} ${image}  ${where}${source}`;
}

/** The lines of one crash: its reason first, then the crashed thread's first frames. */
export function crashSummary({ body }) {
  const { exception = {}, termination = {}, threads = [], usedImages = [] } = body;
  const reason = [exception.type, exception.signal && `(${exception.signal})`].filter(Boolean).join(' ') || 'no exception';
  const lines = [`The app crashed: ${reason}`];
  const ended = [termination.namespace, termination.indicator].filter(Boolean).join(' ');
  if (ended) lines.push(`Ended by: ${ended}${termination.reasons?.length ? `: ${termination.reasons.join(' ')}` : ''}`);
  const thread = threads[body.faultingThread] ?? threads.find(each => each.triggered);
  const frames = (thread?.frames ?? []).slice(0, FRAMES);
  if (frames.length) lines.push(`Crashed thread${thread.name ? ` (${thread.name})` : ''}:`);
  frames.forEach((frame, index) => lines.push(frameLine(frame, usedImages, index)));
  return lines.join('\n');
}

/** The summary of the oldest report among `files` ({ name, text }), and how many more there are. '' with none. */
export function crashText(files) {
  const sorted = [...files].sort((a, b) => a.name.localeCompare(b.name));
  if (!sorted.length) return '';
  const [first] = sorted;
  const ips = readIps(first.text);
  const summary = ips ? crashSummary(ips) : `The app crashed: crashes/${first.name} (the report can't be read).`;
  const more = sorted.length - 1;
  return more ? `${summary}\n${more} more crash report${more === 1 ? '' : 's'} in crashes/.` : summary;
}

if (isMain(import.meta.url)) {
  const folder = process.argv[2];
  let names = [];
  try {
    names = readdirSync(folder).filter(name => name.startsWith('Runner'));
  } catch {
    // No folder: no crash.
  }
  const text = crashText(names.map(name => ({ name, text: readFileSync(join(folder, name), 'utf8') })));
  if (text) console.log(text);
}
