// Run with: node --test scripts/app-release.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  MAC_DMG, compareVersions, githubNotes, groupNotes, macCheck, makeGit, markPulls, nextBeta, parseTag, planRun,
  pubspecVersion, pullNumber, releaseItems, versionLines, whatsNew, writeNotes,
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

/** Each job's `needs` and one-line `if` in a workflow file, read from its two-space job keys. */
function readJobs(file) {
  const jobs = readFileSync(new URL(`../.github/workflows/${file}`, import.meta.url), 'utf8').split(/^jobs:\n/m)[1];
  return Object.fromEntries(jobs.split(/^(?=  [a-z][\w-]*:\n)/m).filter(block => /^  [a-z]/.test(block)).map(block => {
    const needs = block.match(/^    needs: (.+)$/m)?.[1] ?? '';
    return [block.match(/^  ([\w-]+):/)[1], {
      needs: needs.replace(/[[\]]/g, '').split(',').map(name => name.trim()).filter(Boolean),
      if: block.match(/^    if: (.+)$/m)?.[1] ?? '',
    }];
  }));
}

test("a branch's builds start with the tests, and main's and a release's wait for them", () => {
  const jobs = readJobs('mobile-ci.yml');
  for (const job of ['android-branch', 'ios-branch', 'macos-branch']) {
    assert.deepEqual(jobs[job].needs, ['plan'], job);
    assert.match(jobs[job].if, /needs\.plan\.outputs\.mode == 'branch'/, job);
  }
  for (const job of ['android', 'ios', 'macos']) {
    assert.deepEqual(jobs[job].needs, ['plan', 'flutter'], job);
    assert.match(jobs[job].if, /needs\.plan\.outputs\.mode != 'branch'/, job);
  }
  assert.ok(['android', 'ios', 'macos'].every(job => jobs.release.needs.includes(job)));
});

test('only a beta from main that went to TestFlight goes to the public beta', () => {
  const job = readJobs('mobile-ci.yml')['public-beta'];
  assert.deepEqual(job.needs, ['plan', 'ios']);
  assert.match(job.if, /needs\.plan\.outputs\.mode == 'beta' && needs\.ios\.outputs\.sent == 'true'/);
  assert.doesNotMatch(job.if, /\|\||release|!=/, 'a release or a release check never sends to the public beta');
  const ios = readFileSync(new URL('../.github/workflows/mobile-ios.yml', import.meta.url), 'utf8');
  assert.match(ios, /^ {8}value: \$\{\{ jobs\.testflight\.outputs\.sent \}\}$/m);
  assert.match(ios, /^ {6}sent: \$\{\{ steps\.testflight\.outcome == 'success' \}\}$/m);
  assert.match(ios, /- name: TestFlight\n {8}id: testflight\n/);
  const fastfile = readFileSync(new URL('../mobile/ios/fastlane/Fastfile', import.meta.url), 'utf8');
  assert.match(fastfile, /^PUBLIC_BETA_GROUP = "Public beta"$/m);
  assert.match(fastfile, /^ {2}lane :public_beta do \|options\|$/m);
});

test("main's run only starts the public beta, which waits for Apple in its own group", () => {
  const ci = readFileSync(new URL('../.github/workflows/mobile-ci.yml', import.meta.url), 'utf8');
  const job = ci.split(/^ {2}public-beta:\n/m)[1].split(/^ {2}[a-z][\w-]*:\n/m)[0];
  assert.match(job, /^ {6}actions: write$/m);
  assert.match(job, /gh workflow run mobile-public-beta\.yml --ref main -f version="\$VERSION" -f build="\$BUILD" -f sha="\$GITHUB_SHA"/);
  assert.doesNotMatch(job, /fastlane|timeout-minutes/, 'the wait for Apple is not in main\'s run');
  const beta = readFileSync(new URL('../.github/workflows/mobile-public-beta.yml', import.meta.url), 'utf8');
  assert.match(beta, /^on:\n {2}(#.*\n {2})?workflow_dispatch:\n/m);
  assert.doesNotMatch(beta, /^ {2}(push|pull_request|workflow_call):/m);
  assert.match(beta, /^concurrency:\n {2}group: mobile-public-beta\n {2}cancel-in-progress: false$/m);
  assert.match(beta, /^ {4}timeout-minutes: 90$/m);
  assert.match(beta, /^ {10}ref: \$\{\{ inputs\.sha \}\}$/m);
  assert.match(beta, /bundle exec fastlane public_beta version:"\$VERSION" build:"\$BUILD" notes:/);
});

test('a release sends the App Store page before it submits, and a release check only verifies it', () => {
  const ci = readFileSync(new URL('../.github/workflows/mobile-ci.yml', import.meta.url), 'utf8');
  const job = ci.split(/^ {2}release:\n/m)[1].split(/^ {2}[a-z][\w-]*:\n/m)[0];
  const listing = job.indexOf('bundle exec fastlane listing version:"$VERSION" verify_only:"$check"');
  const submit = job.indexOf('bundle exec fastlane submit ');
  assert.ok(listing > 0 && submit > listing, 'fastlane listing runs before fastlane submit');
  const page = job.slice(job.indexOf('- name: App Store page'), job.indexOf('- name: App Store review'));
  assert.match(page, /if \[ "\$MODE" = release-check \]; then check=true; fi/);
  const fastfile = readFileSync(new URL('../mobile/ios/fastlane/Fastfile', import.meta.url), 'utf8');
  const lane = fastfile.split(/^ {2}lane :listing do \|options\|$/m)[1].split(/^ {2}end$/m)[0];
  for (const option of ['metadata_path: LISTING_METADATA', 'screenshots_path: LISTING_SCREENSHOTS',
    'app_rating_config_path: LISTING_RATING', 'overwrite_screenshots: true', 'skip_binary_upload: true',
    'submit_for_review: false', 'force: true']) assert.ok(lane.includes(option), option);
  assert.ok(lane.indexOf('check_listing(app)') < lane.indexOf('deliver('), 'verify_only stops before deliver');
  const submitLane = fastfile.split(/^ {2}lane :submit do \|options\|$/m)[1].split(/^ {2}end$/m)[0];
  assert.match(submitLane, /metadata_path: metadata,/, 'submit keeps its empty metadata folder');
  assert.match(submitLane, /skip_screenshots: true/);
});

test('mac-check passes a signed, accepted and stapled disk image, and names each check it runs', () => {
  const ran = [];
  const line = macCheck({ file: `/tmp/out/${MAC_DMG}`, exists: () => true, exec: (command, args) => ran.push([command, ...args].join(' ')) });
  assert.equal(line, 'result=checked file=Relay-Everything-Mac.dmg');
  assert.deepEqual(ran, [
    'codesign --verify --strict --verbose=2 /tmp/out/Relay-Everything-Mac.dmg',
    'spctl --assess --type open --context context:primary-signature --verbose=2 /tmp/out/Relay-Everything-Mac.dmg',
    'xcrun stapler validate /tmp/out/Relay-Everything-Mac.dmg',
  ]);
});

test('mac-check refuses an unsigned or unstapled file, another name, or no file, with the reason', () => {
  const failing = command => (cmd, args) => {
    if (cmd === command) throw Object.assign(new Error('failed'), { stderr: `${args.at(-1)}: rejected\nmore` });
  };
  const check = exec => macCheck({ file: MAC_DMG, exists: () => true, exec });
  assert.throws(() => check(failing('codesign')), /can not go to a release: it is not signed.*\(Relay-Everything-Mac\.dmg: rejected\)$/);
  assert.throws(() => check(failing('spctl')), /Gatekeeper refuses it/);
  assert.throws(() => check(failing('xcrun')), /ticket is not stapled/);
  assert.throws(() => macCheck({ file: 'relay.dmg', exists: () => true, exec: () => assert.fail('ran') }), /must be named Relay-Everything-Mac\.dmg/);
  assert.throws(() => macCheck({ file: MAC_DMG, exists: () => false, exec: () => assert.fail('ran') }), /is missing/);
});

test('only a checked Mac disk image reaches the pre-release and the release, and a branch never signs', () => {
  const ci = readFileSync(new URL('../.github/workflows/mobile-ci.yml', import.meta.url), 'utf8');
  const jobs = readJobs('mobile-ci.yml');
  assert.deepEqual(jobs['macos-beta'].needs, ['plan', 'macos', 'android']);
  assert.match(jobs['macos-beta'].if, /needs\.plan\.outputs\.mode == 'beta' && needs\.macos\.outputs\.signed == 'true'/);
  const beta = ci.split(/^ {2}macos-beta:\n/m)[1].split(/^ {2}[a-z][\w-]*:\n/m)[0];
  assert.match(beta, /TAG: mobile-v\$\{\{ needs\.plan\.outputs\.version \}\}\+\$\{\{ needs\.plan\.outputs\.build \}\}/);
  assert.match(beta, /gh release upload "\$TAG" "\$RUNNER_TEMP\/mac\/Relay-Everything-Mac\.dmg" --clobber/);
  const branch = ci.split(/^ {2}macos-branch:\n/m)[1].split(/^ {2}[a-z][\w-]*:\n/m)[0];
  assert.doesNotMatch(branch, /secrets/, 'a branch gets no secret');
  const release = ci.split(/^ {2}release:\n/m)[1];
  const steps = [...release.matchAll(/^ {6}- name: (.+)$/gm)].map(match => match[1]);
  assert.ok(steps.indexOf('Mac app on the GitHub release') > steps.indexOf('GitHub release'), steps.join(', '));
  assert.ok(steps.indexOf('Mac app on the GitHub release') < steps.indexOf('Mark the pull requests'), steps.join(', '));
  const mac = readFileSync(new URL('../.github/workflows/mobile-macos.yml', import.meta.url), 'utf8');
  assert.match(mac, /flutter build macos -t lib\/main_mac\.dart --release --build-name="\$VERSION" --build-number="\$BUILD"/);
  assert.match(mac, /if \[ "\$MODE" = branch \]; then\n {12}echo "sign=false"/);
  assert.match(mac, /--options runtime --timestamp/);
  assert.match(mac, /xcrun notarytool submit "\$DMG"/);
  assert.match(mac, /xcrun stapler staple "\$DMG"/);
  const check = mac.indexOf('app-release.mjs mac-check --file "$DMG"');
  assert.ok(check > mac.indexOf('xcrun stapler staple'), 'the check runs on the stapled file');
  assert.ok(check < mac.indexOf('name: relay-everything-mac\n'), 'the file is kept only after the check');
  assert.match(mac, /- name: File for the release\n {8}if: steps\.check\.outcome == 'success'/);
});
