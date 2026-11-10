# Relay Everything's memory and knowledge web

Each Relay Everything person has a memory of facts, a table in their own [space](../relay-spaces.md), and a knowledge web of topic pages, a git repository in Cloudflare Artifacts that only their computers reach. This page tells how the server keeps both, part of [the Cloudflare stack](README.md). The website's [Memory and knowledge web](../../site/src/content/docs/api/knowledge-web.md) page tells a person and a plugin builder how to use them.

## The memory

- The tables come from [`0016_memory.sql`](../../schema/space-migrations/0016_memory.sql). Only [`memory.ts`](../../app/worker/apps/relay/memory.ts) writes them. The connector's files only read: [`tools.test.ts`](../../app/worker/relay-mcp/tools.test.ts) fails on a write word there.
- A person's columns are values in `relay_memory_columns`, not SQL columns. A fact's values are JSON in `fields`. So a column change needs no migration, and no caller's text becomes SQL: a name is checked by pattern, and a filter binds its value.
- A fact is only added. A replace sets the old fact's `replaced_by` in the same batch, and that is the only update. Only deleting the account deletes a fact.
- Only a computer's key (`agent` reach) adds facts, changes columns and changes topics. An API key and the [AI connector](relay-ai-connector.md) read. A phone's key is refused before the web API runs.

## The knowledge web

- **Namespaces.** The live server and connector bind `KNOWLEDGE` to `relay-everything-knowledge`, staging to `relay-everything-knowledge-staging`, in [`wrangler.relay.jsonc`](../../app/wrangler.relay.jsonc) and [`wrangler.relay-mcp.jsonc`](../../app/wrangler.relay-mcp.jsonc). The Worker holds no Cloudflare token.
- **The start repo.** Each namespace has a repo named `start`, holding [`schema/knowledge/`](../../schema/knowledge/README.md)'s `README.md` and `FORMAT.md`. A person's web is a fork of `start`, named `p-<personId>`, made on their computer's first ask ([`knowledge.ts`](../../app/worker/apps/relay/knowledge.ts)). A fork can't be filled from the Worker, as it can't push git objects. A later change to `start` reaches only new webs.
- **The setup script.** [`scripts/relay-knowledge-setup.mjs`](../../scripts/relay-knowledge-setup.mjs) `[--staging]` makes the namespace and `start` when missing, and pushes the two pages with a ten-minute pass. It reads `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the primary worktree's `.env`. [`publish-relay-server.mjs`](../../scripts/publish-relay-server.mjs) runs it before each environment's deploys ([the Workers and their order](../relay-spaces.md#the-workers-and-their-order)), so it is never missed.
- **The pass.** `POST /v1/knowledge/access` answers the web's git address and a write pass for one hour. *Turn off* stops the key at once, but can't call back a pass already given: it ends within the hour. A server with no `KNOWLEDGE` binding, or no `start` repo, answers `501 not_set_up`; a fork still running answers `503 try_again`.
- **The copy.** The plugin's [`knowledge.mjs`](../../plugin/bin/knowledge.mjs) keeps the copy in `knowledge/` in the plugin's folder. It gives the pass to git only as `GIT_CONFIG_*` environment values, never in an argument, a file or the remote. It syncs at most once every 15 minutes, unless the copy has changes or the person adds `--now`, because each sync costs Artifacts operations. A page both computers changed keeps both: text by joining the lines (`merge=union`), any other file with the web's copy beside it as `<name>.other`.
- **Delete.** Deleting the account deletes the person's repo after their space ([`account.ts`](../../app/worker/apps/relay/account.ts)). A person with no web passes.

## Cost

Artifacts needs Workers Paid. There is no charge for each repo. 10,000 operations a month are free, then $0.15 for each 1,000. A sync is about 2 to 3 operations.
