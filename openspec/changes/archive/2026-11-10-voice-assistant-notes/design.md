## Context

`AddNoteIntent` in `mobile/ios/Runner/RelayIntents.swift` keeps a note through `ShortcutsEngine`: the app's engine, a headless engine, or `shortcuts-inbox/` as a fallback. Its `text` and `files` are both optional, so Siri asks for neither, and the empty call fails with *no words and no files*. `RelayShortcuts` gives Siri two phrases for it, each with `.applicationName`, which Siri hears as *Relay Everything* from `CFBundleDisplayName`.

Apple's App Shortcut phrases can hold only entity or enum parameters, never a free `String`, so the classic Siri can't take a note's words in the phrase. The new Siri in iOS 27 reads each App Intent's title, parameters and descriptions and can fill a `String` from the whole request.

## Goals / Non-Goals

**Goals:** one sentence to the new Siri makes one note; the old Siri asks once; *Relay* works as a spoken name.

**Non-Goals:** no new intent; no SiriKit `INCreateNoteIntent` or Intents extension; no change to how a kept note syncs.

## Decisions

### 1. Describe the words so the new Siri fills them

`text` becomes `@Parameter(title: "Note", description: "The words of the note, as the person says them", requestValueDialog: "What's the note?")`. The intent's description leads with *Takes a note in Relay Everything from what you say or give it*. The new Siri maps *take a note in Relay, buy milk* to `AddNoteIntent(text: "buy milk")` from these words. Changing the title from *Words* to *Note* changes the line in Shortcuts to *Add Note with Files to Relay Everything*; saved shortcuts keep their values, since the property name `text` stays.

Alternative: an Apple assistant schema. Rejected: none fits a plain note, and a wrong schema would make Siri call the action for the wrong request.

### 2. Ask in `perform`, not a required parameter

When `text` is empty and `files` is empty, `perform` calls `try await $text.requestValue()`, which uses the `requestValueDialog`. A required `text` would break shortcuts that pass only files. In an automation with no one to answer, `requestValue` throws, and the action fails with today's message and keeps nothing. The result returns `.result(value:dialog:)` with *Saved*.

### 3. *Relay* as an app-name synonym

`Info.plist` gains `INAlternativeAppNames` with one entry, `INAlternativeAppName` *Relay*, which App Shortcuts uses as a second `.applicationName`. `CFBundleDisplayName` stays *Relay Everything*. `RelayShortcuts` adds *Take a note in \(.applicationName)* and *Note in \(.applicationName)*, beside today's *Add a note to* and *Keep a note in*.

### 4. The product-name check allows only these literals

`scripts/product-name.test.mjs` refuses a bare *Relay*. Its empty `ALLOWED` list gets the plist's `<string>Relay</string>` beside `INAlternativeAppName`, and the website's spoken phrases (*take a note in Relay*, *add a note to Relay*, *note in Relay*), each as an exact literal. Nothing else changes in the check.

## Risks / Trade-offs

- [The new Siri may still ask, or pick another app] → The fallback question keeps it working; the person checks it on their iPhone through TestFlight, and the description is the one place to tune.
- [*Relay* may clash with another app's name on the person's phone] → Siri then asks which app; the long name still works.
- [The Shortcuts line changes from *Words* to *Note*] → Only the label; saved shortcuts keep their values.
