// Run with: node --test mobile/device-check/*.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { tourJson } from './tour-json.mjs';

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

test("each flow gets one entry in the tour's order, whatever order the file has", () => {
  assert.deepEqual(tourJson(XML, FLOWS), [
    { flow: 'timeline', passed: true, screenshot: 'tour/timeline.png' },
    { flow: 'new-note', passed: false, screenshot: 'tour/new-note.png' },
    { flow: 'settings', passed: true, screenshot: 'tour/settings.png' },
  ]);
});

test('a failure with no status, a missing flow and a missing file each fail', () => {
  const noStatus = '<testcase name="timeline"><failure>x</failure></testcase><testcase name="settings"/>';
  assert.deepEqual(tourJson(noStatus, FLOWS).map(entry => entry.passed), [false, false, true]);
  assert.deepEqual(tourJson('', FLOWS).map(entry => entry.passed), [false, false, false]);
});
