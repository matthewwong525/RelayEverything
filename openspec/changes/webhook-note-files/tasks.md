# Tasks

## 1. Space migration

- [x] 1.1 Write `schema/space-migrations/0007_note_files.sql`: rebuild `relay_outbox` with `note.file`, make the log triggers again, add the `relay_attachments` trigger, and log stored files once
- [x] 1.2 Extend `webhooks/migration.test.ts` and `space-schema.test.ts`: seqs and webhook places kept, a sealed file logs one row after its note, a file listed but not sent logs none, stored files logged once

## 2. Server

- [x] 2.1 `webhooks/format.ts`: `noteFile` builder; descriptions of `note.file` and `attachments` say the server sends it too
- [x] 2.2 `webhooks/sign.ts` and `send.ts`: build and sign a body as bytes; `post` takes bytes
- [x] 2.3 `kinds.ts`: Notes owns `note.file` with its builder (`skip` when gone); the Files reason points at Notes
- [x] 2.4 `send.ts`: a 413 to `note.file` skips the file and names it in `last_error`
- [x] 2.5 Tests in `format.test.ts`, `send.test.ts` and `kinds.test.ts`: order after the note, same `webhook-id` on retry, a 413 skips only the file, a deleted note skips its file, the body's signature checks, a 25 MB file's body is valid JSON
- [x] 2.6 Add a note with a stored file to the sample rows the check starts from (`app/tests/relay-space-rows.sql` or `schema/seed.sql`)

## 3. Website and wiki

- [x] 3.1 `site/public/webhooks/receiver.mjs`: keep each listed file, then its bytes; `webhooks/receiver.test.ts` covers both
- [x] 3.2 `site/src/content/docs/connections/your-database.md`: the server sends `note.file`; how large a body to accept; a 413 skips a file and the card names it; files stored before go once
- [x] 3.3 Run `npm run relay:api-doc` in `app/` to make `v1.schema.json` again
- [x] 3.4 `wiki/relay-spaces.md` *Webhooks*: files are logged when sealed and go as `note.file`

## 4. Checks

- [x] 4.1 Run `npm test` in `app/` and `node scripts/public-check.mjs`
- [ ] 4.2 `/save`, then on staging: a note with a 25 MB file and a small photo reaches the example receiver behind a tunnel with both files' bytes; a receiver that answers 413 to files gets the next note, and the card names the skipped file
