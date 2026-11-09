// Run with: node --test scripts/device-check.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  cancelReason, checkValues, dispatchMissing, finishedChecks, findRun, lastReport, readVerdict, recheckScenarios, resultOf,
  scenarioVerdicts, swiftOutcome, tourOutcome, waitDone,
} from './device-check.mjs';

const SHA = 'a'.repeat(40);
const OTHER = 'b'.repeat(40);
const after = Date.parse('2026-11-06T10:00:00Z');
// The shape `gh run list --json databaseId,headSha,event,createdAt,url,conclusion` prints.
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

test('the verdict file gives one of four verdicts, and anything else is no verdict', () => {
  assert.equal(readVerdict('works\n'), 'works');
  assert.equal(readVerdict('  could-not-check '), 'could-not-check');
  assert.equal(readVerdict('broken'), 'broken');
  assert.equal(readVerdict('no-verdict\n'), 'no-verdict');
  for (const text of ['', 'Works', 'works fine', 'passed', undefined]) assert.equal(readVerdict(text), null);
});

test('the result is the verdict, a timeout, or failed when no verdict came back', () => {
  assert.equal(resultOf({ timedOut: false, verdict: 'works' }), 'works');
  assert.equal(resultOf({ timedOut: false, verdict: 'broken' }), 'broken');
  assert.equal(resultOf({ timedOut: false, verdict: null }), 'failed');
  assert.equal(resultOf({ timedOut: true, verdict: 'works' }), 'timeout');
  assert.equal(resultOf({ timedOut: false, verdict: 'no-verdict' }), 'no-verdict');
});

test('a cancelled run is cancelled, whatever its verdict file says', () => {
  assert.equal(resultOf({ timedOut: false, cancelled: true, verdict: 'no-verdict' }), 'cancelled');
  assert.equal(resultOf({ timedOut: false, cancelled: true, verdict: null }), 'cancelled');
});

test('failed Swift tests on the second Mac make the check broken', () => {
  assert.equal(resultOf({ timedOut: false, verdict: 'works', swift: 'failed' }), 'broken');
  assert.equal(resultOf({ timedOut: false, verdict: 'works', swift: 'passed' }), 'works');
  assert.equal(resultOf({ timedOut: false, verdict: 'works', swift: '' }), 'works');
});

test('Swift tests that never finished are no failure: only a failed swift-tests job is', () => {
  assert.equal(swiftOutcome('failure', 'failed'), 'failed');
  assert.equal(swiftOutcome('cancelled', 'failed'), '');
  assert.equal(swiftOutcome('timed_out', 'failed'), '');
  assert.equal(swiftOutcome('success', 'passed'), 'passed');
  assert.equal(swiftOutcome('failure', ''), '');
  assert.equal(swiftOutcome(undefined, ''), '');
  assert.equal(swiftOutcome(undefined, 'failed'), 'failed');
  assert.equal(resultOf({ timedOut: false, verdict: 'works', swift: swiftOutcome('cancelled', 'failed') }), 'works');
});

test('a cancelled run says whether a newer check replaced it', () => {
  assert.match(cancelReason(runs, runs[2]), /newer check/);
  assert.match(cancelReason(runs, runs[4]), /stopped before it ended/);
});

test('a newer skipped run, such as a start by another label, replaced nothing', () => {
  const skipped = { databaseId: 99, createdAt: '2099-01-01T00:00:00Z', conclusion: 'skipped' };
  assert.match(cancelReason([runs[4], skipped], runs[4]), /stopped before it ended/);
  assert.match(cancelReason([runs[4], { ...skipped, conclusion: '' }], runs[4]), /newer check/);
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

test('--flows takes names split by commas, and nothing that could name another file', () => {
  const good = { ref: 'feature', sha: SHA, platform: 'iphone', model: 'claude-sonnet-5-5' };
  assert.equal(checkValues({ ...good, flows: 'voice-note' }, ['run']), null);
  assert.equal(checkValues({ ...good, flows: 'voice-note,share-link' }, ['run']), null);
  for (const flows of ['', '../x', 'voice note', 'voice-note,', 'Voice']) {
    assert.match(checkValues({ ...good, flows }, ['run']), /--flows/);
  }
});

test("the tour passed only when each step passed and the app didn't crash, and it names second tries", () => {
  const entries = [{ flow: 'timeline', passed: true, tries: 1 }, { flow: 'new-note', passed: true, tries: 2 }];
  assert.deepEqual(tourOutcome(entries), {
    tour: 'passed', reason: '2 steps passed; passed on the second try: new-note; Claude is checking now',
  });
  const failed = [entries[0], { flow: 'settings', passed: false, tries: 2 }];
  assert.deepEqual(tourOutcome(failed, { reason: 'A step of the tour failed on both tries: settings.' }),
    { tour: 'broken', reason: 'A step of the tour failed on both tries: settings.' });
  assert.deepEqual(tourOutcome(failed), { tour: 'broken', reason: 'the tour failed at settings' });
  assert.equal(tourOutcome(entries, { reason: 'The app crashed during the tour.', crashed: true }).tour, 'broken');
  assert.equal(tourOutcome([]), null);
  assert.equal(tourOutcome(null), null);
});

// Cut from Claude's report on run 42533783176.
const REPORT = `Scenario: Hold to talk tip
Tried: Read the fixed tour's Home/Notes screenshot (fresh install).
Verdict: works
Reason: Matches THEN.

Scenario: The ring fills during the hold
Verdict: could-not-check

Scenario: The recording fills the screen
Verdict: works

Scenario: Tap anywhere saves
Saw: The app had quit.
Verdict: broken

Notes:
- The app crashes on launch after the first save.

Verdict: broken
`;

const SCENARIOS = `Change: A voice note records on its own full screen.

Scenario: Hold to talk tip
WHEN the app opens on a fresh install
THEN a Hold to talk tip shows above New note

#### Scenario: the  RING fills during the hold
WHEN you hold New note
THEN a ring fills

Scenario: The recording fills the screen
WHEN the recording starts
THEN it fills the screen

Scenario: Tap anywhere saves
WHEN you tap the middle
THEN the note page opens

Scenario: A scenario the last check did not have
WHEN you tap X
THEN nothing is kept`;

test("the report gives each scenario's own verdict, never the overall one", () => {
  assert.deepEqual(scenarioVerdicts(REPORT), [
    { name: 'Hold to talk tip', verdict: 'works' },
    { name: 'The ring fills during the hold', verdict: 'could-not-check' },
    { name: 'The recording fills the screen', verdict: 'works' },
    { name: 'Tap anywhere saves', verdict: 'broken' },
  ]);
});

test('a re-check sends only the blocks that were not works, and keeps a block it cannot match', () => {
  const cut = recheckScenarios(SCENARIOS, REPORT);
  assert.deepEqual(cut.passed, ['Hold to talk tip', 'The recording fills the screen']);
  assert.equal(cut.reason, undefined);
  assert.match(cut.scenarios, /^Change: A voice note/);
  assert.match(cut.scenarios, /RING fills during the hold/);
  assert.match(cut.scenarios, /Scenario: Tap anywhere saves\nWHEN you tap the middle/);
  assert.match(cut.scenarios, /A scenario the last check did not have/);
  assert.doesNotMatch(cut.scenarios, /Hold to talk tip|fills the screen/);
});

test('with nothing that worked, no matching name, or nothing left, every scenario goes', () => {
  assert.deepEqual(recheckScenarios(SCENARIOS, ''), {
    scenarios: SCENARIOS, passed: [], reason: 'the last check has no scenario that works',
  });
  const other = recheckScenarios('Scenario: Settings\nWHEN x\nTHEN y', REPORT);
  assert.equal(other.passed.length, 0);
  assert.match(other.reason, /no scenario in the file matches/);
  const all = recheckScenarios('Scenario: Hold to talk tip\nWHEN a\nTHEN b', REPORT);
  assert.equal(all.scenarios, 'Scenario: Hold to talk tip\nWHEN a\nTHEN b');
  assert.match(all.reason, /every scenario worked/);
});

test('the last check is the newest finished one started by hand, never a cancelled or running one', () => {
  const list = [
    { databaseId: 1, event: 'workflow_dispatch', createdAt: '2026-11-09T08:00:00Z', conclusion: 'failure' },
    { databaseId: 2, event: 'workflow_dispatch', createdAt: '2026-11-09T09:00:00Z', conclusion: 'success' },
    { databaseId: 3, event: 'workflow_dispatch', createdAt: '2026-11-09T10:00:00Z', conclusion: 'cancelled' },
    { databaseId: 4, event: 'workflow_dispatch', createdAt: '2026-11-09T11:00:00Z', conclusion: '' },
    { databaseId: 5, event: 'pull_request', createdAt: '2026-11-09T12:00:00Z', conclusion: 'success' },
  ];
  assert.deepEqual(finishedChecks(list).map(run => run.databaseId), [2, 1]);
  assert.deepEqual(finishedChecks(list.slice(2)), []);
  assert.deepEqual(finishedChecks([]), []);
});

test('each re-check skips what passed in any earlier check, and reads only a check that reached Claude', () => {
  const A = 'Scenario: Alpha\nWHEN a\nTHEN a';
  const B = 'Scenario: Beta\nWHEN b\nTHEN b';
  const both = `${A}\n\n${B}`;
  const results = new Map();
  const runs = [];
  // Runs one check: what lastReport picks, what it sends, and what the run leaves, as finish.sh writes it.
  const check = (id, verdicts, { claude = true } = {}) => {
    const last = lastReport(runs, run => results.get(run.databaseId));
    const cut = last ? recheckScenarios(both, last.report, last.carried) : { scenarios: both, passed: [] };
    const passedBefore = cut.passed.length ? [last.run.url, ...cut.passed].join('\n') : '';
    const report = claude ? verdicts.map(([name, verdict]) => `Scenario: ${name}\nVerdict: ${verdict}`).join('\n\n') : '';
    results.set(id, { report, passedBefore });
    runs.push({ databaseId: id, event: 'workflow_dispatch', conclusion: 'failure', url: `u${id}`,
      createdAt: `2026-11-09T0${id}:00:00Z` });
    return { last: last?.run.databaseId, sent: cut.scenarios, passedBefore };
  };
  check(1, [['Alpha', 'works'], ['Beta', 'broken']]);
  const second = check(2, [['Beta', 'broken']]);
  assert.equal(second.last, 1);
  assert.equal(second.sent, B);
  assert.equal(second.passedBefore, 'u1\nAlpha');
  const third = check(3, [], { claude: false });
  assert.equal(third.last, 2);
  assert.equal(third.sent, B);
  assert.equal(third.passedBefore, 'u2\nAlpha');
  const fourth = check(4, [['Beta', 'works']]);
  assert.equal(fourth.last, 2, 'check 3 stopped at the tour, so it is skipped');
  assert.equal(fourth.sent, B);
  assert.equal(lastReport(runs.slice(2, 3), run => results.get(run.databaseId)), null);
});

test('a scenario the last check tried again goes by its verdict there, not by an older pass', () => {
  const cut = recheckScenarios('Scenario: Alpha\nWHEN a\n\nScenario: Beta\nWHEN b', 'Scenario: Alpha\nVerdict: broken', ['Alpha']);
  assert.equal(cut.reason, 'the last check has no scenario that works');
});

test('waitDone waits through a run still going and a failed read, and stops at the limit', async () => {
  const answers = ['in_progress', '', 'completed'];
  assert.equal(await waitDone(() => answers.shift(), { until: Date.now() + 1000, every: 1 }), true);
  assert.deepEqual(answers, []);
  assert.equal(await waitDone(() => 'in_progress', { until: Date.now() + 20, every: 5 }), false);
});
