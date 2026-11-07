# Design

## Context

See [proposal.md](proposal.md) for why. On `main` (after PR #36 and #37), a webhook's data kinds are spread over files that must agree by hand: `webhooks/send.ts` (`Kind`, `Entry`, `bodyOf`), `webhooks/log.ts` (`TAKES` SQL), `webhooks/routes.ts` (`kind` enum, `kindsOf`), `Webhooks.tsx` (`KIND` labels and ticks), `webhooks/format.ts` (message union), `relay-mcp/inputs.ts` (`TOOLS`), `relay-mcp/api.ts` (`ROUTES`), the outbox `CHECK` in space migration `0006_phone_data.sql`, and the site pages. The calendar change touched each one. `npm run relay:api-doc` publishes `site/public/webhooks/v1.schema.json`, whose objects say `additionalProperties: false`, so a receiver that validates with a saved copy rejects any added field.

## Goals / Non-Goals

**Goals:** one registry that the sender, routes, card and checks read; receivers told, and shown, how to survive additions.

**Non-Goals:** webhook versions, step-down transforms, end dates and a changelog (parked; see the Decision log); versioning `/v1/` or MCP tools; filling the files, photos and chats gaps.

## Decisions

### One registry: `app/worker/apps/relay/kinds.ts`

```ts
type Part = "webhook" | "api" | "tool" | "docs";
type DataKind = {
  id: "notes" | "health" | "locations" | "calendar" | "files" | "photos" | "chats";
  label: string; detail: string;      // the tick's words
  always?: true; sensitive?: true;    // notes always go; health, places, calendar warn
  log: string[];                      // relay_outbox kinds it owns, e.g. ["health"]
  messages: string[];                 // message types, e.g. ["health.samples"]
  build?: (ctx, group) => Promise<Body | "skip" | "wait">;  // was bodyOf's branches
  api: string[]; tools: ToolName[];   // "/v1/health", "health"
  docs: string;                       // site slug, e.g. "app/health"
  missing?: Partial<Record<Part, string>>;  // known gaps, with the reason
};
```

- `TAKES` is generated from `log` (one `CASE` arm per log kind); `routes.ts`' `kind` enum, its `max`, and `kindsOf` come from the ids with a `webhook` part; `send.ts`' `bodyOf` dispatches to `build`.
- `GET webhooks` also answers `kinds: [{ id, label, detail, always, sensitive }]`, so `Webhooks.tsx` draws ticks and kind names from the server. Alternative, importing the registry into `app/src`: rejected, as `app/src` imports nothing from `app/worker` and the worker file pulls in SQL.
- `kinds.test.ts` checks, for each kind and each part not in `missing`: every message type is in `format.ts`' union and has a `###` heading in `your-database.md` and a branch in `receiver.mjs`; every API path is in `ROUTES`; every tool is in `TOOLS`; the docs page exists under `site/src/content/docs/`. It fails when a `missing` part is present, when a message type or log kind has no owner (only `webhook.test` is shared), and when the outbox `CHECK` list in the newest space migration differs from the union of `log`. Files, photos and chats start with `missing.webhook` set, plus the parts they lack on `main` at build time.
- Alternative, a checklist in the wiki: rejected, because nothing fails when a step is skipped. The wiki page points to the registry and its test.

### Receivers ignore what they don't know

- `jsonSchema()` post-processes `z.toJSONSchema` to drop `additionalProperties: false`, and publishes a list marked `.meta({ grows: true })` (health type, calendar status) as a string with `examples`. The server's own parse stays strict, so its tests still catch a typo.
- `receiver.mjs` adds `CREATE TABLE IF NOT EXISTS other_messages (webhook_id TEXT PRIMARY KEY, type TEXT, body TEXT, received_at TEXT)`; `save()` stores there any type it does not handle, keyed by `webhook-id` so a retry upserts. It stays under about 75 lines.
- `your-database.md` gains *When the format changes*: answer 2xx to an unknown type, keep unknown fields, accept new list values; until the public release version 1 can change in any way; after it, a breaking change gets a new version.

## Risks / Trade-offs

- [The phone-to-webhook plan builds version 1 messages on the phone] → its `note.file` type joins the registry when it lands; `kinds.test.ts` fails until it has a heading and a receiver branch.
- [Alpha changes that break WongOS] → accepted until the public release; the person is the only receiver and fixes WongOS in the same change.

## Migration Plan

No data changes: no space migration, and every webhook keeps its ticks. Rollback is publishing the earlier Worker.
