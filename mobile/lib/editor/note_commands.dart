import 'package:super_editor/super_editor.dart';

import 'markdown.dart';
import 'note_editing.dart';
import 'shortcuts.dart';

/// The words picked, or the cursor's line, in a note: the styles they have, and each style the format tools set. The
/// Format sheet, the bars, the computer's menu and keys, and the Mac's *Format* menu all style through this.
class NoteCommands {
  const NoteCommands(this.editing);

  final NoteEditing editing;

  DocumentSelection? get _selection => editing.composer.selection;

  /// The inline styles on every letter picked, or, at a cursor, the styles the next letter typed takes.
  Set<Attribution> get inline {
    final selection = _selection;
    if (selection == null) return const {};
    if (selection.isCollapsed) return editing.composer.preferences.currentAttributions;
    Set<Attribution>? all;
    for (final (node, start, end) in _pieces(selection)) {
      if (start >= end) continue;
      final here = node.text.getAllAttributionsThroughout(SpanRange(start, end - 1));
      all = all == null ? here : all.intersection(here);
    }
    return all ?? const {};
  }

  /// Each text node the selection touches, with the part of its words it holds.
  List<(TextNode, int, int)> _pieces(DocumentSelection selection) {
    final document = editing.document;
    final range = document.getRangeBetween(selection.base, selection.extent);
    final pieces = <(TextNode, int, int)>[];
    for (final node in document.getNodesInside(range.start, range.end)) {
      if (node is! TextNode) continue;
      final start = node.id == range.start.nodeId ? _offset(range.start.nodePosition) : 0;
      final end = node.id == range.end.nodeId ? _offset(range.end.nodePosition) : node.text.length;
      pieces.add((node, start, end));
    }
    return pieces;
  }

  static int _offset(NodePosition position) => position is TextNodePosition ? position.offset : 0;

  bool has(Attribution attribution) => inline.contains(attribution);

  /// The highlight colour of the words picked, or null.
  String? get highlight => inline.whereType<HighlightAttribution>().firstOrNull?.colour;

  /// Whether the words picked hold a link.
  bool get linked {
    final selection = _selection;
    if (selection == null) return false;
    if (selection.isCollapsed) {
      final node = editing.extentNode;
      final at = _offset(selection.extent.nodePosition);
      return node is TextNode && at > 0 && node.text.getAllAttributionsAt(at - 1).any((one) => one is LinkAttribution);
    }
    return _pieces(selection).any((piece) => [
      for (var at = piece.$2; at < piece.$3; at++) piece.$1.text.getAllAttributionsAt(at).any((one) => one is LinkAttribution),
    ].any((linked) => linked));
  }

  /// The kind of the cursor's line.
  LineKind? get kind => switch (editing.extentNode) {
    final TextNode node => kindOf(node),
    _ => null,
  };

  /// The list kind of the cursor's line, such as [LineKind.bullet], or null.
  LineKind? get list => switch (kind) {
    LineKind.bullet || LineKind.dashed || LineKind.numbered || LineKind.unchecked || LineKind.checked => kind,
    _ => null,
  };

  /// The cursor's line style: Title, Heading, Subheading, Monostyled or Body.
  FormatAction get lineStyle => switch (kind) {
    LineKind.code => FormatAction.monostyled,
    LineKind.header1 => FormatAction.title,
    LineKind.header2 => FormatAction.heading,
    LineKind.header3 => FormatAction.subheading,
    _ => FormatAction.body,
  };

  /// [attribution] on the words picked, or off when they all have it. At a cursor, the next letters typed.
  void toggle(Attribution attribution) {
    final selection = _selection;
    if (selection == null) return;
    if (selection.isCollapsed) {
      editing.composer.preferences.toggleStyle(attribution);
      return;
    }
    final range = editing.document.getRangeBetween(selection.base, selection.extent);
    editing.editor.execute([
      if (has(attribution)) RemoveTextAttributionsRequest(documentRange: range, attributions: {attribution})
      else AddTextAttributionsRequest(documentRange: range, attributions: {attribution}),
    ]);
  }

  static final _highlights = {for (final colour in highlightColours) HighlightAttribution(colour)};

  /// The highlight pen: [colour] on the words picked, or off when they have a highlight.
  void highlightWith(String colour) => highlight != null ? _setHighlight(null) : _setHighlight(colour);

  /// Words with a highlight take [colour] in place of their own.
  void recolour(String colour) {
    if (highlight != null) _setHighlight(colour);
  }

  void _setHighlight(String? colour) {
    final selection = _selection;
    if (selection == null) return;
    if (selection.isCollapsed) {
      final preferences = editing.composer.preferences;
      preferences.removeStyles(_highlights);
      if (colour != null) preferences.addStyle(HighlightAttribution(colour));
      return;
    }
    final range = editing.document.getRangeBetween(selection.base, selection.extent);
    editing.editor.execute([
      RemoveTextAttributionsRequest(documentRange: range, attributions: _highlights),
      if (colour != null) AddTextAttributionsRequest(documentRange: range, attributions: {HighlightAttribution(colour)}),
    ]);
  }

  /// The text lines the selection touches, each changed by [change], as one change.
  void _lines(TextNode Function(TextNode node) change) {
    final picked = {for (final node in editing.selectedTextNodes) node.id};
    if (picked.isEmpty) return;
    editing.breakTyping();
    editing.setNodes([
      for (final node in editing.nodes) node is TextNode && picked.contains(node.id) ? change(node) : node,
    ], keepSelection: true);
  }

  /// The lines the selection touches as [kind], each keeping its words and indent.
  void setKind(LineKind kind) => _lines((node) => kindOf(node) == kind ? node
    : lineNode(kind, node.text, indent: indentOf(node), id: node.id));

  /// A list kind on the cursor's lines: a second time on the same kind takes it off.
  void listOf(LineKind kind) => setKind(this.kind == kind ? LineKind.paragraph : kind);

  /// The lines one indent level in, or out.
  void indent(bool more) => _lines((node) {
    final level = (indentOf(node) + (more ? 1 : -1)).clamp(0, 8);
    return level == indentOf(node) ? node : lineNode(kindOf(node), node.text, indent: level, id: node.id);
  });

  /// A line's style: one header level, Monostyled, which a second time takes off, or Body.
  void line(FormatAction style) {
    if (style == FormatAction.monostyled) return setKind(kind == LineKind.code ? LineKind.paragraph : LineKind.code);
    setKind(switch (style) {
      FormatAction.title => LineKind.header1,
      FormatAction.heading => LineKind.header2,
      FormatAction.subheading => LineKind.header3,
      _ => LineKind.paragraph,
    });
  }

  /// *Checklist*: the lines become checklist items, or stop being them.
  void checklist() => setKind(kind == LineKind.checked || kind == LineKind.unchecked ? LineKind.paragraph : LineKind.unchecked);

  /// Does [action], with [colour] for the highlight pen. False for *Link* and *Table*, which the page does itself.
  bool run(FormatAction action, {String colour = 'purple'}) {
    switch (action) {
      case FormatAction.bold: toggle(boldAttribution);
      case FormatAction.italic: toggle(italicsAttribution);
      case FormatAction.underline: toggle(underlineAttribution);
      case FormatAction.strikethrough: toggle(strikethroughAttribution);
      case FormatAction.highlight: highlightWith(colour);
      case FormatAction.title || FormatAction.heading || FormatAction.subheading || FormatAction.body ||
          FormatAction.monostyled:
        line(action);
      case FormatAction.bulleted: listOf(LineKind.bullet);
      case FormatAction.dashed: listOf(LineKind.dashed);
      case FormatAction.numbered: listOf(LineKind.numbered);
      case FormatAction.checklist: checklist();
      case FormatAction.tick:
        if (kind == LineKind.unchecked) setKind(LineKind.checked);
        if (kind == LineKind.checked) setKind(LineKind.unchecked);
      case FormatAction.quote: setKind(kind == LineKind.quote ? LineKind.paragraph : LineKind.quote);
      case FormatAction.indentMore: indent(true);
      case FormatAction.indentLess: indent(false);
      case FormatAction.link || FormatAction.table: return false;
    }
    return true;
  }
}
