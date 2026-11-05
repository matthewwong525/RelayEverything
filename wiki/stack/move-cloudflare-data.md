# Move Cloudflare data to a new name

You move a D1 database or an R2 bucket to a new name with [`scripts/cf-move-data.mjs`](../../scripts/cf-move-data.mjs): it copies every row and file inside your Cloudflare account, then checks both sides. It is part of [the Cloudflare stack](README.md).

## Why a copy

Cloudflare can't rename a D1 database or an R2 bucket. A new name is a new, empty store. So you make the new store, give it the schema, copy the data, and point the config at it. The old store stays until you say yes to delete it.

## The rule: the data stays in the account

Rows and files go from store to store inside Cloudflare, never through your computer. `wrangler d1 export` and R2 downloads put health, places and recordings in a file on your computer, so the tool never uses them. The tool prints only table names, bucket names and counts.

## Run a move

1. Make the new stores. Apply the schema to each new database: `npx wrangler d1 migrations apply <new-db> --remote` for the app's database, and the [memory skill's migrations](../development/memory.md) for a memory store. The copy fills rows only.
2. Copy and check. Name each pair as `<old>=<new>`:

   ```bash
   node scripts/cf-move-data.mjs --d1 old-db=new-db --r2 old-files=new-files
   ```

3. Copy again with `--replace` when the old store can change after the first copy. Stop the writes first, for example with a hold page, so nothing changes between the copy and the check.
4. Use `--check-only` to compare both sides again with no copy.

The tool reads `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the primary checkout's `.env` ([Cloudflare credentials](cloudflare-credentials.md)). The token needs D1, R2 and Workers Scripts write.

## What it does

- **A one-off Worker** binds each old and new store. The tool writes its config in a temporary folder outside the repository, makes a random key in memory, and sets the key as the Worker's secret through stdin. It never prints or saves the key. It deletes the Worker at the end, also when the move fails.
- **D1:** it copies each table in pages, a table after the tables its rows name. A second run adds what is missing and doubles nothing. `--replace` also takes changed rows, but never a column that a `BEFORE UPDATE` trigger guards, such as a memory fact's words. It skips SQLite's and Cloudflare's own tables, the migration ledgers (`d1_migrations`, `schema_migrations`), and FTS5 index tables. During the copy it turns off the new side's `AFTER` triggers, because they would write rows again that the copy already brings, such as an outbox row for each note; then it puts them back and rebuilds each search index. A run you stop with Ctrl-C puts them back before it deletes the Worker. Before it turns them off, it saves their SQL in the new database, in `_move_paused_triggers`. If a run still leaves them off, the check reports `triggers ... missing=<n> mismatch`: run the move again. It puts back the triggers that the stopped run paused, from that saved SQL, and rebuilds the search indexes. Then `--check-only` shows `triggers ... missing=0 ok`. It never adds an old side's trigger that the new side never had. Don't apply the schema again: the migration ledgers say each migration is already applied, so that does nothing.
- **A table the new side lacks:** the tool copies the other tables, then the move fails and names that table. Give the new side the old side's schema, then run the move again.
- **R2:** it copies each file that is missing on the new side or has another size or ETag, with its content type and custom metadata.

## The check

Each line names one table, index or bucket, then `ok` or `mismatch`. The last line is `result=passed` or `result=failed`.

```text
table relay_notes old=1200 new=1201 missing=0 differ=0 extra=1 ok
triggers old=9 new=9 missing=0 ok
index facts_fts rows=310 source=310 ok
bucket old-files -> new-files old=80 new=80 bytes_old=9100000 bytes_new=9100000 missing=0 differ=0 extra=0 ok
```

- `missing`: old rows or files that the new side doesn't have. The move fails.
- `differ`: old rows whose new copy has other values, matched by primary key, or files with another size or ETag. The move fails. A memory fact saved to both stores under the same id shows here: save the old fact again under a new id with the memory skill.
- `extra`: rows or files only the new side has, such as a note that came in at the new address. The move still passes.
- `index`: an FTS5 index has one row for each row of its table.

## Delete the old store only on a yes

A passed move doesn't delete anything. The old store is a free way back while the new one settles. Ask the owner, with the counts from the check, before you delete each old database, bucket or Worker: a delete can't be undone. Before you delete a D1 database, record `npx wrangler d1 time-travel info <old-db>`.
