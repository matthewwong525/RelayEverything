import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, posix, relative, sep } from 'node:path';
import { test } from 'node:test';
import { COPY, copiedFiles, LEFT_OUT, pluginSkill, SKILL, SOURCE } from '../../scripts/copy-plugin-memory.mjs';

const AGAIN = 'Run node scripts/copy-plugin-memory.mjs to copy memory again.';
const filesIn = dir => readdirSync(dir, { withFileTypes: true, recursive: true }).filter(entry => entry.isFile())
  .map(entry => relative(dir, join(entry.parentPath ?? entry.path, entry.name)).split(sep).join('/')).sort();

test('the plugin\'s memory is the source folder less the short list, file for file', () => {
  const files = copiedFiles();
  assert.deepEqual(filesIn(COPY), files, AGAIN);
  for (const path of files) assert.ok(readFileSync(join(COPY, path)).equals(readFileSync(join(SOURCE, path))), `${path} differs. ${AGAIN}`);
  // Each entry of the short list is in the source, so the list never names a part memory no longer has.
  for (const out of LEFT_OUT) assert.ok(existsSync(join(SOURCE, out)), `${out} is not in memory any more`);
  for (const kept of ['SKILL.md', 'scripts/memory.mjs', 'scripts/session-start.mjs', 'store/interface.mjs', 'references/writing-facts.md']) {
    assert.ok(files.includes(kept), kept);
  }
});

test('no copied file imports a file that the copy left out', () => {
  const files = new Set(copiedFiles());
  const missing = [];
  for (const path of [...files].filter(file => file.endsWith('.mjs'))) {
    const text = readFileSync(join(COPY, path), 'utf8');
    const named = [...text.matchAll(/(?:\bfrom\s*|\bimport\s*\(\s*|^\s*import\s+)['"](\.{1,2}\/[^'"]+)['"]/gm)].map(found => found[1]);
    for (const target of named) {
      const file = posix.normalize(posix.join(posix.dirname(path), target));
      if (!files.has(file)) missing.push(`${path} imports ${file}`);
    }
  }
  assert.deepEqual(missing, []);
});

test('the memory skill is memory\'s own, with the plugin\'s command, its on and off, and no link out of the plugin', () => {
  const text = readFileSync(SKILL, 'utf8');
  assert.equal(text, pluginSkill(readFileSync(join(SOURCE, 'SKILL.md'), 'utf8')), AGAIN);
  assert.match(text, /^---\nname: memory\ndescription: .*Relay Everything/);
  for (const part of ['node "${CLAUDE_PLUGIN_ROOT}/bin/memory.mjs" <command>', 'node "${CLAUDE_PLUGIN_ROOT}/bin/connect.mjs" memory $ARGUMENTS',
    '/relay:memory on', 'In Codex it is empty: use the folder two levels above this file',
    '**In Codex, run each command here outside the sandbox.** Ask for escalated permissions', '## Write', '## Background run']) {
    assert.ok(text.includes(part), part);
  }
  for (const gone of ['.claude/skills/memory', '## Daily tidy', '## Team access', '](../../../']) assert.ok(!text.includes(gone), gone);
  // Each link the skill keeps lands on a file in the plugin.
  for (const [, target] of text.matchAll(/\]\(([^)#\s]+)(?:#[^)]*)?\)/g)) assert.ok(existsSync(join(dirname(SKILL), target)), target);
});
