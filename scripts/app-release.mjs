#!/usr/bin/env node
// The phone app's release steps for .github/workflows/mobile-ci.yml: the run's version, the release notes, the marks on
// released pull requests, the check of the Mac app's disk image, and its update feed. mobile/README.md says how a release runs.
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { isMain, parseCli, usageError } from './lib-cli.mjs';
import { NAME as SPARKLE_KEY, edSignature } from './sparkle-key.mjs';

const USAGE = `usage: node scripts/app-release.mjs <version|notes|mark|mac-check|mac-feed> [options]

version  Prints mode, version, build, tag and previous_tag as key=value lines for $GITHUB_OUTPUT.
         Takes --ref (GITHUB_REF), --sha (GITHUB_SHA), --event (GITHUB_EVENT_NAME), --build (GITHUB_RUN_NUMBER)
         and --release-check true|false (RELEASE_CHECK; only from refs/heads/main). A tag that is not vX.Y.Z, is not on origin/main, or is
         not higher than the newest earlier v tag exits 1 with the reason.
notes    Writes notes.md (GitHub) and whats-new.txt (App Store) to --out (default .) for --version, from the
         commits that changed mobile/ after --previous-tag up to --to (GITHUB_SHA, else HEAD). --repo
         (GITHUB_REPOSITORY) names the repository for links.
mark     Labels each pull request in those notes "released" and comments once with the version. Same options.
mac-check  On a Mac: exits 1 unless --file is Relay-Everything-Mac.dmg, signed, accepted by Gatekeeper as checked by
         Apple, and stapled, and each of Sparkle's helpers in the app is signed by the app's own team. Only a file that
         passes goes to a GitHub release.
mac-feed Adds --file, the Mac app of --version and --build on the release --tag, to the update feed --feed (appcast.xml,
         made when missing), signed with SPARKLE_ED_PRIVATE_KEY. --channel is release or beta; --notes is a text file of
         what is new. Keeps the newest 10 of each channel. Prints newest=true when no item in the feed has a higher
         build, so only then does the file replace the website's download.`;

const TAG = /^v(\d+)\.(\d+)\.(\d+)$/;
/** The Mac app's one file on each GitHub release; the website's *Download for Mac* link names it. */
export const MAC_DMG = 'Relay-Everything-Mac.dmg';
const WHATS_NEW_LIMIT = 4000;
const HEADINGS = ['New', 'Fixes', 'Changes'];

/** `[major, minor, patch]` for a release tag such as `v1.10.0`, else null: `mobile-v1.0.0+96` is a beta tag. */
export function parseTag(name) {
  const match = TAG.exec(name);
  return match ? match.slice(1).map(Number) : null;
}

/** Semver order, so `v1.10.0` is above `v1.9.0`. */
export function compareVersions(a, b) {
  const at = a.findIndex((part, i) => part !== b[i]);
  return at === -1 ? 0 : a[at] - b[at];
}

/** The highest release tag in `tags`, leaving out `except`; '' when there is none. */
export function newestTag(tags, except) {
  const releases = tags.filter(tag => tag !== except && parseTag(tag));
  return releases.sort((a, b) => compareVersions(parseTag(b), parseTag(a)))[0] ?? '';
}

/** A build that is not a release: patch + 1 on the newest tag, since Apple takes no build for a live version. */
export function nextBeta(tags, pubspecVersion) {
  const newest = newestTag(tags);
  if (!newest) return pubspecVersion;
  const [major, minor, patch] = parseTag(newest);
  return [major, minor, patch + 1].join('.');
}

/** The `plan` job's outputs; throws with the reason a tag can not release. `isOnMain` runs only for a tag. */
export function planRun({ ref = '', event = '', releaseCheck = false, build, tags, pubspecVersion, isOnMain }) {
  if (!/^\d+$/.test(String(build ?? ''))) throw new Error(`the build number must be a whole number, not "${build ?? ''}"`);
  const result = (mode, version, previous, tag = '') => ({ mode, version, build: String(build), tag, previous_tag: previous });
  if (releaseCheck) {
    // Its iPhone build goes to TestFlight with the betas, so only main's code may run it.
    if (ref !== 'refs/heads/main') throw new Error('a release check runs only from main: start it with --ref main');
    const version = nextBeta(tags, pubspecVersion);
    return result('release-check', version, newestTag(tags), `v${version}`);
  }
  if (ref.startsWith('refs/tags/')) {
    const tag = ref.slice('refs/tags/'.length);
    const parts = parseTag(tag);
    if (!parts) throw new Error(`${tag} is not a release tag: name it v<major>.<minor>.<patch>, such as v1.1.0`);
    if (!isOnMain()) throw new Error(`${tag} is on a commit that is not on main: tag a commit on main`);
    const previous = newestTag(tags, tag);
    if (previous && compareVersions(parts, parseTag(previous)) <= 0) {
      throw new Error(`${tag} is not higher than ${previous}, the newest release: use a higher version`);
    }
    return result('release', parts.join('.'), previous, tag);
  }
  const mode = ref === 'refs/heads/main' && event === 'push' ? 'beta' : 'branch';
  return result(mode, nextBeta(tags, pubspecVersion), newestTag(tags));
}

/** The version name in `pubspec.yaml`, without its build number. */
export function pubspecVersion(text) {
  const match = /^version:\s*(\d+\.\d+\.\d+)/m.exec(text);
  if (!match) throw new Error('mobile/pubspec.yaml has no version line');
  return match[1];
}

export const makeGit = cwd => args => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const defaultGh = args => execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });

/** True when `sha` is on `branch`. Exit 1 means no; any other failure, such as a missing branch, throws. */
export function isAncestor(git, sha, branch = 'origin/main') {
  try {
    git(['merge-base', '--is-ancestor', sha, branch]);
    return true;
  } catch (error) {
    if (error.status === 1) return false;
    throw error;
  }
}

/** `version`: reads the tags and pubspec.yaml through `git`, and returns the key=value lines. */
export function versionLines({ git, ref, sha, event, build, releaseCheck, pubspecText }) {
  const tags = git(['tag', '--list', 'v*']).split('\n').filter(Boolean);
  const plan = planRun({
    ref, event, releaseCheck, build, tags, pubspecVersion: pubspecVersion(pubspecText),
    isOnMain: () => isAncestor(git, sha || 'HEAD'),
  });
  return Object.entries(plan).map(([key, value]) => `${key}=${value}`).join('\n');
}

/** The commits that changed `mobile/` after `previous` up to `to`, oldest first; no `previous` takes all history. */
export function commitsForApp(git, previous, to) {
  const range = previous ? `${previous}..${to}` : to;
  return git(['log', '--reverse', '--format=%H%x1f%s', range, '--', 'mobile/'])
    .split('\n')
    .filter(Boolean)
    .map(line => {
      const [sha, subject] = line.split('\x1f');
      return { sha, subject };
    });
}

/** The pull request number a squash merge puts at the end of its subject, `… (#53)`; null when there is none. */
export function pullNumber(subject) {
  const match = /\(#(\d+)\)\s*$/.exec(subject);
  return match ? Number(match[1]) : null;
}

function pullItem(gh, repo, number, subject) {
  const base = { number, url: `https://github.com/${repo}/pull/${number}`, ref: `#${number}` };
  try {
    const pull = JSON.parse(gh(['pr', 'view', String(number), '--repo', repo, '--json', 'title,labels']));
    return { ...base, title: pull.title, labels: pull.labels.map(label => label.name) };
  } catch (error) {
    process.stderr.write(`app-release: #${number}: ${error.message.split('\n')[0]}; the notes use the commit's line\n`);
    return { ...base, title: subject.replace(/\s*\(#\d+\)\s*$/, ''), labels: [] };
  }
}

/** One entry per pull request, by its title and labels from `gh`; a commit with no pull request keeps its line. */
export function releaseItems({ git, gh, repo, previous, to }) {
  const seen = new Set();
  const items = [];
  for (const { sha, subject } of commitsForApp(git, previous, to)) {
    const number = pullNumber(subject);
    if (number === null) {
      items.push({ number: null, title: subject, labels: [], url: `https://github.com/${repo}/commit/${sha}`, ref: sha.slice(0, 7) });
    } else if (!seen.has(number)) {
      seen.add(number);
      items.push(pullItem(gh, repo, number, subject));
    }
  }
  return items;
}

const headingFor = labels => (labels.includes('enhancement') ? 'New' : labels.includes('bug') ? 'Fixes' : 'Changes');

/** Items by label: `enhancement` is New, `bug` is Fixes, the rest Changes; empty groups dropped. */
export function groupNotes(items) {
  return HEADINGS.map(heading => ({ heading, items: items.filter(item => headingFor(item.labels) === heading) }))
    .filter(group => group.items.length);
}

export function releaseLinks(repo, version, previous) {
  const tag = `v${version}`;
  return {
    release: `https://github.com/${repo}/releases/tag/${tag}`,
    full: previous ? `https://github.com/${repo}/compare/${previous}...${tag}` : `https://github.com/${repo}/commits/${tag}`,
  };
}

export function githubNotes(groups, fullLink) {
  const sections = groups.map(group =>
    [`## ${group.heading}`, ...group.items.map(item => `- ${item.title} ([${item.ref}](${item.url}))`)].join('\n'));
  return [...(sections.length ? sections : ['No changes to the app.']), `**Full list**: ${fullLink}`].join('\n\n') + '\n';
}

/** Plain text for App Store What's New, at most `limit` characters, cut at a line with a link to the rest. */
export function whatsNew(groups, releaseLink, limit = WHATS_NEW_LIMIT) {
  const lines = groups.flatMap((group, n) => [
    ...(n ? [''] : []),
    group.heading,
    ...group.items.map(item => `- ${item.title.replace(/[`*]/g, '')}${item.number ? ` (#${item.number})` : ''}`),
  ]);
  if (!lines.length) return 'Small fixes and improvements.';
  const more = `…and more: ${releaseLink}`;
  const kept = [];
  for (const line of lines) {
    if ([...kept, line, more].join('\n').length > limit) return [...kept, more].join('\n');
    kept.push(line);
  }
  return kept.join('\n');
}

/** `notes`: writes notes.md and whats-new.txt into `out` and returns their paths. */
export function writeNotes({ git, gh = defaultGh, repo, version, previous, to, out = '.' }) {
  const groups = groupNotes(releaseItems({ git, gh, repo, previous, to }));
  const links = releaseLinks(repo, version, previous);
  const files = [join(out, 'notes.md'), join(out, 'whats-new.txt')];
  writeFileSync(files[0], githubNotes(groups, links.full));
  writeFileSync(files[1], `${whatsNew(groups, links.release)}\n`);
  return files;
}

/** `mark`: the label `released` and one comment per pull request; the marker in the comment stops a second one. */
export function markPulls({ git, gh = defaultGh, repo, version, previous, to }) {
  const marker = `<!-- relay-everything-release v${version} -->`;
  const body = `Released in Relay Everything ${version}: ${releaseLinks(repo, version, previous).release}\n\n${marker}`;
  const pulls = releaseItems({ git, gh, repo, previous, to }).filter(item => item.number !== null);
  gh(['label', 'create', 'released', '--repo', repo, '--force', '--color', '0E8A16', '--description', 'In a Relay Everything release']);
  let commented = 0;
  for (const { number } of pulls) {
    const id = String(number);
    gh(['pr', 'edit', id, '--repo', repo, '--add-label', 'released']);
    const { comments } = JSON.parse(gh(['pr', 'view', id, '--repo', repo, '--json', 'comments']));
    if (comments.some(comment => comment.body.includes(marker))) continue;
    gh(['pr', 'comment', id, '--repo', repo, '--body', body]);
    commented += 1;
  }
  return `result=marked prs=${pulls.length} commented=${commented}`;
}

/** What a Mac disk image passes before a release takes it: a valid signature, Gatekeeper's yes, and Apple's ticket. */
export const macChecks = file => [
  { what: 'it is not signed, or its signature is broken', command: 'codesign', args: ['--verify', '--strict', '--verbose=2', file] },
  { what: 'Gatekeeper refuses it: it is not signed with Developer ID, or Apple did not accept it',
    command: 'spctl', args: ['--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', file] },
  { what: "Apple's ticket is not stapled to it", command: 'xcrun', args: ['stapler', 'validate', file] },
];

/** Sparkle's helpers in the app, each signed on its own before Sparkle.framework (mobile-macos.yml). */
export const SPARKLE_HELPERS = ['XPCServices/Installer.xpc', 'XPCServices/Downloader.xpc', 'Autoupdate', 'Updater.app']
  .map(path => `Contents/Frameworks/Sparkle.framework/Versions/B/${path}`);
const MAC_APP = 'Relay Everything.app';

// codesign --display writes its lines to stderr, so a run's output is both.
function defaultExec(command, args) {
  const run = spawnSync(command, args, { encoding: 'utf8' });
  if (run.status !== 0) throw Object.assign(new Error(`${command} failed`), { stderr: run.stderr ?? run.error?.message });
  return `${run.stdout}${run.stderr}`;
}

function checked(exec, what, command, args) {
  try {
    return `${exec(command, args) ?? ''}`;
  } catch (error) {
    const detail = `${error.stderr ?? ''}`.trim().split('\n')[0];
    throw new Error(`${MAC_DMG} can not go to a release: ${what}${detail ? ` (${detail})` : ''}`);
  }
}

/** The signing team of `path`, from `codesign --display`; '' when it has none, as an unsigned or ad hoc file. */
function teamOf(exec, path) {
  const out = checked(exec, `${basename(path)} is not signed`, 'codesign', ['--display', '--verbose=2', path]);
  const team = /^TeamIdentifier=(.+)$/m.exec(out)?.[1].trim() ?? '';
  return team === 'not set' ? '' : team;
}

/** Each of Sparkle's helpers in the app on the mounted disk image: a valid signature by the app's own team. */
function checkHelpers(exec, mount) {
  const app = join(mount, MAC_APP);
  const team = teamOf(exec, app);
  for (const helper of SPARKLE_HELPERS) {
    const path = join(app, helper);
    checked(exec, `Sparkle's ${basename(helper)} is not signed, or its signature is broken`, 'codesign',
      ['--verify', '--strict', '--deep', '--verbose=2', path]);
    if (!team || teamOf(exec, path) !== team) {
      throw new Error(`${MAC_DMG} can not go to a release: Sparkle's ${basename(helper)} is not signed by the app's team ${team || '(none)'}`);
    }
  }
}

/** `mac-check`: runs each of [macChecks] through `exec`, then [checkHelpers] in the mounted image, and throws with the
 * first reason the file can not go out. */
export function macCheck({ file, exec = defaultExec, exists = existsSync, mount = () => mkdtempSync(join(tmpdir(), 'relay-dmg-')) }) {
  if (basename(file ?? '') !== MAC_DMG) throw new Error(`the Mac app's file must be named ${MAC_DMG}, not "${basename(file ?? '')}"`);
  if (!exists(file)) throw new Error(`${file} is missing`);
  for (const { what, command, args } of macChecks(file)) checked(exec, what, command, args);
  const at = mount();
  checked(exec, 'it does not open', 'hdiutil', ['attach', file, '-nobrowse', '-readonly', '-noautoopen', '-mountpoint', at]);
  try {
    checkHelpers(exec, at);
  } finally {
    exec('hdiutil', ['detach', at, '-force']);
    rmSync(at, { recursive: true, force: true });
  }
  return `result=checked file=${MAC_DMG}`;
}

/** How many items of each channel the feed keeps. */
export const FEED_KEEP = 10;
const SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle';

const xmlText = value => String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** The macOS version the app needs, from the Runner's `MACOSX_DEPLOYMENT_TARGET`. */
export function minimumMacos(pbxproj) {
  const match = /MACOSX_DEPLOYMENT_TARGET = ([\d.]+);/.exec(pbxproj);
  if (!match) throw new Error('mobile/macos/Runner.xcodeproj has no MACOSX_DEPLOYMENT_TARGET');
  return match[1];
}

/** One feed item: a release has no channel, a test build is `beta`. The enclosure is the file on its own release. */
export function feedItem({ version, build, url, length, signature, channel, notes, minimum, date }) {
  return [
    '    <item>',
    `      <title>Relay Everything ${xmlText(version)} (${xmlText(build)})</title>`,
    `      <pubDate>${date.toUTCString()}</pubDate>`,
    `      <sparkle:version>${xmlText(build)}</sparkle:version>`,
    `      <sparkle:shortVersionString>${xmlText(version)}</sparkle:shortVersionString>`,
    `      <sparkle:minimumSystemVersion>${xmlText(minimum)}</sparkle:minimumSystemVersion>`,
    ...(channel === 'beta' ? ['      <sparkle:channel>beta</sparkle:channel>'] : []),
    `      <description sparkle:format="plain-text"><![CDATA[${notes.replaceAll(']]>', ']] >')}]]></description>`,
    `      <enclosure url="${xmlText(url)}" length="${length}" type="application/octet-stream" sparkle:edSignature="${signature}"/>`,
    '    </item>',
  ].join('\n');
}

const itemsOf = xml => xml.match(/^ {4}<item>[\s\S]*?<\/item>$/gm) ?? [];
const buildOf = item => Number(/<sparkle:version>(\d+)<\/sparkle:version>/.exec(item)?.[1] ?? 0);
const channelOf = item => /<sparkle:channel>([^<]+)<\/sparkle:channel>/.exec(item)?.[1] ?? 'release';

/** The feed with `item` first, its build's earlier item dropped, and the newest [FEED_KEEP] of each channel kept;
 * `newest` is true when no other item has a higher build. */
export function addToFeed(xml, item) {
  const build = buildOf(item);
  const others = itemsOf(xml ?? '').filter(old => buildOf(old) !== build);
  const kept = [item, ...others].sort((a, b) => buildOf(b) - buildOf(a))
    .filter((one, at, all) => all.slice(0, at).filter(newer => channelOf(newer) === channelOf(one)).length < FEED_KEEP);
  return {
    xml: ['<?xml version="1.0" encoding="utf-8"?>', `<rss version="2.0" xmlns:sparkle="${SPARKLE_NS}">`, '  <channel>',
      '    <title>Relay Everything for Mac</title>', ...kept, '  </channel>', '</rss>', ''].join('\n'),
    newest: others.every(old => buildOf(old) < build),
  };
}

/** `mac-feed`: signs the disk image and writes the feed with its item; returns the result= line. */
export function macFeed({ file, feed, version, build, tag, channel, notes, repo, seed, minimum, date = new Date() }) {
  if (!['release', 'beta'].includes(channel)) throw new Error(`--channel must be release or beta, not "${channel}"`);
  if (!/^\d+$/.test(String(build))) throw new Error(`the build number must be a whole number, not "${build}"`);
  if (!seed) throw new Error(`${SPARKLE_KEY} is missing: add it to this repository's secrets (node scripts/sparkle-key.mjs)`);
  const bytes = readFileSync(file);
  const url = `https://github.com/${repo}/releases/download/${encodeURIComponent(tag)}/${MAC_DMG}`;
  const item = feedItem({ version, build, url, length: bytes.length, signature: edSignature(seed, bytes), channel,
    notes: readFileSync(notes, 'utf8').trim(), minimum, date });
  const { xml, newest } = addToFeed(existsSync(feed) ? readFileSync(feed, 'utf8') : '', item);
  writeFileSync(feed, xml);
  return `result=written items=${itemsOf(xml).length} newest=${newest}`;
}

function required(values, name) {
  if (!values[name]) usageError(USAGE, `${name} is missing`);
  return values[name];
}

if (isMain(import.meta.url)) {
  const env = process.env;
  const { values, positionals } = parseCli({
    usage: USAGE,
    allowPositionals: true,
    options: {
      ref: { type: 'string', default: env.GITHUB_REF ?? '' },
      sha: { type: 'string', default: env.GITHUB_SHA ?? '' },
      event: { type: 'string', default: env.GITHUB_EVENT_NAME ?? '' },
      build: { type: 'string', default: env.GITHUB_RUN_NUMBER ?? '' },
      'release-check': { type: 'string', default: env.RELEASE_CHECK ?? 'false' },
      version: { type: 'string' },
      'previous-tag': { type: 'string', default: '' },
      to: { type: 'string', default: env.GITHUB_SHA || 'HEAD' },
      repo: { type: 'string', default: env.GITHUB_REPOSITORY ?? '' },
      out: { type: 'string', default: '.' },
      file: { type: 'string' },
      feed: { type: 'string' },
      tag: { type: 'string' },
      channel: { type: 'string' },
      notes: { type: 'string' },
    },
  });
  const [command] = positionals;
  // Read only when a command uses git, so mac-check runs on a folder with no history.
  let top;
  const root = () => (top ??= execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim());
  const notesArgs = () => ({
    git: makeGit(root()), repo: required(values, 'repo'), version: required(values, 'version'), previous: values['previous-tag'],
    to: values.to,
  });
  try {
    if (command === 'mac-check') {
      console.log(macCheck({ file: required(values, 'file') }));
    } else if (command === 'mac-feed') {
      console.log(macFeed({
        file: required(values, 'file'), feed: required(values, 'feed'), version: required(values, 'version'),
        build: required(values, 'build'), tag: required(values, 'tag'), channel: required(values, 'channel'),
        notes: required(values, 'notes'), repo: required(values, 'repo'), seed: env[SPARKLE_KEY],
        minimum: minimumMacos(readFileSync(join(root(), 'mobile/macos/Runner.xcodeproj/project.pbxproj'), 'utf8')),
      }));
    } else if (command === 'version') {
      console.log(versionLines({
        git: makeGit(root()), ref: values.ref, sha: values.sha, event: values.event, build: values.build,
        releaseCheck: values['release-check'] === 'true', pubspecText: readFileSync(join(root(), 'mobile/pubspec.yaml'), 'utf8'),
      }));
    } else if (command === 'notes') {
      console.log(`result=written files=${writeNotes({ ...notesArgs(), out: values.out }).join(',')}`);
    } else if (command === 'mark') {
      console.log(markPulls(notesArgs()));
    } else {
      usageError(USAGE, `unknown command: ${command ?? '(none)'}`);
    }
  } catch (error) {
    console.error(`app-release: ${error.message}`);
    process.exit(1);
  }
}
