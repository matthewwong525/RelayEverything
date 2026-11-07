import assert from 'node:assert/strict';
import { test } from 'node:test';
import { codeFrom, parseCode, post } from '../lib/code.mjs';

const key = name => `rek_${name.padEnd(43, 'x')}`;
const code = (server, more = {}) => JSON.stringify({ relay: 1, server, key: key('one'), ...more });

test('takes the server only from the connect code: https, with no path', () => {
  assert.deepEqual(parseCode(` ${code('https://relay.example.com')}\n`),
    { server: 'https://relay.example.com', key: key('one') });
  for (const wrong of [code('http://relay.example.com'), code('https://relay.example.com/apps'), code('https://relay.example.com/'),
    code(`https://user${'@'}relay.example.com`), code('https://relay.example.com', { relay: 2 }), code('https://relay.example.com', { key: '' }),
    code('https://relay.example.com', { key: 'rek_short' }), code('https://relay.example.com', { key: `${key('one')} ` }),
    JSON.stringify({ relay: 1, server: 'https://relay.example.com', clientId: 'old.access', clientSecret: 'old' }), '{', '', undefined, 'null']) {
    assert.equal(parseCode(wrong), null, String(wrong));
  }
});

test('a hook reads its option, and the save tool its own setting', () => {
  assert.equal(codeFrom({ CLAUDE_PLUGIN_OPTION_CONNECT_CODE: code('https://a.example.com') }).server, 'https://a.example.com');
  assert.equal(codeFrom({ CLAUDE_PLUGIN_OPTION_CONNECT_CODE: '', RELAY_CONNECT_CODE: code('https://b.example.com') }).server, 'https://b.example.com');
  assert.equal(codeFrom({}), null);
});

test('two codes for two servers each send to their own server, with their own key', async () => {
  const calls = [];
  const fetcher = async (url, init) => {
    calls.push([url, init.headers.Authorization, JSON.parse(init.body)]);
    return new Response(JSON.stringify({ stored: 1 }), { status: 200 });
  };
  await post(parseCode(code('https://one.example.com')), 'chats', { a: 1 }, fetcher);
  await post(parseCode(code('https://two.example.com', { key: key('two') })), 'chat-saves', { b: 2 }, fetcher);
  assert.deepEqual(calls, [
    ['https://one.example.com/apps/relay/api/chats', `Bearer ${key('one')}`, { a: 1 }],
    ['https://two.example.com/apps/relay/api/chat-saves', `Bearer ${key('two')}`, { b: 2 }],
  ]);
  const notJson = await post(parseCode(code('https://one.example.com')), 'chats', {}, async () => new Response('<html>', { status: 502 }));
  assert.deepEqual(notJson, { status: 502, json: null });
});
