// Run with: node --test mobile/device-check/*.test.mjs
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { pickPicture, tourJson, writeTour } from './tour-json.mjs';

const FLOWS = ['timeline', 'new-note', 'settings'];
// The shape Maestro 2.12.1's JUnit report writes (maestro-cli JUnitTestSuiteReporterTest).
const XML = `<?xml version='1.0' encoding='UTF-8'?>
<testsuites>
  <testsuite name="Test Suite" device="iPhone 17" tests="3" failures="1" time="80.2" timestamp="2026-11-08T10:00:00">
    <testcase id="settings" name="settings" classname="settings" file="flows/settings.yaml" time="20.1" status="SUCCESS"/>
    <testcase id="timeline" name="timeline" classname="timeline" file="flows/timeline.yaml" time="30.0" status="WARNING"/>
    <testcase id="new-note" name="new-note" classname="new-note" file="flows/new-note.yaml" time="30.1" status="ERROR">
      <failure>Assertion is false: "Device check note(.|\\n)*" is visible</failure>
    </testcase>
  </testsuite>
</testsuites>`;
const passedAlone = flow => `<testsuites><testsuite><testcase name="${flow}" status="SUCCESS"/></testsuite></testsuites>`;

test("each flow gets one entry in the tour's order, whatever order the file has", () => {
  assert.deepEqual(tourJson(XML, FLOWS), [
    { flow: 'timeline', passed: true, tries: 1, screenshot: 'tour/timeline.png' },
    { flow: 'new-note', passed: false, tries: 1, screenshot: 'tour/new-note.png' },
    { flow: 'settings', passed: true, tries: 1, screenshot: 'tour/settings.png' },
  ]);
});

test('a failure with no status, a missing flow and a missing file each fail', () => {
  const noStatus = '<testcase name="timeline"><failure>x</failure></testcase><testcase name="settings"/>';
  assert.deepEqual(tourJson(noStatus, FLOWS).map(entry => entry.passed), [false, false, true]);
  assert.deepEqual(tourJson('', FLOWS).map(entry => entry.passed), [false, false, false]);
});

test('the second try decides a flow that ran again; one that hung with no file stays failed', () => {
  const passed = tourJson(XML, FLOWS, new Map([['new-note', passedAlone('new-note')]]));
  assert.deepEqual(passed[1], { flow: 'new-note', passed: true, tries: 2, screenshot: 'tour/new-note.png' });
  const hung = tourJson(XML, FLOWS, new Map([['new-note', '']]));
  assert.deepEqual(hung[1], { flow: 'new-note', passed: false, tries: 2, screenshot: 'tour/new-note.png' });
});

// The pictures of run 42544862299, where timeline failed and its fallback showed Settings.
const RUN = 'maestro/2026-11-09_013008';
const FILES = [
  { path: `${RUN}/timeline/takeScreenshot/home.png`, mtimeMs: 1 },
  { path: `${RUN}/timeline/screenshots/step-012-assertCondition-No_notes_yet(._n).png`, mtimeMs: 2 },
  { path: `${RUN}/new-note/takeScreenshot/note-reading.png`, mtimeMs: 3 },
  { path: `${RUN}/note-styles/takeScreenshot/note-styles.png`, mtimeMs: 4 },
  { path: `${RUN}/settings/screenshots/step-006-assertCondition-Appearance.png`, mtimeMs: 5 },
  { path: `${RUN}/voice-note/takeScreenshot/voice-recording.png`, mtimeMs: 6 },
  { path: `${RUN}/voice-note/takeScreenshot/voice-cancelled.png`, mtimeMs: 8 },
  { path: `${RUN}/voice-note/takeScreenshot/voice-saved.png`, mtimeMs: 7 },
];

test("a failed flow shows the screen where it stopped, never another flow's", () => {
  assert.equal(pickPicture(FILES, 'timeline', false), `${RUN}/timeline/screenshots/step-012-assertCondition-No_notes_yet(._n).png`);
  assert.equal(pickPicture(FILES, 'settings', false), `${RUN}/settings/screenshots/step-006-assertCondition-Appearance.png`);
});

test('a passed flow shows its picture named as the flow, else its newest one, and none is undefined', () => {
  assert.equal(pickPicture(FILES, 'note-styles', true), `${RUN}/note-styles/takeScreenshot/note-styles.png`);
  assert.equal(pickPicture(FILES, 'voice-note', true), `${RUN}/voice-note/takeScreenshot/voice-cancelled.png`);
  assert.equal(pickPicture(FILES, 'share-link', true), undefined);
  assert.equal(pickPicture(FILES, 'new-note', false), undefined);
});

test("writeTour copies each flow's picture, the second try's for a flow that ran again", () => {
  const out = mkdtempSync(join(tmpdir(), 'tour-json-'));
  const picture = (path, text, mtime) => {
    mkdirSync(join(out, path, '..'), { recursive: true });
    writeFileSync(join(out, path), text);
    utimesSync(join(out, path), mtime, mtime);
  };
  mkdirSync(join(out, 'maestro', 'retry'), { recursive: true });
  writeFileSync(join(out, 'maestro', 'tour.xml'), XML);
  writeFileSync(join(out, 'maestro', 'retry', 'new-note.xml'), passedAlone('new-note'));
  picture(`${RUN}/timeline/takeScreenshot/timeline.png`, 'first timeline', 1);
  picture(`${RUN}/new-note/screenshots/step-014.png`, 'first new-note', 2);
  picture(`maestro/retry/new-note/2026-11-09_014000/new-note/takeScreenshot/new-note.png`, 'second new-note', 3);
  const tour = writeTour(out, FLOWS);
  assert.deepEqual(tour.map(entry => [entry.flow, entry.passed, entry.tries, entry.screenshot_live ?? false]), [
    ['timeline', true, 1, false],
    ['new-note', true, 2, false],
    ['settings', true, 1, true],
  ]);
  assert.equal(readFileSync(join(out, 'tour', 'timeline.png'), 'utf8'), 'first timeline');
  assert.equal(readFileSync(join(out, 'tour', 'new-note.png'), 'utf8'), 'second new-note');
});

test("a second try that left no picture shows the first try's failure picture; live only with none from either", () => {
  const out = mkdtempSync(join(tmpdir(), 'tour-json-'));
  const picture = (path, text) => {
    mkdirSync(join(out, path, '..'), { recursive: true });
    writeFileSync(join(out, path), text);
  };
  mkdirSync(join(out, 'maestro', 'retry'), { recursive: true });
  writeFileSync(join(out, 'maestro', 'tour.xml'), XML.replace('status="SUCCESS"', 'status="ERROR"'));
  // tour.sh empties each file before the second try, and a try that hung writes none: both flows failed twice.
  writeFileSync(join(out, 'maestro', 'retry', 'new-note.xml'), '');
  writeFileSync(join(out, 'maestro', 'retry', 'settings.xml'), '');
  picture(`${RUN}/timeline/takeScreenshot/timeline.png`, 'first timeline');
  picture(`${RUN}/new-note/screenshots/step-014.png`, 'first new-note');
  const tour = writeTour(out, FLOWS);
  assert.deepEqual(tour.map(entry => [entry.flow, entry.passed, entry.tries, entry.screenshot_live ?? false]), [
    ['timeline', true, 1, false],
    ['new-note', false, 2, false],
    ['settings', false, 2, true],
  ]);
  assert.equal(readFileSync(join(out, 'tour', 'new-note.png'), 'utf8'), 'first new-note');
});
