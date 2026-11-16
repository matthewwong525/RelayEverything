import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import 'markdown.dart' show dashedList;

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

/// The Mac's *Format* menu, in its order, with each item's key. The keys of [formatShortcuts] are these and
/// [_moreKeys], so the menu and the keys can not drift.
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

/// The line styles again with ⌥: Chrome keeps Ctrl+Shift+T and others for itself.
final _moreKeys = <FormatKey>[
  _key('Title', FormatAction.title, LogicalKeyboardKey.digit1, alt: true),
  _key('Heading', FormatAction.heading, LogicalKeyboardKey.digit2, alt: true),
  _key('Subheading', FormatAction.subheading, LogicalKeyboardKey.digit3, alt: true),
  _key('Body', FormatAction.body, LogicalKeyboardKey.digit0, alt: true),
];

/// A format key pressed in the note.
class FormatIntent extends Intent {
  const FormatIntent(this.action);

  final FormatAction action;
}

/// Whether the keys use ⌘: on a Mac, and on an iPad with a keyboard.
bool get commandKeys => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

/// Every format key, with ⌘ on a Mac and Ctrl elsewhere. Off a Mac, AltGr comes as Ctrl and Alt, so a Ctrl+Alt digit
/// key made with AltGr, such as } on a German keyboard, types its letter and styles nothing.
Map<ShortcutActivator, Intent> formatShortcuts({bool? mac}) {
  final command = mac ?? commandKeys;
  ShortcutActivator keys(FormatKey item) {
    final keys = SingleActivator(item.key, meta: command, control: !command, shift: item.shift, alt: item.alt);
    return command || !_moreKeys.contains(item) ? keys : _NotAltGr(keys);
  }
  return {
    for (final item in [...formatItems.expand((group) => group), ..._moreKeys]) keys(item): FormatIntent(item.action),
  };
}

/// [keys], but not while AltGr, the right Alt key, is down.
class _NotAltGr extends ShortcutActivator {
  const _NotAltGr(this.keys);

  final SingleActivator keys;

  static final _altGr = {LogicalKeyboardKey.altRight, LogicalKeyboardKey.altGraph};

  @override
  Iterable<LogicalKeyboardKey>? get triggers => keys.triggers;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
    keys.accepts(event, state) && !state.logicalKeysPressed.any(_altGr.contains);

  @override
  String debugDescribeKeys() => '${keys.debugDescribeKeys()}, not AltGr';
}

/// The Markdown marks typed at the start of a line, and the line style each gives, as Notes reads them.
const _lineMarks = <String, Map<String, dynamic>>{
  '#': {'header': 1},
  '##': {'header': 2},
  '###': {'header': 3},
  '-': {'list': dashedList},
  '*': {'list': 'bullet'},
  '1.': {'list': 'ordered'},
  '[]': {'list': 'unchecked'},
  '>': {'blockquote': true},
};

/// Whether [words] at the start of a line are Markdown marks that a space turns into the line's style.
bool isLineMark(String words) => _lineMarks.containsKey(words);

/// The change after a space typed at [index] in [document] when the words before it in its line are one of the
/// Markdown marks, such as `#`: the marks and the space go and the line takes their style, with the line's other
/// styles off. Null for any other space. A code block keeps its marks as words.
Delta? lineMarkChange(Document document, int index) {
  final text = document.toPlainText();
  if (index <= 0 || index >= text.length || text[index] != ' ') return null;
  final start = text.lastIndexOf('\n', index - 1) + 1;
  final style = _lineMarks[text.substring(start, index)];
  if (style == null) return null;
  final end = text.indexOf('\n', index);
  final line = document.collectStyle(index, 0).attributes;
  if (line.containsKey(Attribute.codeBlock.key)) return null;
  final attributes = <String, dynamic>{
    for (final key in ['header', 'list', 'blockquote']) if (line.containsKey(key)) key: null,
    ...style,
  };
  return Delta()
    ..retain(start)
    ..delete(index - start + 1)
    ..retain(end - index - 1)
    ..retain(1, attributes);
}
