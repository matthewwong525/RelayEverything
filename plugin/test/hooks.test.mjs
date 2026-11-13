import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = name => JSON.parse(readFileSync(new URL(`../hooks/${name}`, import.meta.url), 'utf8')).hooks;
/** Each event's script argument and time limit, as `hook.mjs <event>` and seconds. */
const shape = hooks => Object.fromEntries(Object.entries(hooks).map(([event, groups]) => {
  const [hook, ...more] = groups.flatMap(group => group.hooks);
  assert.equal(more.length, 0, event);
  assert.equal(hook.async, undefined, `${event}: Codex does not run an async hook`);
  return [event, { script: /\/bin\/hook\.mjs" ([a-z-]+)$/.exec(hook.command)?.[1], timeout: hook.timeout }];
}));

test('the copy\'s hooks for Claude Code and Codex name the same events, scripts and time limits as the plugin\'s', () => {
  const plugin = shape(read('hooks.json'));
  for (const [name, folder] of [['claude.json', '$CLAUDE_PROJECT_DIR'], ['codex.json', '$(git rev-parse --show-toplevel)']]) {
    const hooks = read(name);
    assert.deepEqual(shape(hooks), plugin, name);
    for (const group of Object.values(hooks).flat()) {
      assert.ok(group.hooks[0].command.startsWith(`node "${folder}/.agents/relay/bin/hook.mjs" `), `${name}: ${group.hooks[0].command}`);
    }
  }
  // An edit in each app: Claude Code's edit tools, and Codex's apply_patch.
  assert.deepEqual(read('claude.json').PreToolUse[0].matcher.split('|'), ['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);
  assert.equal(read('codex.json').PreToolUse[0].matcher, 'apply_patch');
});
