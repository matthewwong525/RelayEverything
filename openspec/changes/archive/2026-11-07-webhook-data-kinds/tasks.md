## 1. Start from main

- [x] 1.1 Bring this branch up to `main`, which holds the calendar kind (#36) and the Pebble removal (#37). Verify: `app/worker/apps/relay/webhooks/log.ts` names `calendar`, and `npm test` in `app/` passes before any edit.

## 2. The list of data kinds (server)

- [x] 2.1 Add `app/worker/apps/relay/kinds.ts` with one entry per kind (notes, health, locations, calendar, files, photos, chats), each naming its tick words, log kinds, message types, body builder, `/v1/` paths, MCP tools, docs slug and `missing` parts. Verify: `tsc -b` in `app/` passes.
- [x] 2.2 Make `webhooks/log.ts` (`TAKES`), `webhooks/routes.ts` (`kind` enum, `kindsOf`) and `webhooks/send.ts` (`Kind`, `Entry`, `bodyOf`) read the registry, and make `GET webhooks` answer the tickable kinds. Verify: the existing `send.test.ts` and `routes.test.ts` pass unchanged, plus a new `routes.test.ts` case for the `kinds` list.
- [x] 2.3 Write `kinds.test.ts`: each non-missing part exists (union type, `your-database.md` heading, `receiver.mjs` branch, `ROUTES` path, `TOOLS` tool, docs page); a listed-missing part that exists fails; every message type and outbox kind has exactly one owner; the outbox `CHECK` list equals the registry's log kinds. Verify: it passes, and fails when a kind's `docs` points at a missing page (checked once by hand, then reverted).
- [x] 2.4 Add a `send.test.ts` case: a webhook made for notes only gets no calendar or health message after that data is stored. Verify: `npx vitest run worker/apps/relay/webhooks` passes.

## 3. The published schema (server)

- [x] 3.1 Make `jsonSchema()` drop `additionalProperties: false` and publish growing lists (health type, calendar status) as text with known values, while the server's own parse stays strict; run `npm run relay:api-doc`. Verify: a `format.test.ts` case validates a message with an extra field against the published schema, and the existing "schema differs from code" check passes.

## 4. Webhook card (web page)

- [x] 4.1 Draw the add form's ticks and the card's kind names from `GET webhooks`' `kinds`, keeping the sensitive-data line. Verify: a `Webhooks.test.tsx` case with a kind list from the server, and the existing cases pass.

## 5. Example receiver and docs (website and wiki)

- [x] 5.1 Make `site/public/webhooks/receiver.mjs` keep unknown message types in `other_messages`. Verify: a `receiver.test.ts` case for an unknown type answers 2xx and stores one raw row, and a retry of it stores no second row.
- [x] 5.2 Add *When the format changes* to `site/src/content/docs/connections/your-database.md`: answer 2xx to unknown types, keep unknown fields, accept new values; version 1 can still change until the public release. Verify: `node --test scripts/product-name.test.mjs` and the site test pass.
- [x] 5.3 Write `wiki/relay-webhook-changes.md` (add a kind through the registry and let `kinds.test.ts` list what is missing; additions only after the public release; the parked versions plan) and link it from `wiki/README.md` and `wiki/relay-spaces.md#webhooks`. Verify: the wiki link and size checks pass.

## 6. Checks

- [x] 6.1 Run `npm test` in `app/`, the site's tests, and `node scripts/public-check.mjs`. Verify: all pass.
- [x] 6.2 Run `/save`, and on the preview add a webhook and see the Health, Location history and Calendar ticks. Verify: CI passes and the form shows the three ticks.
