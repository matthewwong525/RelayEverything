// Run with: node --test scripts/app-release.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  compareVersions, githubNotes, groupNotes, makeGit, markPulls, nextBeta, parseTag, planRun, pubspecVersion,
  pullNumber, releaseItems, versionLines, whatsNew, writeNotes,
} from './app-release.mjs';

const REPO = 'matthewwong525/RelayEverything';
const TAGS = ['mobile-v1.0.0+96', 'v1.0.0', 'v1.1.0', 'v1.9.0'];
const plan = opts => planRun({ build: '120', tags: TAGS, pubspecVersion: '1.0.0', isOnMain: () => true, ...opts });

/** A temporary repository: each commit writes one file and takes the subject given. */
function tempRepo(commits) {
  const dir = mkdtempSync(join(tmpdir(), 'app-release-'));
  const env = { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@example.com', GIT_COMMITTER_NAME: 't',
    GIT_COMMITTER_EMAIL: 't@example.com' };
  const run = args => execFileSync('git', args, { cwd: dir, env, stdio: 'pipe' });
  run(['init', '-q', '-b', 'main']);
  commits.forEach(([path, subject, tag], n) => {
    mkdirSync(join(dir, path, '..'), { recursive: true });
    writeFileSync(join(dir, path), String(n));
    run(['add', '.']);
    run(['commit', '-q', '-m', subject]);
    if (tag) run(['tag', tag]);
  });
  return { dir, git: makeGit(dir), done: () => rmSync(dir, { recursive: true, force: true }) };
}

/** A fake `gh`: pull requests by number, and every call recorded. */
function fakeGh(pulls) {
  const calls = [];
  const gh = args => {
    calls.push(args.join(' '));
    const pull = pulls[args[2]];
    if (args[0] === 'pr' && args[1] === 'view') {
      if (!pull) throw new Error('no pull request found');
      return JSON.stringify(args.includes('comments') ? { comments: pull.comments ?? [] } : pull);
    }
    return '';
  };
  return { gh, calls };
}

test('release tags sort by semver, and a beta tag is not a release tag', () => {
  assert.deepEqual(parseTag('v1.10.0'), [1, 10, 0]);
  assert.ok(compareVersions(parseTag('v1.10.0'), parseTag('v1.9.0')) > 0);
  assert.equal(parseTag('mobile-v1.0.0+96'), null);
  assert.equal(parseTag('v1.0'), null);
  assert.equal(plan({ ref: 'refs/tags/v1.10.0' }).previous_tag, 'v1.9.0');
});

test('a beta after v1.1.0 is 1.1.1, and with no release tag it is the pubspec.yaml version', () => {
  assert.equal(nextBeta(['v1.0.0', 'v1.1.0'], '1.0.0'), '1.1.1');
  assert.equal(nextBeta(['mobile-v1.0.0+96'], '1.0.0'), '1.0.0');
  assert.equal(pubspecVersion('name: relay\nversion: 1.0.0+1\n'), '1.0.0');
  assert.deepEqual(plan({ ref: 'refs/heads/main', event: 'push' }),
    { mode: 'beta', version: '1.9.1', build: '120', tag: '', previous_tag: 'v1.9.0' });
  assert.equal(plan({ ref: 'refs/heads/main', event: 'pull_request' }).mode, 'branch');
  assert.equal(plan({ ref: 'refs/heads/feature', event: 'push', tags: [] }).version, '1.0.0');
});

test('a tag on main releases its own version', () => {
  assert.deepEqual(plan({ ref: 'refs/tags/v2.0.0', event: 'push' }),
    { mode: 'release', version: '2.0.0', build: '120', tag: 'v2.0.0', previous_tag: 'v1.9.0' });
  assert.equal(plan({ ref: 'refs/tags/v1.0.0', tags: ['v1.0.0', 'mobile-v1.0.0+96'] }).previous_tag, '');
});

test('a bad, off-main or not-higher tag is refused with the reason', () => {
  assert.throws(() => plan({ ref: 'refs/tags/v2.0' }), /not a release tag/);
  assert.throws(() => plan({ ref: 'refs/tags/v2.0.0', isOnMain: () => false }), /not on main/);
  assert.throws(() => plan({ ref: 'refs/tags/v1.2.0' }), /not higher than v1\.9\.0/);
  assert.throws(() => plan({ ref: 'refs/tags/v1.1.0' }), /not higher than v1\.9\.0/);
  assert.equal(plan({ ref: 'refs/tags/v1.9.0' }).previous_tag, 'v1.1.0', 'the run\'s own tag is not an earlier one');
  assert.throws(() => plan({ ref: 'refs/heads/main', build: '' }), /build number/);
});

test('a release check skips the tag checks and uses the next beta version', () => {
  const isOnMain = () => assert.fail('a release check reads no tag');
  assert.deepEqual(plan({ ref: 'refs/heads/main', event: 'workflow_dispatch', releaseCheck: true, isOnMain }),
    { mode: 'release-check', version: '1.9.1', build: '120', tag: 'v1.9.1', previous_tag: 'v1.9.0' });
});

test('a release check from a branch or a tag is refused, as its build goes to TestFlight', () => {
  for (const ref of ['refs/heads/feature', 'refs/tags/v2.0.0', '']) {
    assert.throws(() => plan({ ref, event: 'workflow_dispatch', releaseCheck: true }), /runs only from main/);
  }
});

test('version reads the tags and refuses a tag on a commit off main', () => {
  const repo = tempRepo([['mobile/a', 'first', 'v1.0.0'], ['mobile/b', 'second', 'v1.1.0']]);
  try {
    const sha = repo.git(['rev-parse', 'HEAD']).trim();
    repo.git(['branch', 'origin/main', 'HEAD~1']);
    const args = { git: repo.git, sha, event: 'push', build: '7', pubspecText: 'version: 1.0.0+1\n' };
    assert.equal(versionLines({ ...args, ref: 'refs/heads/main' }),
      'mode=beta\nversion=1.1.1\nbuild=7\ntag=\nprevious_tag=v1.1.0');
    assert.throws(() => versionLines({ ...args, ref: 'refs/tags/v1.1.0' }), /not on main/);
    repo.git(['branch', '-f', 'origin/main', 'HEAD']);
    assert.match(versionLines({ ...args, ref: 'refs/tags/v1.1.0' }), /^mode=release\nversion=1\.1\.0\n.*previous_tag=v1\.0\.0$/s);
  } finally {
    repo.done();
  }
});

test('a squash merge gives its pull request number; another commit gives none', () => {
  assert.equal(pullNumber('Sign iPhone builds with one saved certificate (#53)'), 53);
  assert.equal(pullNumber('Fix (#12) in the middle'), null);
  assert.equal(pullNumber('Bump the app'), null);
});

test('notes list the app changes since the last tag, grouped by label, and leave out server-only commits', () => {
  const repo = tempRepo([
    ['mobile/a', 'Old app work (#40)', 'v1.0.0'],
    ['mobile/b', 'Edit notes like Apple Notes (#55)'],
    ['app/server.ts', 'Server only change (#56)'],
    ['mobile/c', 'Fix the share sheet (#57)'],
    ['mobile/d', 'Bump the app by hand'],
    ['site/x.md', 'Website only'],
  ]);
  const pulls = {
    55: { title: 'Edit notes like `Apple Notes`', labels: [{ name: 'enhancement' }] },
    57: { title: 'Fix the share sheet', labels: [{ name: 'bug' }] },
  };
  const out = mkdtempSync(join(tmpdir(), 'app-release-out-'));
  try {
    const { gh } = fakeGh(pulls);
    const items = releaseItems({ git: repo.git, gh, repo: REPO, previous: 'v1.0.0', to: 'HEAD' });
    assert.deepEqual(items.map(item => item.ref.startsWith('#') ? item.ref : item.title), ['#55', '#57', 'Bump the app by hand']);
    assert.deepEqual(groupNotes(items).map(group => [group.heading, group.items.length]), [['New', 1], ['Fixes', 1], ['Changes', 1]]);
    writeNotes({ git: repo.git, gh, repo: REPO, version: '1.1.0', previous: 'v1.0.0', to: 'HEAD', out });
    const notes = readFileSync(join(out, 'notes.md'), 'utf8');
    assert.match(notes, /^## New\n- Edit notes like `Apple Notes` \(\[#55\]\(https:\/\/github\.com\/[^)]+\/pull\/55\)\)/);
    assert.match(notes, /## Changes\n- Bump the app by hand \(\[[0-9a-f]{7}\]\(https:\/\/github\.com\/.+\/commit\/[0-9a-f]{40}\)\)/);
    assert.ok(notes.endsWith(`**Full list**: https://github.com/${REPO}/compare/v1.0.0...v1.1.0\n`));
    assert.doesNotMatch(notes, /Server only|Website only|#40/);
    assert.equal(readFileSync(join(out, 'whats-new.txt'), 'utf8'),
      'New\n- Edit notes like Apple Notes (#55)\n\nFixes\n- Fix the share sheet (#57)\n\nChanges\n- Bump the app by hand\n');
    const first = releaseItems({ git: repo.git, gh, repo: REPO, previous: '', to: 'HEAD' });
    assert.equal(first[0].title, 'Old app work', 'with no tag, all history; a pull request gh can not read keeps its line');
  } finally {
    repo.done();
    rmSync(out, { recursive: true, force: true });
  }
});

test("What's New stays within 4,000 characters and links to the rest", () => {
  const items = Array.from({ length: 200 }, (_, n) => ({ number: n + 1, title: `A change with a long enough title ${n}`, labels: [] }));
  const link = `https://github.com/${REPO}/releases/tag/v1.1.0`;
  const text = whatsNew(groupNotes(items), link);
  assert.ok(text.length <= 4000, `${text.length} characters`);
  assert.ok(text.endsWith(`\n…and more: ${link}`));
  assert.equal(whatsNew([], link), 'Small fixes and improvements.');
  assert.equal(githubNotes([], 'L'), 'No changes to the app.\n\n**Full list**: L\n');
});

test('mark labels each pull request and comments once, skipping one that has the marker', () => {
  const repo = tempRepo([['mobile/a', 'Base', 'v1.0.0'], ['mobile/b', 'One (#55)'], ['mobile/c', 'Two (#57)'], ['mobile/d', 'No pull']]);
  const marker = '<!-- relay-everything-release v1.1.0 -->';
  const { gh, calls } = fakeGh({
    55: { title: 'One', labels: [], comments: [{ body: `Released in Relay Everything 1.1.0\n\n${marker}` }] },
    57: { title: 'Two', labels: [], comments: [{ body: 'Looks good' }] },
  });
  try {
    const line = markPulls({ git: repo.git, gh, repo: REPO, version: '1.1.0', previous: 'v1.0.0', to: 'HEAD' });
    assert.equal(line, 'result=marked prs=2 commented=1');
    assert.ok(calls.some(call => call.startsWith('label create released')));
    assert.deepEqual(calls.filter(call => call.includes('--add-label')).map(call => call.split(' ')[2]), ['55', '57']);
    const comments = calls.filter(call => call.startsWith('pr comment'));
    assert.equal(comments.length, 1);
    assert.match(comments[0], /^pr comment 57 .*Released in Relay Everything 1\.1\.0: https:\/\/github\.com\/.+\/releases\/tag\/v1\.1\.0/s);
    assert.ok(comments[0].includes(marker));
  } finally {
    repo.done();
  }
});
