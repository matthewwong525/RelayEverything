# The note editor

The note editor is the page where a person writes a note, on the iPhone, Android, the Mac app and the web page. It is a [Tiptap](https://tiptap.dev) web page in a web view, and this page gives what is not clear from the code: why a web editor, how the app and the page talk, and what to check before a change. Up: [the wiki](README.md).

## Why a web editor

- **Until 2026-11-19 the editor was flutter_quill, then super_editor** ([PR #155](https://github.com/matthewwong525/RelayEverything/pull/155)). Both are Flutter editors: Flutter draws each letter, so the editor also draws the cursor, the handles and the magnifier, and reads the keyboard through its own code. On a phone the copy is close, never equal, and in the browser the note was a picture that the browser's selection, spell check and find did not see.
- **Tiptap uses the system's own text editing on each platform.** The cursor, the handles, the text menu, autocorrect, dictation and spell check are the iPhone's, Android's, the Mac's or the browser's own. What shipped is in [the note editing spec](../openspec/specs/relay-note-editing/spec.md).
- **Notes stay the same Markdown.** The server, AI apps and webhooks read the same text as before. The Dart code stays the one reader and writer of Markdown and of a paste: the page gets and gives only the editor's document, as JSON.

## Where the code is

- [`mobile/editor-web/`](../mobile/editor-web/): the editor page. `src/schema.js` holds the document's parts, `src/editor.js` the bridge and the commands, `src/cards.js` the file and recording cards, and `test/editor.test.mjs` the tests in a real Chromium.
- [`mobile/assets/editor/`](../mobile/assets/): the built page that the app ships. Never edit it by hand: run `npm run build` in `mobile/editor-web/`. CI refuses a build whose `source.sha256` does not match `src/`.
- [`mobile/lib/editor/web_note/`](../mobile/lib/editor/web_note/): `WebNote`, the app's side of the bridge; the web view host for the phones and the Mac, and the frame host for the web page; and `WebNotePool`, which starts a page before a note needs it.
- [`mobile/lib/screens/note_editor.dart`](../mobile/lib/screens/note_editor.dart): the note page, its bars, saving, files and recordings. [The phone app's README](../mobile/README.md#where-the-code-is) gives each file.

## How the app and the page talk

The app and the page send small JSON messages. The app's have `do`; the page's have `is`.

- **The app sends** `load` (the document, the colours, the date line and each file's look), `run` (one command, such as `bold` or `line heading`), `files`, `theme`, `bottom`, `head`, `highlight` and the answer to a `paste`.
- **The page sends** `ready`, `changed` (the whole document after each change), `state` (the cursor's styles, for the bars), `paste` (the HTML, for the Dart paste reader), `tap` (on a card: play, seek, open), `open` (a link), `keys` and `drop`.
- **The app keeps the words after each change.** The system can stop a web view in the background: `WebNote.gone` starts the page again with the last document.

## The tests

- **The page's typing tests run in Chromium**: `npm test` in `mobile/editor-web/`. Write a test for typing, a key, a paste's placement or a card there.
- **The Flutter tests use `FakeWebNote`** from [`mobile/test/fakes.dart`](../mobile/test/fakes.dart): a test reads the messages sent (`runs`, `loaded`, `viewOf`) and plays the page's (`write`, `say`, `tap`, `key`).
- **The golden notes** in `mobile/test/golden_notes.dart` must come back byte for byte through the page's document. Add each new kind of note text there.

## Where a web editor is hard

- **The keyboard and our bars.** A bar button takes no focus, so the keyboard stays up when it is tapped. On the iPhone, `RelayWebKeyboard.swift` hides the bar of arrows over the keyboard and lets the page raise the keyboard for a new note.
- **Android keyboards.** Web editors have had typing bugs with some keyboards: test with Gboard and a Samsung keyboard.
- **The web page's frame.** Flutter web shows the editor in an iframe. The frame gets the page as text (`srcdoc`, with a `<base>`), never from an address that ends in `.html`: the Cloudflare assets answer `.../index.html` with a 307 to the folder, and the Worker then serves the main app there. Hide the frame with its own CSS opacity, never a Flutter `Opacity` of 0: Flutter then skips the paint, and the frame never enters the page. A Flutter bar or menu over the frame gets no click without `pointer_interceptor`; [`cover.dart`](../mobile/lib/editor/web_note/cover.dart) turns the frame's clicks off while a menu is open.
- **Moving a block by touch.** A drag is weak in web editors on a phone: plan a *Move up* and *Move down* menu.

## Before you change the editor package

- **Keep Markdown as the stored form.** The server, the AI connector, webhooks and old notes read it, whatever editor shows it.
- **Pin each package of `mobile/editor-web/` to one exact version**, with the lock file. A new version is its own change, with a new build.
- **The other editors, as of November 2026**: [appflowy_editor](https://pub.dev/packages/appflowy_editor) does not build on a current Flutter and has an unclear license; [fleather](https://pub.dev/packages/fleather) and [flutter_quill](https://pub.dev/packages/flutter_quill) have no blocks; super_editor draws its own text, as above; a native editor for each platform gives the best feel, but three or four editors to keep.

## Before you merge a change to the editor

Check these by hand on a real iPhone, because the tests do not catch them:

- **No bar of arrows over the keyboard**, and the keyboard stays up on a bar tap.
- **The cursor stays above the bar** while you type at the end of a long note.
- **A new note opens with the keyboard up.**
- **No white flash** when a note opens in dark mode, and the cursor shows in dark mode.
- **Tab moves every selected line**, not only the first.
- **A triple-tap selects one line**: the iPhone check taps too slowly to count as three.
