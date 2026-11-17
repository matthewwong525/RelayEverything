# Tasks

## 1. The recording's page

- [x] 1.1 In `mobile/lib/screens/note_blocks.dart`, add `RecordingPage`: `BackTo` with the note's title (or *Note*), a `RoundIconButton` copy (tooltip *Copy transcript*) and, while editing, the round check button; the date and length under the top; the words in a scroll view, as a `TextField` with every border set to `InputBorder.none` when editable, else `SelectableText`; a `VoicePlayer` in a `Card` at the bottom in the safe area
- [x] 1.2 Move the words controller, focus, `_keep` and `didUpdateWidget` sync from `_RecordingCardState` to the page; keep on blur, on the check button and on dispose
- [x] 1.3 In `RecordingCard`, replace the fold with a *Transcript ›* row (`CupertinoIcons.chevron_right`) in a `GestureDetector` with `HitTestBehavior.opaque`, pushing `RecordingPage` on the nearest `Navigator`; keep the writing, failed and no-words states in the card; remove the `InkWell`
- [x] 1.4 Pass what the page needs (note title, date, editable) from `mobile/lib/screens/note_editor.dart` where it builds the card

## 2. Tests and the device check

- [x] 2.1 In `mobile/test/screens_test.dart`, change the transcript tests: the card shows *Transcript* and none of the words; a tap opens the page with all words, copy and a player; the field has no border (no `OutlineInputBorder` drawn); a fix on the page is kept on back; a note from another phone shows read-only words; no `InkWell` in the card's row
- [x] 2.2 In `mobile/device-check/flows/recording-card.yaml`, tap *Transcript*, assert *Copy transcript* on the page, take the screenshot, then go *Back* before typing in the note; update the file's top comment

## 3. Website

- [x] 3.1 Update *Read the transcript* in `site/src/content/docs/app/voice-notes.md` and the recording lines in `site/src/content/docs/app/your-notes.md` to say a tap on *Transcript* opens the recording's page

## 4. Checks

- [x] 4.1 Run `flutter analyze` and `flutter test` in `mobile/`, and `node scripts/product-name.test.mjs`
- [x] 4.2 `/save` passes the gate; the iPhone look on the next TestFlight build is an open thread after the publish, because TestFlight builds only from `main`
