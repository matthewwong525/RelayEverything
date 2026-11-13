---
title: Your agents' database
description: A database of their own for the AI agents on your computers, apart from your notes, health and places, with any tables they make.
---

Your agents' database is a second database in Relay Everything, only for the AI agents on your computers. An agent can make any table there and keep its own data, such as a reading list or a plan. Your notes, health, places, chats and memory are in your space, not in this database, so no command sent to it can read or change them.

- **Who reaches it:** only a computer connected with [Relay Everything in Claude Code or Codex](../../connections/claude-code/), or your own plugin with a computer's key. An API key, your [AI connector](../../connections/connect-your-ai/) and a phone's key are refused.
- **What goes out:** nothing. No webhook, export or AI connector reads it, and Relay Everything puts no health or location data into it.
- **When it goes:** *Delete my account* deletes it with your space.

## Send commands

Each command is SQLite, sent with the computer's key as `Authorization: Bearer`:

```http
POST /v1/db
{ "sql": "INSERT INTO reading_list (title) VALUES (?)", "params": ["Dune"] }
```

The answer has one result for each command: the rows it read and how many rows it wrote.

```json
{ "results": [{ "rows": [], "changed": 1 }] }
```

To send several commands in one step, all or none, send `{ "batch": [{ "sql": "…", "params": [] }, …] }`. A blob reads back as `{ "base64": "…" }`. A command that fails answers `400` with SQLite's reason, and nothing in its step stays.

`GET /v1/db/tables` lists each table, with its columns and how many rows it holds. Read it before you make a table: another agent may have made one already.

With Relay Everything in the project, the AI runs `relay.mjs db "<sql>"`, `relay.mjs db --file <path>` and `relay.mjs db tables`.

## Limits

| Limit | Size |
| --- | --- |
| One command | 100 KB |
| Commands in one step | 50 |
| One answer | 5,000 rows and 5 MB |
| The database | 1 GB |

A step past a limit is refused with the limit, and nothing it wrote stays. Add `LIMIT` to a read that is too big. The whole route is in the [web API reference](../v1-reference/).
