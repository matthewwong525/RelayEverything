// Relay Everything's profile for memory's copy in `memory/`: the store is the person's own space, the topics are this
// computer's copy of their knowledge web, and a pulled topic adds its notes and chats. No other part: no WongStack verbs.
import { join, relative, sep } from 'node:path';
import { copyOf, readComputer } from './lib/config.mjs';
import { notesAndChats, whyOff } from './lib/memory.mjs';
import { readTopic, topicPages, topLevel } from './lib/topics.mjs';
import { StoreError } from './memory/store/interface.mjs';

/** The store: `/memory` under the computer's web API, with its key. Memory off here leaves the copy quiet. */
export function connect(ctx, { env = process.env } = {}) {
  const computer = readComputer(env);
  const why = whyOff(env, ctx.root, computer);
  if (why) throw new StoreError(`Relay Everything's memory is not on here: ${why}`, { kind: 'unconfigured' });
  return { url: `${computer.api}/memory`, headers: () => ({ Authorization: `Bearer ${computer.key}` }) };
}

/**
 * One topic per page of the knowledge copy. Memory reads a page at `join(ctx.root, page)`, so `page` is the copy's
 * file from the repo's root. `hub` orders the chat start's lines: the top-level topics, the newest first.
 */
export function topics(ctx, { env = process.env } = {}) {
  const dir = copyOf(env);
  const pages = topicPages(dir);
  const hub = topLevel(dir).sort((a, b) => String(b.updated ?? '').localeCompare(String(a.updated ?? ''))).map(topic => topic.name);
  return [...pages].map(([tag, file]) => {
    const page = relative(ctx.root, join(dir, file)).split(sep).join('/');
    return { tag, kind: 'company', page, summary: readTopic(dir, tag, pages)?.summary ?? '', aliases: [], paths: [page], docs: [page],
      hub: hub.includes(tag) ? hub.indexOf(tag) : null };
  });
}

/** After a lookup: the notes on its topics and the chats their facts came from. */
export const lookup = {
  after: (ctx, { tags = [] } = {}, options = {}) => notesAndChats(tags, options),
};

export default { connect, topics, lookup };
