import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { envValues, hide, hider, HIDDEN, SHAPES } from '../lib/hide.mjs';

// The memory store's copy of the shapes: the plugin can't import it, because Claude Code installs only plugin/.
const SCAN = new URL('../../.agents/skills/memory/scripts/lib/scan.mjs', import.meta.url);
const { redact } = await import(SCAN.href);

// Made-up samples, joined at run time so no file here holds a key shape.
const samples = {
  'GitHub token': `gh${'p_'}${'A1'.repeat(18)}`,
  'GitHub fine-grained token': `github${'_pat_'}${'B2'.repeat(20)}`,
  'API key (sk-)': `s${'k-'}${'c3'.repeat(15)}`,
  'AWS access key': `AK${'IA'}${'D4'.repeat(8)}`,
  'JWT': `ey${'J'}hbGciOiJIUzI1.eyJzdWIiOiIx.c2lnbmF0dXJlcw`,
  'Memory login marker': `wong${'l_'}${'e'.repeat(43)}`,
  'Memory key': `wong${'m_'}abc.${'f'.repeat(24)}`,
  'Bearer header': `Bear${'er'} ${'g'.repeat(32)}`,
  'Private key block': `-----BEGIN ${'RSA PRIVATE'} KEY-----\nMIIEow\n-----END RSA ${'PRIVATE'} KEY-----`,
  'Slack token': `xo${'xb'}-123456-${'h'.repeat(12)}`,
};

test('every key shape of the memory store is one of the plugin\'s, by name', () => {
  const names = [...readFileSync(SCAN, 'utf8').matchAll(/^\s*\['([^']+)', \//gm)].map(match => match[1]);
  assert.ok(names.length >= 8);
  const ours = SHAPES.map(([name]) => name);
  assert.deepEqual(names.filter(name => !ours.includes(name)), []);
  assert.deepEqual(Object.keys(samples).sort(), [...ours].sort());
});

test('hides each sample, and the memory store\'s redact hides its own shapes alike', () => {
  const theirs = readFileSync(SCAN, 'utf8');
  for (const [name, sample] of Object.entries(samples)) {
    const text = `before ${sample} after`;
    const hidden = hide(text);
    assert.doesNotMatch(hidden, new RegExp(sample.slice(-10).replace(/[.*+?^${}()|[\]\\-]/g, '\\$&')), name);
    assert.match(hidden, /^before .*\[hidden\].* after$/, name);
    if (theirs.includes(`['${name}'`)) assert.notEqual(redact(text, []), text, `${name}: scan.mjs no longer hides it`);
  }
  assert.equal(hide(samples['Bearer header']), `Bearer ${HIDDEN}`);
  assert.equal(hide('An ordinary sentence with sk-short and Bearer you.'), 'An ordinary sentence with sk-short and Bearer you.');
});

test('hides each .env and .dev.vars value of 8 characters or more, from the nearest folder up', () => {
  const top = mkdtempSync(join(tmpdir(), 'relay-hide-'));
  mkdirSync(join(top, 'app'));
  writeFileSync(join(top, '.env'), 'export SHORT=abc\nDB_PASSWORD="opensesame-42"\n# A comment\nEMPTY=\nTOKEN=\'tok-long-value\'\n');
  writeFileSync(join(top, 'app', '.dev.vars'), 'API_SECRET = devvalue123\n');
  assert.deepEqual(envValues(join(top, 'app')), ['tok-long-value', 'opensesame-42', 'devvalue123']);
  const hideHere = hider(join(top, 'app'));
  assert.equal(hideHere('The password is opensesame-42, devvalue123 and abc.'), `The password is ${HIDDEN}, ${HIDDEN} and abc.`);
  assert.deepEqual(envValues(mkdtempSync(join(tmpdir(), 'relay-none-'))), []);
});

test('an unreadable .env still hides every key shape', () => {
  const top = mkdtempSync(join(tmpdir(), 'relay-hide-'));
  mkdirSync(join(top, '.env'));
  assert.equal(hider(top)(samples['GitHub token']), HIDDEN);
});
