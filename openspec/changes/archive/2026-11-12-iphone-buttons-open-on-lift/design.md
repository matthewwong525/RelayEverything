# Design

## Context

Flutter's `Tooltip`, which `IconButton(tooltip:)` wraps around each round button, adds a `LongPressGestureRecognizer` on each touch when `triggerMode` is `longPress`, the default. After `kLongPressTimeout` (500 ms) the long press wins the gesture arena, the `InkWell`'s tap is rejected, and the tooltip shows. A Maestro tap that lasts about 1 second on a slow GitHub Mac crosses that line.

`RawTooltip` with `TooltipTriggerMode.manual` adds no recognizer, but still writes `Semantics(tooltip: …)`, so `find.byTooltip`, VoiceOver and Maestro's `tapOn: "Settings"` still find the button. Mouse hover still shows the tooltip.

Proof, run in `.scratch/` on 2026-11-12 with Flutter 3.47.9: an `IconButton` held 1 second fired `onPressed` 0 times with the default theme and 1 time with `triggerMode: manual`. The `pictures/` cards come from the same press on the real `RelayApp`.

## Goals / Non-Goals

**Goals:** on iOS, each `Tooltip`-wrapped button fires on lift however long the press, and keeps its semantics label.

**Non-Goals:** `NewNoteButton`'s own `GestureDetector` (`onLongPress` records) is not a tooltip and does not change. A slow Maestro tap on *New note* can still start a recording; the fixed tour has not shown that, so it waits for evidence.

## Decisions

- **Theme, not each button.** Set `tooltipTheme: TooltipThemeData(triggerMode: TooltipTriggerMode.manual)` once, for iOS only. Alternative: drop `tooltip:` from each of about 35 buttons and add `Semantics(label:)`: more edits, and a new button would bring the bug back.
- **Read the platform in `RelayApp.build`, not in the top-level `_light`/`_dark` finals.** The finals are made once per process, so a test's `debugDefaultTargetPlatformOverride` would not reach them. Wrap them with a small `_iPhoneButtons(ThemeData)` helper that checks `defaultTargetPlatform == TargetPlatform.iOS`.
- **No flow retry.** A `runFlow` with `when: notVisible: "Appearance"` that taps again fails whenever the second tap is slow too, and hides a fault a person can hit. The tour's existing second try still catches other slow-Mac faults.

## Risks / Trade-offs

- [A person on iPhone loses the long-press name of an icon] → iPhone apps show none; VoiceOver still reads it.
- [Another screen sets its own `Tooltip(triggerMode:)`] → none do today (`grep triggerMode mobile/lib` is empty); a later one would override the theme on purpose.
- [The web shell on an iPhone browser also gets `manual`] → it acts like the app there, and the mouse hover on a computer is unchanged.
