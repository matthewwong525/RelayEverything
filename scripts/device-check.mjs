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
       [--model <id>] [--platform iphone]

Starts .github/workflows/mobile-device-check.yml on the branch for the saved commit, waits up to 50 minutes, and
downloads the report, pictures and video to a new temporary folder. Until the workflow is on the default branch,
GitHub can't start it by hand: with --pr, the check then starts by the "check on iPhone" label, and Claude reads the
open change's specs in place of --scenarios-file. Prints result=works|broken|could-not-check|no-verdict|cancelled|
timeout|failed, start=, run=, folder= and reason=. Exits 0 only on works.`;

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
  return null;
}

function dispatch({ ref, sha, pr, model, scenarios }) {
  const fields = { sha, model, ...(pr && { pr }), ...(scenarios && { scenarios }) };
  return gh(['workflow', 'run', WORKFLOW, '--ref', ref, ...Object.entries(fields).flatMap(([k, v]) => ['-f', `${k}=${v}`])]);
}

/** Puts the label on again, so GitHub sends a fresh `labeled` start. */
function label(pr) {
  gh(['label', 'create', LABEL, '--color', '1D76DB', '--description', 'Run the iPhone device check', '--force']);
  gh(['pr', 'edit', pr, '--remove-label', LABEL]);
  return gh(['pr', 'edit', pr, '--add-label', LABEL]).status === 0;
}

/** How the check started: `workflow_dispatch`, `pull_request`, or an error line. */
function start(values, scenarios) {
  const started = dispatch({ ...values, scenarios });
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

function collect(run, { platform, ref }) {
  const watch = gh(['run', 'watch', String(run.databaseId), '--exit-status', '--interval', '30'], { stdio: 'ignore', timeout: WATCH_MS });
  if (watch.error?.code === 'ETIMEDOUT') return { result: resultOf({ timedOut: true }) };
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
  const scenarios = values['scenarios-file'] ? readFileSync(values['scenarios-file'], 'utf8').trim() : '';
  const after = Date.now() - CLOCK_SLACK_MS;
  const started = start(values, scenarios);
  if (started.error) return { result: 'failed', reason: started.error };
  const kind = started.event === 'workflow_dispatch' ? 'by-hand' : 'label';
  const run = await waitForRun(values, started.event, after);
  if (!run) return { result: 'failed', start: kind, reason: 'no run of this commit showed on GitHub' };
  return { start: kind, run: run.url, ...collect(run, values) };
}

if (isMain(import.meta.url)) {
  const { values, positionals } = parseCli({
    usage: USAGE,
    allowPositionals: true,
    options: {
      ref: { type: 'string' }, sha: { type: 'string' }, pr: { type: 'string' }, 'scenarios-file': { type: 'string' },
      model: { type: 'string', default: 'claude-sonnet-5-5' }, platform: { type: 'string', default: 'iphone' },
    },
  });
  const out = await main(values, positionals);
  for (const key of ['result', 'start', 'run', 'folder', 'reason']) if (out[key]) console.log(`${key}=${out[key]}`);
  if (out.result !== 'works') process.exit(1);
}
