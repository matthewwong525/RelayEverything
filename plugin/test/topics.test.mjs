import assert from 'node:assert/strict';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { frontmatter, linksIn, matchTopics, MOST_MATCHES, projectTopic, readTopic, topicName, topicPages, topLevel } from '../lib/topics.mjs';
import { copy, page } from './fake.mjs';

const WEB = {
  'README.md': '# Your knowledge web\n',
  'FORMAT.md': '# The rules\n',
  'topics/battery.md': page('Battery', 'Stays 40 mAh; charger cable open', 'It charges on the [dock](ring/charging.md).'),
  'topics/ring/README.md': page('Ring', 'Bike ring v2: band, board, sync', 'Parts: [charging](charging.md), [band](band.md), [the web](https://example.com).'),
  'topics/ring/charging.md': page('Charging', 'The dock and its cable', 'See [battery](../battery.md#size) and [ring](./README.md).'),
  'topics/ring/band.md': page('Band', undefined, 'No summary yet.'),
  'topics/sam.md': page('Sam', '"Friend from the bike club"'),
  'topics/Not A Tag.md': page('Bad', 'Not a topic name'),
  'topics/notes.txt': 'Not a page.\n',
  'topics/battery.md.other': 'The web\'s side of a joined page.\n',
};

test('reads the topics, their summaries and their links from the copy', () => {
  const dir = copy(WEB);
  assert.deepEqual([...topicPages(dir).keys()].sort(), ['battery', 'ring', 'ring/band', 'ring/charging', 'sam']);
  assert.deepEqual(topLevel(dir), [
    { name: 'battery', summary: 'Stays 40 mAh; charger cable open', updated: '2026-11-10' },
    { name: 'ring', summary: 'Bike ring v2: band, board, sync', updated: '2026-11-10' },
    { name: 'sam', summary: 'Friend from the bike club', updated: '2026-11-10' }]);
  const ring = readTopic(dir, 'ring');
  assert.equal(ring.path, 'topics/ring/README.md');
  assert.deepEqual(ring.links, ['ring/band', 'ring/charging']);
  assert.deepEqual(readTopic(dir, 'ring/charging').links, ['battery', 'ring']);
  assert.equal(readTopic(dir, 'ring/band').summary, null);
  assert.equal(readTopic(dir, 'nothing'), null);
  assert.deepEqual(linksIn(dir, 'battery'), ['ring/charging']);
  assert.deepEqual(linksIn(dir, 'ring/charging'), ['battery', 'ring']);
  assert.deepEqual(frontmatter('No frontmatter.'), { fields: {}, body: 'No frontmatter.' });
});

test('a copy with no topics, or no copy, has none', () => {
  assert.deepEqual(topLevel(copy({ 'README.md': '# Your knowledge web\n' })), []);
  assert.deepEqual(topLevel(join(tmpdir(), 'relay-no-copy-here')), []);
  assert.equal(projectTopic(join(tmpdir(), 'relay-no-copy-here'), 'WongOS'), null);
});

test('a project\'s topic is the topic with its name, whole or as a last part', () => {
  assert.equal(topicName('WongOS'), 'wongos');
  assert.equal(topicName('relay_ring'), 'relay-ring');
  assert.equal(projectTopic(copy({ 'topics/wongos.md': page('WongOS', 'The OS') }), 'WongOS').summary, 'The OS');
  assert.equal(projectTopic(copy({ 'topics/work/wongos.md': page('WongOS', 'At work') }), 'WongOS').name, 'work/wongos');
  assert.equal(projectTopic(copy(WEB), 'WongOS'), null);
});

test('a message matches a whole name or a last part clearly, the start of a name weakly, at most 3', () => {
  const names = ['battery', 'ring', 'ring/band', 'ring/charging', 'sam', 'bike-club'];
  assert.deepEqual(matchTopics(names, 'Is the battery still 40 mAh?'), [{ name: 'battery', clear: true }]);
  assert.deepEqual(matchTopics(names, 'Is it still charging?'), [{ name: 'ring/charging', clear: true }]);
  assert.deepEqual(matchTopics(names, 'Did the bike club meet?'), [{ name: 'bike-club', clear: true }]);
  assert.deepEqual(matchTopics(names, 'How is the batt?'), [{ name: 'battery', clear: false }]);
  // A clear match's own parts are left out: its page leads to them.
  assert.deepEqual(matchTopics(names, 'What about the ring?'), [{ name: 'ring', clear: true }]);
  assert.deepEqual(matchTopics(names, 'ring charging and the battery'),
    [{ name: 'ring/charging', clear: true }, { name: 'battery', clear: true }, { name: 'ring', clear: true }]);
  assert.equal(matchTopics(names, 'sam, the band, the battery, the ring and charging').length, MOST_MATCHES);
  assert.deepEqual(matchTopics(names, 'What is for lunch?'), []);
  assert.deepEqual(matchTopics(names, 'samples'), []);
  assert.deepEqual(matchTopics(names, ''), []);
});
