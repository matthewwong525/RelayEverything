# Design: notes first when the app opens

## Context

See proposal.md, Why. Today `RelayController.pullNotes` (`mobile/lib/controller.dart`) awaits `sync()`, a single-flight `_rounds()` loop of `_sync()`. One `_sync()` reads health, the calendar, drains iPhone history, steps and names stays, queues points, runs `flush(store, api)` for the notes destination (every route of that destination, oldest id first, so a note waits behind `health`/`locations`/`stays`/`calendar` rows when private data also goes to the server), flushes the private client if apart, sends photos, and sets `_status` from the notes flush plus the photo failure when not apart. Only then `_pull()` runs `syncNotes`, and only when `_status == synced`. `_rounds()` then may run `refreshConnections()`.

`backgroundRound` (`mobile/lib/sync/background.dart`) has the same order: health and places first, one notes flush, then the pull.

`privateRoutes` (`store.dart`) is `{'health', 'locations', 'stays', 'calendar'}`. Photos use their own table and `sendPhotos`, not the outbox. Note routes are everything else: `notes`, `note.update`, `note.delete`, `attachment`.

## Goals / Non-Goals

Goals: the notes part of a round finishes before any health, place, calendar or photo read or send; `pullNotes` resolves when the notes part ends; the private part never changes the Home status and never stops the pull; a note or pull waiting stops the private part at its next upload.

Non-goals: more iPhone background time; batching several outbox rows in one request; any server change; changing what or where private data sends.

## Decisions

1. **A route filter on the outbox.** `Store.outbox({destination, private})` and `flush(..., private: bool?)` read only note routes (`private: false`), only `privateRoutes` (`private: true`), or all (`null`, today's behavior for any other caller). The notes flush of the server client passes `false`; the private part flushes the same client with `true` when private data is not apart, and the private client (webhook) as today. Two flushes of one destination touch disjoint rows, so no row sends twice. *Alternative:* a priority column or `ORDER BY` that puts notes first in one flush: a failed note still stops the private rows behind it, and the pull still waits for the whole flush.

2. **The round has two parts, one single-flight.** `_sync()` becomes `_notesPart()` then `_privatePart()` inside the same `_rounds()` loop, keeping one `_syncing` future, so two rounds never run at once and `sync()` keeps meaning "everything" for its callers (iPhone wake `onWake(relay.sync)`, the note editor, tests).
   - `_notesPart()`: sets `syncing`, flushes note routes, sets `_status` from that result only (`refused`, `synced`, `offline`; `idle` with sending off), refreshes the list, and, when a pull is wanted and the flush emptied, runs `syncNotes` with the same error mapping `_pull()` has today. It then completes the waiting pull.
   - `_privatePart()`: health, calendar, `_drain`, stays, `queuePoints`, the private-routes flush, the private client's flush when apart, photos, then `_refreshLocal`. It never sets `_status` except to `idle` when sending turned off.
   - `_rounds()` returns "emptied" from the notes part, and `refreshConnections()` keeps its place after the loop.

3. **`pullNotes` waits for the notes part only.** `pullNotes()` sets `_pullWanted = true` and a `Completer` (one shared by callers that come before it completes), calls `sync()` without awaiting it fully, and returns the completer's future. The notes part completes it after the pull, or right away when the pull cannot run (flush failed, sending off, no reader). If a round is in its private part, the stop in decision 4 makes the next loop iteration run the notes part soon. The `_pulling` field goes away. `resume()` and `main()` keep calling `pullNotes()`; the Home and timeline refresh and **Sync now** end with the notes.

4. **Notes preempt the private part.** The private part's `keepGoing` (`still()` today, and the photo `keepGoing`) also returns false while `_again` is set (a `sync()` call came during the round, such as `keepNote`) or `_pullWanted` is set. The loop in `_rounds()` then runs again while `_again || _pullWanted`, starting with notes. Health and calendar reads that already started finish their one bounded read; the rows they queued wait. *Alternative:* run a notes flush in parallel with the private part: two flushes against the same `Store` while a switch of place may move rows makes the single-flight reasoning harder, for a gain of at most one upload.

5. **Background round, same order.** `backgroundRound` drains the share inbox, flushes note routes of `api`, pulls when `pull` and that flush emptied, then drains points, reads health, calendar, stays, queues points, flushes private routes (same client when not apart, else the private client) and sends photos. Its return value keeps meaning "everything sent".

## Risks / Trade-offs

- [A private send to the server that is refused while notes succeed no longer shows on Home] → a turned-off key also refuses the notes flush, so Home still shows it; a webhook problem shows on the Account page as today.
- [The private part may stop often while the person writes many notes] → each stop keeps the queued rows; the round after the notes goes on with them, and the hourly task and wakes also send them.
- [A pull completer left pending if a round throws] → complete it in a `finally` of the round; tests cover a throwing store.

## Migration Plan

No data change: the outbox keeps its rows and columns. A phone updates and the next open uses the new order. Rollback is the previous app build.
