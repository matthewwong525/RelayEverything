import assert from 'node:assert/strict';
import { test } from 'node:test';
import { codeFrom, parseCode, post } from '../lib/code.mjs';

const code = (server, more = {}) => JSON.stringify({ relay: 1, server, clientId: 'id-1.access', clientSecret: 'secret-1', ...more });

test('takes the server only from the connect code: https, with no path', () => {
  assert.deepEqual(parseCode(` ${code('https://relay.example.com')}\n`),
    { server: 'https://relay.example.com', clientId: 'id-1.access', clientSecret: 'secret-1' });
  for (const wrong of [code('http://relay.example.com'), code('https://relay.example.com/apps'), code('https://relay.example.com/'),
    code(`https://user${'@'}relay.example.com`), code('https://relay.example.com', { relay: 2 }), code('https://relay.example.com', { clientSecret: '' }),
    code('https://relay.example.com', { clientId: 'with space' }), '{', '', undefined, 'null']) {
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
    calls.push([url, init.headers['CF-Access-Client-Id'], init.headers['CF-Access-Client-Secret'], JSON.parse(init.body)]);
    return new Response(JSON.stringify({ stored: 1 }), { status: 200 });
  };
  await post(parseCode(code('https://one.example.com')), 'chats', { a: 1 }, fetcher);
  await post(parseCode(code('https://two.example.com', { clientId: 'id-2.access', clientSecret: 'secret-2' })), 'chat-saves', { b: 2 }, fetcher);
  assert.deepEqual(calls, [
    ['https://one.example.com/apps/relay/api/chats', 'id-1.access', 'secret-1', { a: 1 }],
    ['https://two.example.com/apps/relay/api/chat-saves', 'id-2.access', 'secret-2', { b: 2 }],
  ]);
  const notJson = await post(parseCode(code('https://one.example.com')), 'chats', {}, async () => new Response('<html>', { status: 502 }));
  assert.deepEqual(notJson, { status: 502, json: null });
});
