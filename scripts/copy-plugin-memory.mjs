#!/usr/bin/env node
// `node scripts/copy-plugin-memory.mjs`: copies `.agents/skills/memory/` to `plugin/memory/`, and its skill to
// `plugin/skills/memory/SKILL.md`. The plugin release runs it; memory-copy.test.mjs fails while the copy differs.
import { cpSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
export const SOURCE = join(ROOT, '.agents', 'skills', 'memory');
export const COPY = join(ROOT, 'plugin', 'memory');
export const SKILL = join(ROOT, 'plugin', 'skills', 'memory', 'SKILL.md');

// Left out: the plugin's hook runs the scripts, the daily build is the one daily job, /relay:connect sets memory up,
// and the plugin has no packages. A folder ends with `/`.
export const LEFT_OUT = ['hooks/', 'README.md', 'references/setup.md', 'store/contract.mjs'];

const left = path => LEFT_OUT.some(out => (out.endsWith('/') ? path.startsWith(out) : path === out));

/** Each file the copy holds, as a path in the folder with `/`, sorted. */
export function copiedFiles(source = SOURCE) {
  return readdirSync(source, { withFileTypes: true, recursive: true }).filter(entry => entry.isFile())
    .map(entry => relative(source, join(entry.parentPath ?? entry.path, entry.name)).split(sep).join('/'))
    .filter(path => !left(path)).sort();
}

const FRONTMATTER = `---
name: memory
description: Relay Everything's memory for Claude Code and Codex. Search and record what the person decided, prefers and left open in this computer's chats, or turn memory on or off. Use for /relay:memory, /relay:memory on, /relay:memory off, "what did we decide about", or "remember this".
argument-hint: "[on|off]"
allowed-tools: Bash(node:*)
---
`;

const HEAD = `# /relay:memory

Relay Everything's memory keeps short facts from this computer's chats in the person's own Relay Everything space.

\`\${CLAUDE_PLUGIN_ROOT}\` is the plugin's folder. In Codex it is empty: use the folder two levels above this file, and put the person's words in place of \`$ARGUMENTS\`.

**In Codex, run each command here outside the sandbox.** Ask for escalated permissions, and the person approves it. In Codex's sandbox, the command can not reach the network or write this computer's Relay Everything folder.

## On or off

With \`on\`, \`off\` or nothing, run this and show the lines it prints, word for word:

\`\`\`bash
node "\${CLAUDE_PLUGIN_ROOT}/bin/connect.mjs" memory $ARGUMENTS
\`\`\`

When memory is off, a command below says that memory is not set up. Tell the person to type \`/relay:memory on\`, then go on without memory. A project with its own memory, such as a WongStack project, uses its own memory: Relay Everything's memory stays off there.

## Use it
`;

const OUT = String.raw`(?:\.\.\/|README\.md\b|https:\/\/github\.com\/matthewwong525\/WongStack\/)`;

// The sections that are WongStack's own: the plugin starts no daily tidy, and the store has no company sign-in.
const DROPPED = ['Daily tidy', 'Team access'];

/** Memory's `SKILL.md` as the plugin's skill: its own head, the plugin's script, and no link out of the plugin. */
export function pluginSkill(text) {
  const body = String(text).replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, '').replace(/^\s*# .*\r?\n/, '');
  const kept = body.split(/(?=^## )/m).filter(part => !DROPPED.some(name => part.startsWith(`## ${name}\n`))).join('');
  const plugged = kept
    .replaceAll('node .claude/skills/memory/scripts/memory.mjs', 'node "${CLAUDE_PLUGIN_ROOT}/bin/memory.mjs"')
    // A line that is only a link out of the plugin goes; another link out keeps its words. A link out is one above
    // memory's folder, to its README, which the copy leaves out, or to WongStack's own pages on the web.
    .replace(new RegExp(`^\\[[^\\]]*\\]\\(${OUT}[^)]*\\)\\.?\\r?\\n\\r?\\n?`, 'gm'), '')
    .replace(new RegExp(`\\[([^\\]]*)\\]\\(${OUT}[^)]*\\)`, 'g'), '$1')
    .replace(/\]\(references\//g, '](../../memory/references/');
  return `${FRONTMATTER}\n${HEAD}${plugged.replace(/^\s+/, '\n')}`;
}

/** Makes the copy again from nothing, so a file memory removed goes too, and writes the skill. */
export function copyMemory({ source = SOURCE, copy = COPY, skill = SKILL } = {}) {
  rmSync(copy, { recursive: true, force: true });
  const files = copiedFiles(source);
  for (const path of files) {
    mkdirSync(dirname(join(copy, path)), { recursive: true });
    cpSync(join(source, path), join(copy, path));
  }
  mkdirSync(dirname(skill), { recursive: true });
  writeFileSync(skill, pluginSkill(readFileSync(join(source, 'SKILL.md'), 'utf8')));
  return files;
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(self)) {
  const files = copyMemory();
  console.log(`Copied ${files.length} files of memory to ${relative(ROOT, COPY)}, and wrote ${relative(ROOT, SKILL)}.`);
}
