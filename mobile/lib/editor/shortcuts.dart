import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

/// Each thing the note page's format tools do: the Format sheet and menu, the bars, the keys and the Mac's *Format*
/// menu all name one of these, so they do the same thing.
enum FormatAction {
  bold, italic, underline, strikethrough, highlight,
  title, heading, subheading, body, monostyled,
  bulleted, dashed, numbered, checklist, tick,
  quote, indentMore, indentLess, link, table,
}

/// One format item with its key, as Notes on a Mac has it: ⌘ with [shift] and [alt] on a Mac, Ctrl elsewhere.
typedef FormatKey = ({String label, FormatAction action, LogicalKeyboardKey key, bool shift, bool alt});

FormatKey _key(String label, FormatAction action, LogicalKeyboardKey key, {bool shift = false, bool alt = false}) =>
  (label: label, action: action, key: key, shift: shift, alt: alt);

/// The Mac's *Format* menu, in its order, with each item's key. The editor page, `mobile/editor-web/src/`, has the same
/// keys, and Alt+1, 2, 3 and 0 for the line styles, as Chrome keeps Ctrl+Shift+T and others for itself.
final formatItems = <List<FormatKey>>[
  [
    _key('Bold', FormatAction.bold, LogicalKeyboardKey.keyB),
    _key('Italic', FormatAction.italic, LogicalKeyboardKey.keyI),
    _key('Underline', FormatAction.underline, LogicalKeyboardKey.keyU),
    _key('Strikethrough', FormatAction.strikethrough, LogicalKeyboardKey.keyX, shift: true),
    _key('Highlight', FormatAction.highlight, LogicalKeyboardKey.keyE, shift: true),
  ],
  [
    _key('Title', FormatAction.title, LogicalKeyboardKey.keyT, shift: true),
    _key('Heading', FormatAction.heading, LogicalKeyboardKey.keyH, shift: true),
    _key('Subheading', FormatAction.subheading, LogicalKeyboardKey.keyJ, shift: true),
    _key('Body', FormatAction.body, LogicalKeyboardKey.keyB, shift: true),
    _key('Monostyled', FormatAction.monostyled, LogicalKeyboardKey.keyM, shift: true),
  ],
  [
    _key('Bulleted List', FormatAction.bulleted, LogicalKeyboardKey.digit7, shift: true),
    _key('Dashed List', FormatAction.dashed, LogicalKeyboardKey.digit8, shift: true),
    _key('Numbered List', FormatAction.numbered, LogicalKeyboardKey.digit9, shift: true),
    _key('Checklist', FormatAction.checklist, LogicalKeyboardKey.keyL, shift: true),
    _key('Mark as Ticked', FormatAction.tick, LogicalKeyboardKey.keyU, shift: true),
  ],
  [
    _key('Block Quote', FormatAction.quote, LogicalKeyboardKey.quoteSingle),
    _key('Indent More', FormatAction.indentMore, LogicalKeyboardKey.bracketRight),
    _key('Indent Less', FormatAction.indentLess, LogicalKeyboardKey.bracketLeft),
  ],
  [
    _key('Link…', FormatAction.link, LogicalKeyboardKey.keyK),
    _key('Table', FormatAction.table, LogicalKeyboardKey.keyT, alt: true),
  ],
];

/// Whether the keys use ⌘: on a Mac, and on an iPad with a keyboard. Elsewhere they use Ctrl. The note's editor page
/// does the format keys itself, with the same keys as [formatItems].
bool get commandKeys => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
