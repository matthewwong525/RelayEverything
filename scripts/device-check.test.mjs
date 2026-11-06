// Run with: node --test scripts/device-check.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { checkValues, dispatchMissing, findRun, readVerdict, resultOf } from './device-check.mjs';

const SHA = 'a'.repeat(40);
const OTHER = 'b'.repeat(40);
const after = Date.parse('2026-11-06T10:00:00Z');
// The shape `gh run list --json databaseId,headSha,event,createdAt,url` prints.
const runs = [
  { databaseId: 1, headSha: SHA, event: 'workflow_dispatch', createdAt: '2026-11-06T09:59:00Z', url: 'u1' },
  { databaseId: 2, headSha: SHA, event: 'workflow_dispatch', createdAt: '2026-11-06T10:00:05Z', url: 'u2' },
  { databaseId: 3, headSha: SHA, event: 'workflow_dispatch', createdAt: '2026-11-06T10:00:30Z', url: 'u3' },
  { databaseId: 4, headSha: OTHER, event: 'workflow_dispatch', createdAt: '2026-11-06T10:01:00Z', url: 'u4' },
  { databaseId: 5, headSha: SHA, event: 'pull_request', createdAt: '2026-11-06T10:02:00Z', url: 'u5' },
];

test('the run is the newest one of this commit and start kind since the start', () => {
  assert.equal(findRun(runs, { sha: SHA, event: 'workflow_dispatch', after }).databaseId, 3);
  assert.equal(findRun(runs, { sha: SHA, event: 'pull_request', after }).databaseId, 5);
});

test('an older run, or a run of another commit, is never taken', () => {
  assert.equal(findRun(runs.slice(0, 1), { sha: SHA, event: 'workflow_dispatch', after }), null);
  assert.equal(findRun(runs, { sha: 'c'.repeat(40), event: 'workflow_dispatch', after }), null);
  assert.equal(findRun([], { sha: SHA, event: 'pull_request', after }), null);
});

test('the verdict file gives one of three verdicts, and anything else is no verdict', () => {
  assert.equal(readVerdict('works\n'), 'works');
  assert.equal(readVerdict('  could-not-check '), 'could-not-check');
  assert.equal(readVerdict('broken'), 'broken');
  for (const text of ['', 'Works', 'works fine', 'passed', undefined]) assert.equal(readVerdict(text), null);
});

test('the result is the verdict, a timeout, or failed when no verdict came back', () => {
  assert.equal(resultOf({ timedOut: false, verdict: 'works' }), 'works');
  assert.equal(resultOf({ timedOut: false, verdict: 'broken' }), 'broken');
  assert.equal(resultOf({ timedOut: false, verdict: null }), 'failed');
  assert.equal(resultOf({ timedOut: true, verdict: 'works' }), 'timeout');
});

test('a refused start by hand is told apart from other failures', () => {
  assert.ok(dispatchMissing('could not find any workflows named mobile-device-check.yml'));
  assert.ok(dispatchMissing("HTTP 422: Workflow does not have 'workflow_dispatch' trigger"));
  assert.ok(!dispatchMissing('HTTP 401: Bad credentials'));
});

test('the command takes a branch, a full SHA, a pull request number, a platform and a Claude model', () => {
  const good = { ref: 'feature', sha: SHA, platform: 'iphone', model: 'claude-sonnet-5-5' };
  assert.equal(checkValues(good, ['run']), null);
  assert.equal(checkValues({ ...good, pr: '19' }, ['run']), null);
  assert.match(checkValues(good, []), /run/);
  assert.match(checkValues({ ...good, sha: 'abc' }, ['run']), /--sha/);
  assert.match(checkValues({ ...good, pr: '#19' }, ['run']), /--pr/);
  assert.match(checkValues({ ...good, platform: 'windows' }, ['run']), /--platform/);
  assert.match(checkValues({ ...good, model: 'x; rm -rf /' }, ['run']), /--model/);
});
