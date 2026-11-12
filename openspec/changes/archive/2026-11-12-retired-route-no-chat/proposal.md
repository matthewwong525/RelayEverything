# Proposal

**Status:** shipping
**Branch:** demonic-lynx
**Open questions:** none

## Why

Today the server stopped taking the chat list before this computer had the new code. The daily's helper took the server's *retired* answer as a fault, failed two times in a row, and opened a *Needs you* chat that told you to sign in. The sign-in was fine, and the problem went away by itself a few minutes later when the new code came down.

## What Changes

- **A retired answer opens no chat.** When the server says a part is retired, the helper writes one line in the daily's journal and goes on. It does not count this as a fault, so no *Needs you* chat opens. The line says the computer runs older code and updates itself.
  ```mermaid
  flowchart TD
    A["Server answers"] --> B{"retired?"}
    B -- yes --> C["One journal line, go on"]
    B -- no --> D["Count the fault"]
    D --> E{"2 in a row?"}
    E -- yes --> F["Needs you chat"]
  ```

- **The same fix goes to WongStack.** The daily helper comes from WongStack, so this fix also goes there as a pull request. Then every WongStack computer gets it, and the next update here does not undo it.

## Capabilities

### New Capabilities

### Modified Capabilities

None in this repo: the daily's spec (`daily-routine`) lives in WongStack. The WongStack pull request carries its delta to *Two failures in a row open one Needs-you chat*.

## Impact

- `.agents/skills/daily/scripts/worker.mjs` (`failed`), here and in WongStack.
- WongStack: `scripts/tests/daily-worker.test.mjs`, `openspec/specs/daily-routine/spec.md` delta, and a `CHANGELOG.md` entry (payload release).
