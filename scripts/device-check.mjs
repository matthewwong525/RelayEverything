#!/usr/bin/env node
// Starts the phone app's device check on GitHub for a saved commit, waits, downloads its results and prints result=.
// The workflow and what each result means: wiki/development/device-check.md.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { isMain, parseCli, usageError } from './lib-cli.mjs';

const USAGE = `usage: node scripts/device-check.mjs run --ref <branch> --sha <commit> [--pr <n>] [--scenarios-file <file>]
       [--flows <name,name>] [--recheck] [--model <id>] [--platform iphone]

Starts .github/workflows/mobile-device-check.yml on the branch for the saved commit, waits up to 50 minutes, and
downloads the report, pictures and video to a new temporary folder. --flows adds tour steps from
mobile/device-check/flows/. --recheck sends only the scenarios that were not works, nor skipped as passed, in the
branch's newest finished check that reached Claude, and prints recheck= (that check's link, or none) and
recheck_skipped= or recheck_reason=. Prints tour= and tour_reason= once the tour ends. Until the workflow is on the default branch, GitHub can't start it by hand: with
--pr, the check then starts by the "check on iPhone" label, runs the fixed tour alone, and Claude reads the open
change's specs in place of --scenarios-file. Prints result=works|broken|could-not-check|no-verdict|cancelled|timeout|
failed, start=, run=, folder= and reason=. Exits 0 only on works.`;

export const WORKFLOW = 'mobile-device-check.yml';
export const LABEL = 'check on iPhone';
export const VERDICTS = ['works', 'broken', 'could-not-check', 'no-verdict'];
const PLATFORMS = ['iphone'];
const WATCH_MS = 50 * 60 * 1000;
const FIND_MS = 3 * 60 * 1000;
// GitHub's clock and this computer's can differ, so a run counts as new from a minute before the start.
const CLOCK_SLACK_MS = 60 * 1000;

const gh = (args, options = {}) => spawnSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options });

/** True when GitHub refused a start by hand because the workflow is not on the default branch yet. */
export const dispatchMissing = stderr => /could not find any workflows|HTTP 404|HTTP 422|workflow_dispatch/i.test(stderr);

/** The newest run of this commit and start kind that began after `after` (ms), or null. */
export function findRun(runs, { sha, event, after }) {
  return runs
    .filter(run => run.headSha === sha && run.event === event && Date.parse(run.createdAt) >= after)
    .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))[0] ?? null;
}

/** The run's verdict from its verdict.txt, or null when the file holds anything else. */
export function readVerdict(text) {
  const word = (text ?? '').trim();
  return VERDICTS.includes(word) ? word : null;
}

/** The one result this script reports. A failed Swift test makes the check broken, as it did on one Mac. */
export function resultOf({ timedOut, cancelled, verdict, swift }) {
  if (timedOut) return 'timeout';
  if (cancelled) return 'cancelled';
  if (swift === 'failed' && verdict !== 'broken') return 'broken';
  return verdict ?? 'failed';
}

/** The Swift tests' outcome: `failed` unless job swift-tests was cancelled or timed out, which is no fault. */
export function swiftOutcome(conclusion, text) {
  // No conclusion (GitHub did not answer) trusts the file: the job writes failed only when xcodebuild fails.
  if (text === 'failed') return !conclusion || conclusion === 'failure' ? 'failed' : '';
  return text === 'passed' ? 'passed' : '';
}

/** Why a run was cancelled: a newer check of the branch replaced it, or it ran out of time. A skipped run, such as
 * the start by another label, replaces nothing. */
export function cancelReason(runs, run) {
  const newer = runs.some(other => other.databaseId !== run.databaseId && other.conclusion !== 'skipped'
    && Date.parse(other.createdAt) > Date.parse(run.createdAt));
  return newer ? 'a newer check of this branch replaced it' : 'the run was stopped before it ended, such as when it ran out of time';
}

export function checkValues(values, positionals) {
  if (positionals[0] !== 'run' || positionals.length !== 1) return 'give the command run';
  if (!values.ref) return 'give --ref <branch>';
  if (!/^[0-9a-f]{40}$/.test(values.sha ?? '')) return 'give --sha as a full commit SHA';
  if (values.pr !== undefined && !/^\d+$/.test(values.pr)) return '--pr takes a pull request number';
  if (!PLATFORMS.includes(values.platform)) return `--platform takes ${PLATFORMS.join(', ')}`;
  if (!/^claude-[a-z0-9-]+$/.test(values.model)) return '--model takes a Claude model ID';
  if (values.flows !== undefined && !/^[a-z0-9-]+(,[a-z0-9-]+)*$/.test(values.flows)) {
    return '--flows takes flow names split by commas, such as voice-note';
  }
  return null;
}

/** The tour's result from its tour.json entries and reason.txt: passed only when each step passed and nothing
 * crashed. Null with no entries. */
export function tourOutcome(entries, { reason = '', crashed = false } = {}) {
  if (!Array.isArray(entries) || !entries.length) return null;
  const failed = entries.filter(entry => !entry.passed).map(entry => entry.flow);
  if (failed.length || crashed) {
    return { tour: 'broken', reason: reason || `the tour failed at ${failed.join(', ')}` };
  }
  const second = entries.filter(entry => entry.tries === 2).map(entry => entry.flow);
  const again = second.length ? `; passed on the second try: ${second.join(', ')}` : '';
  return { tour: 'passed', reason: `${entries.length} steps passed${again}; Claude is checking now` };
}

/** Each `Scenario:` line's name and the verdict below it, from Claude's report. */
export function scenarioVerdicts(report) {
  const verdicts = [];
  for (const line of (report ?? '').split('\n')) {
    const name = scenarioName(line);
    if (name) verdicts.push({ name, verdict: '' });
    const verdict = line.match(/^\s*Verdict:\s*(\S+)/i)?.[1].toLowerCase();
    if (verdict && verdicts.length && !verdicts.at(-1).verdict) verdicts.at(-1).verdict = verdict;
  }
  return verdicts;
}

/** The name on a `Scenario: <name>` line, also as a Markdown heading or list item, or null. */
function scenarioName(line) {
  return line.match(/^[\s#*-]*Scenario:\**\s*(.+?)\s*$/i)?.[1].replace(/\*/g, '').trim() || null;
}

const sameName = name => name.toLowerCase().replace(/\s+/g, ' ').trim();

/** The scenarios file cut to the blocks that were not works in the last check. `carried` names the scenarios that
 * check itself skipped as passed; they count as works unless its report tried them. A block whose name the report does
 * not hold stays. Gives the text to send, the names left out, or why every scenario goes. */
export function recheckScenarios(scenarios, report, carried = []) {
  const verdicts = scenarioVerdicts(report);
  const tried = new Set(verdicts.map(each => sameName(each.name)));
  const works = new Set([
    ...verdicts.filter(each => each.verdict === 'works').map(each => sameName(each.name)),
    ...carried.map(sameName).filter(name => !tried.has(name)),
  ]);
  if (!works.size) return { scenarios, passed: [], reason: 'the last check has no scenario that works' };
  const kept = [];
  const passed = [];
  let skipping = false;
  for (const line of scenarios.split('\n')) {
    const name = scenarioName(line);
    if (name) skipping = works.has(sameName(name));
    if (name && skipping) passed.push(name);
    if (!skipping) kept.push(line);
  }
  if (!passed.length) return { scenarios, passed, reason: 'no scenario in the file matches one that worked' };
  if (!kept.some(line => scenarioName(line))) {
    return { scenarios, passed: [], reason: 'every scenario worked in the last check, so each is tried again' };
  }
  return { scenarios: kept.join('\n').trim(), passed };
}

/** The finished checks started by hand that were not cancelled, newest first. */
export function finishedChecks(runs) {
  return runs
    .filter(run => run.event === 'workflow_dispatch' && run.conclusion && !['cancelled', 'skipped'].includes(run.conclusion))
    .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
}

/** The newest finished check that reached Claude, its report, and the names it carried as passed, or null.
 * `read(run)` gives the run's `claude/report.md` and `passed-before.txt`, '' for a file it lacks. */
export function lastReport(runs, read) {
  for (const run of finishedChecks(runs)) {
    const { report, passedBefore } = read(run);
    if (!report) continue;
    // passed-before.txt: that check's own last link, then one name per line (finish.sh).
    const carried = passedBefore.split('\n').slice(1).map(name => name.trim()).filter(Boolean);
    return { run, report, carried };
  }
  return null;
}

function dispatch({ ref, sha, pr, model, scenarios, flows, passedBefore }) {
  const fields = {
    sha, model, ...(pr && { pr }), ...(scenarios && { scenarios }), ...(flows && { flows: flows.split(',').join(' ') }),
    ...(passedBefore && { passed_before: passedBefore }),
  };
  return gh(['workflow', 'run', WORKFLOW, '--ref', ref, ...Object.entries(fields).flatMap(([k, v]) => ['-f', `${k}=${v}`])]);
}

/** Puts the label on again, so GitHub sends a fresh `labeled` start. */
function label(pr) {
  gh(['label', 'create', LABEL, '--color', '1D76DB', '--description', 'Run the iPhone device check', '--force']);
  gh(['pr', 'edit', pr, '--remove-label', LABEL]);
  return gh(['pr', 'edit', pr, '--add-label', LABEL]).status === 0;
}

/** How the check started: `workflow_dispatch`, `pull_request`, or an error line. */
function start(values, scenarios, passedBefore) {
  const started = dispatch({ ...values, scenarios, passedBefore });
  if (started.status === 0) return { event: 'workflow_dispatch' };
  if (!dispatchMissing(started.stderr)) return { error: 'GitHub did not start the check' };
  if (!values.pr) return { error: 'the workflow is not on the default branch yet; give --pr to start it by the label' };
  return label(values.pr) ? { event: 'pull_request' } : { error: `could not put the "${LABEL}" label on the pull request` };
}

function listRuns(ref, event) {
  const listed = gh(['run', 'list', '--workflow', WORKFLOW, '--branch', ref, ...(event ? ['--event', event] : []),
    '--limit', '20', '--json', 'databaseId,headSha,event,createdAt,url,conclusion']);
  return listed.status === 0 ? JSON.parse(listed.stdout) : [];
}

async function waitForRun({ ref, sha }, event, after) {
  const until = Date.now() + FIND_MS;
  while (Date.now() < until) {
    const run = findRun(listRuns(ref, event), { sha, event, after });
    if (run) return run;
    await sleep(10_000);
  }
  return null;
}

/** A file of the downloaded results, or '' when the run made none. */
function readResult(folder, name) {
  try {
    return readFileSync(join(folder, name), 'utf8').trim();
  } catch {
    return '';
  }
}

/** Reads the branch's newest finished check that reached Claude and cuts the scenarios to what was not works.
 * Prints recheck= lines. */
function recheck(ref, scenarios) {
  const none = reason => {
    console.log('recheck=none');
    console.log(`recheck_reason=${reason}`);
    return { scenarios, passedBefore: '' };
  };
  if (!scenarios) return none('no --scenarios-file to cut');
  const runs = listRuns(ref, 'workflow_dispatch');
  if (!finishedChecks(runs).length) return none('no finished check of this branch');
  const last = lastReport(runs, run => {
    const folder = mkdtempSync(join(tmpdir(), 'device-check-last-'));
    gh(['run', 'download', String(run.databaseId), '-n', 'device-check-iphone', '-D', folder]);
    return { report: readResult(folder, join('claude', 'report.md')), passedBefore: readResult(folder, 'passed-before.txt') };
  });
  if (!last) return none('no finished check of this branch has a Claude report');
  const cut = recheckScenarios(scenarios, last.report, last.carried);
  if (!cut.passed.length) return none(cut.reason);
  console.log(`recheck=${last.run.url}`);
  console.log(`recheck_skipped=${cut.passed.join('; ')}`);
  return { scenarios: cut.scenarios, passedBefore: [last.run.url, ...cut.passed].join('\n') };
}

/** Downloads the run's tour file once job iphone uploads it, and prints tour= and tour_reason=. True once printed. */
function printTour(id) {
  const listed = gh(['api', `repos/{owner}/{repo}/actions/runs/${id}/artifacts`, '--jq', '.artifacts[].name']);
  if (listed.status !== 0 || !listed.stdout.split('\n').includes('device-check-tour')) return false;
  const folder = mkdtempSync(join(tmpdir(), 'device-check-tour-'));
  if (gh(['run', 'download', String(id), '-n', 'device-check-tour', '-D', folder]).status !== 0) return false;
  let entries = null;
  try {
    entries = JSON.parse(readResult(folder, 'tour.json'));
  } catch {
    // No tour.json: the tour stopped before it wrote one.
  }
  const outcome = tourOutcome(entries, { reason: readResult(folder, 'reason.txt'), crashed: !!readResult(folder, 'crash.txt') })
    ?? { tour: 'broken', reason: readResult(folder, 'reason.txt') || 'the tour did not finish' };
  console.log(`tour=${outcome.tour}`);
  console.log(`tour_reason=${outcome.reason.replace(/\s+/g, ' ')}`);
  return true;
}

/** True once `status()` says completed, false at `until` (ms). A failed read waits and asks again. */
export async function waitDone(status, { until, every = 30_000 }) {
  while (Date.now() < until) {
    if (status() === 'completed') return true;
    await sleep(every);
  }
  return false;
}

// Not `gh run watch`: it once ended with the run still going, and the check said failed.
function runStatus(id) {
  const viewed = gh(['run', 'view', String(id), '--json', 'status']);
  return viewed.status === 0 ? JSON.parse(viewed.stdout).status : '';
}

async function collect(run, { platform, ref }) {
  let toured = false;
  const status = () => {
    toured ||= printTour(run.databaseId);
    return runStatus(run.databaseId);
  };
  if (!await waitDone(status, { until: Date.now() + WATCH_MS })) {
    return { result: resultOf({ timedOut: true }) };
  }
  if (!toured) printTour(run.databaseId);
  const viewed = gh(['run', 'view', String(run.databaseId), '--json', 'jobs']);
  const jobs = viewed.status === 0 ? JSON.parse(viewed.stdout).jobs : [];
  const cancelled = jobs.some(job => job.name === platform && job.conclusion === 'cancelled');
  const folder = mkdtempSync(join(tmpdir(), 'device-check-'));
  gh(['run', 'download', String(run.databaseId), '-n', `device-check-${platform}`, '-D', folder]);
  gh(['run', 'download', String(run.databaseId), '-n', 'device-check-swift', '-D', join(folder, 'swift')]);
  const verdict = readVerdict(readResult(folder, 'verdict.txt'));
  const swiftJob = jobs.find(job => job.name === 'swift-tests');
  const swift = swiftOutcome(swiftJob?.conclusion, readResult(join(folder, 'swift'), 'swift-tests.txt'));
  const result = resultOf({ timedOut: false, cancelled, verdict, swift });
  const reason = result === 'cancelled' ? cancelReason(listRuns(ref), run)
    : result === 'broken' && verdict !== 'broken' ? "the share card's Swift tests fail: swift/swift-tests.log"
      : readResult(folder, 'reason.txt');
  return { result, folder, ...(reason && { reason }) };
}

export async function main(values, positionals) {
  const problem = checkValues(values, positionals);
  if (problem) usageError(USAGE, problem);
  const given = values['scenarios-file'] ? readFileSync(values['scenarios-file'], 'utf8').trim() : '';
  const { scenarios, passedBefore } = values.recheck ? recheck(values.ref, given) : { scenarios: given, passedBefore: '' };
  const after = Date.now() - CLOCK_SLACK_MS;
  const started = start(values, scenarios, passedBefore);
  if (started.error) return { result: 'failed', reason: started.error };
  const kind = started.event === 'workflow_dispatch' ? 'by-hand' : 'label';
  const run = await waitForRun(values, started.event, after);
  if (!run) return { result: 'failed', start: kind, reason: 'no run of this commit showed on GitHub' };
  return { start: kind, run: run.url, ...await collect(run, values) };
}

if (isMain(import.meta.url)) {
  const { values, positionals } = parseCli({
    usage: USAGE,
    allowPositionals: true,
    options: {
      ref: { type: 'string' }, sha: { type: 'string' }, pr: { type: 'string' }, 'scenarios-file': { type: 'string' },
      flows: { type: 'string' }, recheck: { type: 'boolean', default: false },
      model: { type: 'string', default: 'claude-sonnet-5-5' }, platform: { type: 'string', default: 'iphone' },
    },
  });
  const out = await main(values, positionals);
  for (const key of ['result', 'start', 'run', 'folder', 'reason']) if (out[key]) console.log(`${key}=${out[key]}`);
  if (out.result !== 'works') process.exit(1);
}
