#!/usr/bin/env node
// The phone app's release steps for .github/workflows/mobile-ci.yml: the run's version, the release notes, and
// the marks on released pull requests. mobile/README.md says how a release runs.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { isMain, parseCli, usageError } from './lib-cli.mjs';

const USAGE = `usage: node scripts/app-release.mjs <version|notes|mark> [options]

version  Prints mode, version, build, tag and previous_tag as key=value lines for $GITHUB_OUTPUT.
         Takes --ref (GITHUB_REF), --sha (GITHUB_SHA), --event (GITHUB_EVENT_NAME), --build (GITHUB_RUN_NUMBER)
         and --release-check true|false (RELEASE_CHECK; only from refs/heads/main). A tag that is not vX.Y.Z, is not on origin/main, or is
         not higher than the newest earlier v tag exits 1 with the reason.
notes    Writes notes.md (GitHub) and whats-new.txt (App Store) to --out (default .) for --version, from the
         commits that changed mobile/ after --previous-tag up to --to (GITHUB_SHA, else HEAD). --repo
         (GITHUB_REPOSITORY) names the repository for links.
mark     Labels each pull request in those notes "released" and comments once with the version. Same options.`;

const TAG = /^v(\d+)\.(\d+)\.(\d+)$/;
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
    },
  });
  const [command] = positionals;
  const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
  const git = makeGit(root);
  const notesArgs = () => ({
    git, repo: required(values, 'repo'), version: required(values, 'version'), previous: values['previous-tag'], to: values.to,
  });
  try {
    if (command === 'version') {
      console.log(versionLines({
        git, ref: values.ref, sha: values.sha, event: values.event, build: values.build,
        releaseCheck: values['release-check'] === 'true', pubspecText: readFileSync(join(root, 'mobile/pubspec.yaml'), 'utf8'),
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
