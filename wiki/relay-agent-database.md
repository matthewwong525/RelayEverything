# The agents' database

Each person's agents' database is a second Durable Object, beside their [person space](relay-spaces.md), that holds only the tables the agents on their computers make.

The class is [`Workbench`](../app/worker/spaces-worker.ts), in the spaces Worker, bound as `WORKBENCHES` by the same `script_name` as `SPACES`, and named by the person's id. It has no migration, no `relay_` table, no file key. A Durable Object has one SQLite database, so a separate object is the only way free SQL can't reach the space: a command on `relay_notes` fails as *no such table*. Don't move a Relay Everything table into it, and don't give the space a raw-SQL route instead.

- **The door.** `spaceOf` opens it as `space.workbench`, on first use, for the same checked caller. Deleting the space deletes it first, so *Delete my account* takes both.
- **The routes.** `POST /v1/db` and `GET /v1/db/tables` on the connector's web API, through `computer()` in [`answers.ts`](../app/worker/relay-mcp/answers.ts): only an `agent` key gets in.
- **The limits.** `WORKBENCH_LIMITS` in `spaces-worker.ts`. A step past one throws inside its transaction, so nothing it wrote stays; a SQL error comes back as the answer, never as a crash.
- **Kept apart.** No webhook, export or connector tool reads it, and the server writes no health or location data into it.

A new class needs a new tag in `migrations` of [`wrangler.spaces.jsonc`](../app/wrangler.spaces.jsonc) and the self-host's `spaces.template.jsonc`, and a binding in each Worker that binds `SPACES`; [`bindings.test.mjs`](../app/self-host/bindings.test.mjs) checks both bindings. The website owns what a person reads: [Your agents' database](../site/src/content/docs/api/agents-database.md).

It is part of [the wiki](README.md), under [person spaces](relay-spaces.md).
