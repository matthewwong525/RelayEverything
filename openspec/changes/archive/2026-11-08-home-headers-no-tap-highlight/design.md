## Context

`_FoldHeader` in `mobile/lib/screens/home.dart` wraps the section name in an `InkWell`. The ink paints the theme's highlight and splash over the whole header row, which shows as a grey box on a dark screen.

## Decisions

- Replace the `InkWell` with a `GestureDetector` with `behavior: HitTestBehavior.opaque`, so the whole row, padding included, still takes the tap. Keep the `Semantics(button: true, expanded: …)` wrapper, so screen readers still read it as a button. Alternative: keep `InkWell` with transparent `splashColor`/`highlightColor`; rejected, because it still paints a hover and focus shade and keeps a Material look the app moves away from.
- Folder rows keep `ListTile`'s ink: they open a page, and the person asked only about the header.

## Risks / Trade-offs

- No press feedback on the header → the chevron turns at once, which is the feedback Apple Notes gives.

## UX

Phone-first, no layout change: the header looks the same at rest; only the press state goes.
