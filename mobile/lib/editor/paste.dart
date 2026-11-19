import 'dart:math';

import 'package:flutter/painting.dart' show TextAffinity;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:super_editor/super_editor.dart';

import 'attachments.dart';
import 'markdown.dart';
import 'table.dart';

// Every paste into a note goes through here: the iPhone's own Paste, the editor's own menu and keys, and the browser.
// A paste keeps only the styles a note can store as Markdown, so the page shows what the note keeps.

/// What a paste puts in a note: [html] when it holds words, else [plain] read as Markdown, as a note's own words are.
/// Only the note's styles stay: headings 1 to 3, lists with their indent, quotes, code blocks, tables, links on words,
/// and bold, italic, underlined and struck words.
/// Runs of empty lines become one, and empty lines at the start and end go. The result has gone to Markdown and back,
/// so it is what the note stores; it is empty when the paste has no words. A file's line is a file only when [files]
/// holds its id, or [files] is null.
List<DocumentNode> pastedNodes({String? html, required String plain, Set<String>? files}) {
  final fromHtml = html == null || html.trim().isEmpty ? null : _HtmlReader().read(html);
  final lines = _tidy(fromHtml != null && fromHtml.any((line) => line.words.trim().isNotEmpty)
    ? fromHtml
    : [for (final node in markdownToNodes(_plainMarkdown(plain), files: files)) _Line.of(node)]);
  if (lines.isEmpty) return const [];
  return markdownToNodes(documentToMarkdown([for (final line in lines) line.node()]), files: files);
}

/// A line's style: its kind and its indent.
typedef _Style = (LineKind, int);

_Style _lineStyleOf(DocumentNode node) => (kindOf(node), indentOf(node));

bool _plain(_Style style) => style == (LineKind.paragraph, 0);

/// [nodes] with [range] taken out, and where the caret goes. Two lines the range joins become one, in the style of
/// the last, as a line's style is at its end.
({List<DocumentNode> nodes, DocumentPosition caret}) deleteRange(List<DocumentNode> nodes, DocumentRange range) {
  final ids = [for (final node in nodes) node.id];
  var (start, end) = (range.start, range.end);
  if (ids.indexOf(start.nodeId) > ids.indexOf(end.nodeId) || (start.nodeId == end.nodeId &&
      _offsetIn(start.nodePosition) > _offsetIn(end.nodePosition))) {
    (start, end) = (end, start);
  }
  final from = ids.indexOf(start.nodeId), to = ids.indexOf(end.nodeId);
  final first = nodes[from], last = nodes[to];
  final s = _offsetIn(start.nodePosition), e = _offsetIn(end.nodePosition);
  if (first is TextNode && last is TextNode) {
    final joined = lineNode(kindOf(last), first.text.copyText(0, s).copyAndAppend(last.text.copyText(e)),
      indent: indentOf(last), id: first.id);
    return (nodes: [...nodes.take(from), joined, ...nodes.skip(to + 1)],
      caret: DocumentPosition(nodeId: first.id, nodePosition: TextNodePosition(offset: s)));
  }
  // A table or a file at an edge goes when the range holds it whole; a line of words keeps the words outside it.
  final kept = <DocumentNode>[
    if (first is TextNode) first.copyTextNodeWith(text: first.text.copyText(0, s)) else if (s == 1 && from != to) first,
    if (from != to)
      if (last is TextNode) last.copyTextNodeWith(text: last.text.copyText(e)) else if (e == 0) last,
  ];
  if (kept.isEmpty) kept.add(lineNode(LineKind.paragraph, AttributedText()));
  final caretNode = kept.first;
  return (nodes: [...nodes.take(from), ...kept, ...nodes.skip(to + 1)], caret: DocumentPosition(nodeId: caretNode.id,
    nodePosition: caretNode is TextNode ? TextNodePosition(offset: caretNode.text.length) : caretNode.endPosition));
}

int _offsetIn(NodePosition position) => switch (position) {
  TextNodePosition(:final offset) => offset,
  UpstreamDownstreamNodePosition(:final affinity) => affinity == TextAffinity.upstream ? 0 : 1,
  _ => 0,
};

/// [nodes] after [pasted], from [pastedNodes], goes over [selection], and where the caret goes after it; null when
/// there is nothing to put. It is one change, so one *Undo* takes it back.
///
/// The line at the cursor keeps its own style where it can: one line with no line style joins it, and the last
/// pasted line with no line style joins the words after the cursor. A paste at the end of a line gives that line's
/// style to the last pasted line, so a paste into a new note's empty Title line does not make its last line a Title.
({List<DocumentNode> nodes, DocumentSelection caret})? pasteInto(List<DocumentNode> nodes, DocumentSelection selection,
    List<DocumentNode> pasted) {
  if (pasted.isEmpty && selection.isCollapsed) return null;
  final (nodes: cleared, :caret) = selection.isCollapsed ? (nodes: nodes, caret: selection.extent)
    : deleteRange(nodes, DocumentRange(start: selection.base, end: selection.extent));
  nodes = cleared;
  DocumentSelection at(DocumentNode node, int offset) => DocumentSelection.collapsed(position: DocumentPosition(
    nodeId: node.id, nodePosition: node is TextNode ? TextNodePosition(offset: offset) : node.endPosition));
  final index = nodes.indexWhere((node) => node.id == caret.nodeId);
  final line = nodes[index];
  if (pasted.isEmpty) return (nodes: nodes, caret: DocumentSelection.collapsed(position: caret));
  if (line is! TextNode) {
    // At a table or a file: the paste goes on lines of its own, before or after it.
    final after = _offsetIn(caret.nodePosition) > 0;
    final placed = after ? [...nodes.take(index + 1), ...pasted, ...nodes.skip(index + 1)]
      : [...nodes.take(index), ...pasted, ...nodes.skip(index)];
    final end = pasted.last;
    return (nodes: placed, caret: at(end, end is TextNode ? end.text.length : 1));
  }
  final offset = _offsetIn(caret.nodePosition);
  final before = line.text.copyText(0, offset), rest = line.text.copyText(offset);
  final cursorStyle = _lineStyleOf(line);
  final wordsBefore = offset > 0;
  final nothingAfter = rest.isEmpty;
  final lastStyle = _lineStyleOf(pasted.last);
  final lastBlock = pasted.last is! TextNode;
  // Whether the last pasted line ends where the cursor's line ends, in place of its own line break. A table takes a
  // line of its own, so it never joins the words after the cursor.
  final joinsLast = lastBlock ? nothingAfter
    : (pasted.length == 1 && _plain(lastStyle)) || nothingAfter || _plain(lastStyle);
  final out = <DocumentNode>[];
  var keepId = true;
  DocumentNode emit(AttributedText text, _Style style) {
    final node = lineNode(style.$1, text, indent: style.$2, id: keepId ? line.id : null);
    keepId = false;
    out.add(node);
    return node;
  }
  var current = before;
  for (var k = 0; k < pasted.length; k++) {
    final piece = pasted[k];
    if (piece is! TextNode) {
      // Nor does a table join the words before the cursor.
      if (k == 0 && wordsBefore) emit(current, cursorStyle);
      current = AttributedText();
      out.add(piece);
      continue;
    }
    current = current.copyAndAppend(piece.text);
    if (k == pasted.length - 1 && joinsLast) break;
    // The words before the cursor stay in their line's style when the first pasted line has none.
    emit(current, k == 0 && wordsBefore && _plain(_lineStyleOf(piece)) ? cursorStyle : _lineStyleOf(piece));
    current = AttributedText();
  }
  if (lastBlock && joinsLast) {
    final next = nodes.elementAtOrNull(index + 1);
    return (nodes: [...nodes.take(index), ...out, ...nodes.skip(index + 1)],
      caret: next == null ? at(out.last, 1) : DocumentSelection.collapsed(
        position: DocumentPosition(nodeId: next.id, nodePosition: next.beginningPosition)));
  }
  final singleJoin = pasted.length == 1 && _plain(lastStyle) && !lastBlock;
  final caretOffset = joinsLast ? current.length : 0;
  final last = emit(current.copyAndAppend(rest), joinsLast && nothingAfter && !singleJoin ? lastStyle : cursorStyle);
  return (nodes: [...nodes.take(index), ...out, ...nodes.skip(index + 1)], caret: at(last, caretOffset));
}

/// One line of a paste: its runs of words, each with its inline marks, and its line style; or a table.
class _Line {
  _Line(this.runs, this.style, {this.table});

  /// The line of a [node] read from Markdown.
  factory _Line.of(DocumentNode node) => switch (node) {
    NoteTableNode(:final table) => _Line(const [], (LineKind.paragraph, 0), table: table),
    TextNode(:final text) => _Line(runsOf(text), _lineStyleOf(node)),
    _ => _Line(const [], (LineKind.paragraph, 0)),
  };

  final List<(String, Set<String>)> runs;
  final _Style style;
  final NoteTable? table;

  String get words => [for (final (text, _) in runs) text].join();

  /// The note's node of this line.
  DocumentNode node() => table != null ? NoteTableNode(id: Editor.createNodeId(), table: table!)
    : lineNode(style.$1, attributedOf(runs), indent: style.$2);
}

/// A line with no words, outside a code block: an empty heading or list item, or spaces read as an indent, is one too.
bool _blank(_Line line) => line.words.trim().isEmpty && line.table == null && line.style.$1 != LineKind.code;

/// Runs of empty lines become one, and empty lines at the start and end go.
List<_Line> _tidy(List<_Line> lines) {
  final kept = <_Line>[];
  for (final line in lines) {
    if (_blank(line) && (kept.isEmpty || _blank(kept.last))) continue;
    kept.add(_blank(line) ? _Line(const [], (LineKind.paragraph, 0)) : line);
  }
  while (kept.isNotEmpty && _blank(kept.last)) {
    kept.removeLast();
  }
  return kept;
}

/// A bullet typed as a sign, such as `• Milk`, as Apple Notes and many apps copy a list as words.
final _bulletSign = RegExp(r'^([ \t]*)[•◦▪·]\s+');

/// A list line's indent and mark.
final _listLine = RegExp(r'^([ \t]*)(\d{1,9}\. |- \[[ x]\] |[*-] )');

/// [plain] as a note's Markdown: one kind of line break, a bullet sign as a `* ` bullet, and each list's indent as the
/// note counts it. A list's first item indented up to 3 spaces, with no list above it, starts at the left; an item
/// indented past the words of the item above is in that item's list, a level in; and a line of words indented to the
/// words of the item above belongs to that item, so the list counts on past it.
String _plainMarkdown(String plain) {
  final lines = [
    for (final line in plain.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      line.replaceFirstMapped(_bulletSign, (match) => '${match[1]!.replaceAll('\t', '  ')}* '),
  ];
  // The items open above the line: where each one's mark starts and its words start in the paste, and where its words
  // start as the note writes it.
  final open = <({int mark, int words, int written})>[];
  final out = <String>[];
  for (final line in lines) {
    final lead = line.length - line.trimLeft().length;
    final width = line.substring(0, lead).replaceAll('\t', '  ').length;
    final rest = line.substring(lead);
    if (rest.isEmpty) {
      open.clear();
      out.add(line);
      continue;
    }
    final item = _listLine.firstMatch(line);
    if (item != null && (open.isNotEmpty || width <= 3)) {
      while (open.isNotEmpty && width < open.last.words) {
        open.removeLast();
      }
      final level = min(open.length, 8);
      final mark = item[2]!;
      out.add('${'  ' * level}$rest');
      open.add((mark: width, words: width + mark.length, written: level * 2 + mark.length));
      continue;
    }
    if (open.isNotEmpty && width >= open.last.words) {
      out.add('${' ' * open.last.written}$rest');
      continue;
    }
    open.clear();
    out.add(line);
  }
  return out.join('\n');
}

/// Elements whose words never paste: the page's code, pictures and controls.
const _skipped = {
  'head', 'style', 'script', 'noscript', 'template', 'title', 'meta', 'link', 'img', 'picture', 'video', 'audio',
  'source', 'svg', 'canvas', 'iframe', 'object', 'embed', 'button', 'select', 'textarea', 'input', 'math',
};

/// Elements that start and end a line.
const _blocks = {
  'address', 'article', 'aside', 'blockquote', 'caption', 'center', 'dd', 'details', 'dialog', 'div', 'dl', 'dt',
  'fieldset', 'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr',
  'li', 'main', 'nav', 'ol', 'p', 'pre', 'section', 'summary', 'table', 'tbody', 'tfoot', 'thead', 'tr', 'ul',
};

const _maxIndent = 8;

const _listKinds = {
  'bullet': LineKind.bullet, 'ordered': LineKind.numbered, 'checked': LineKind.checked, 'unchecked': LineKind.unchecked,
};

/// Where a line is: what the elements around it make it.
class _Block {
  const _Block({this.header, this.list, this.lists = 0, this.level, this.quote = false, this.code = false,
    this.listTag, this.todo = false, this.wordList = false});

  final int? header;
  final String? list;
  /// How many lists hold it, and the indent an element names, such as Google Docs' `aria-level`.
  final int lists;
  final int? level;
  final bool quote;
  final bool code;
  /// The list element it is in, `ul` or `ol`, and whether that list is a checklist, as Notion's `to-do-list`.
  final String? listTag;
  final bool todo;
  /// A Word list paragraph: its words start with the bullet or number Word writes.
  final bool wordList;

  _Block copy({int? header, String? list, int? lists, int? level, bool? quote, bool? code, String? listTag, bool? todo,
      bool? wordList}) =>
    _Block(header: header ?? this.header, list: list ?? this.list, lists: lists ?? this.lists,
      level: level ?? this.level, quote: quote ?? this.quote, code: code ?? this.code,
      listTag: listTag ?? this.listTag, todo: todo ?? this.todo, wordList: wordList ?? this.wordList);

  _Style get style {
    if (code) return (LineKind.code, 0);
    final indent = min(level ?? max(lists - 1, 0), _maxIndent);
    if (list case final list?) return (_listKinds[list]!, indent);
    if (header case final header?) return ([LineKind.header1, LineKind.header2, LineKind.header3][header - 1], 0);
    return (quote ? LineKind.quote : LineKind.paragraph, 0);
  }
}

/// Reads a page's HTML into the note's lines, keeping only the styles a note can show.
class _HtmlReader {
  final _lines = <_Line>[];
  var _runs = <(String, Set<String>)>[];

  List<_Line> read(String source) {
    final document = html_parser.parse(source);
    final root = document.body ?? document.documentElement;
    if (root != null) _children(root, const {}, const _Block());
    _end(const _Block());
    // A code block's lines are one block of the note.
    final lines = <_Line>[];
    for (final line in _lines) {
      if (line.style.$1 == LineKind.code && lines.isNotEmpty && lines.last.style.$1 == LineKind.code) {
        lines.last = _Line([...lines.last.runs, ('\n', const {}), ...line.runs], line.style);
      } else {
        lines.add(line);
      }
    }
    return lines;
  }

  void _children(dom.Node node, Set<String> marks, _Block block) {
    for (final child in node.nodes) {
      _node(child, marks, block);
    }
  }

  void _node(dom.Node node, Set<String> marks, _Block block) {
    if (node is dom.Text) return _text(node.text, marks, block);
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    final style = _styleOf(node);
    if (_skipped.contains(tag) || node.attributes['aria-hidden'] == 'true' || node.attributes.containsKey('hidden') ||
      (style['display'] ?? '').startsWith('none')) {
      return;
    }
    if (tag == 'br') {
      if (block.code) return _breakCode(block);
      // In a list item a line break starts a line under the item, in the same item, so the list counts on past it.
      if (block.list != null) return _breakItem();
      if (_runs.every((run) => run.$1.trim().isEmpty)) _lines.add(_Line(const [], (LineKind.paragraph, 0)));
      return _end(block);
    }
    final inner = _marksOf(tag, style, marks);
    if (tag == 'a') return _link(node, inner, block);
    if (tag == 'table' && !block.code && _table(node)) return;
    if (tag == 'td' || tag == 'th') {
      if (_runs.isNotEmpty) _runs.add((' | ', const {}));
      return _children(node, inner, block);
    }
    if (!_blocks.contains(tag) && !(style['mso-list'] ?? '').contains('level')) return _children(node, inner, block);
    _end(block);
    final inside = _blockOf(node, tag, style, block);
    _children(node, inner, inside);
    _end(inside);
  }

  /// The block an element makes for the lines in it.
  _Block _blockOf(dom.Element element, String tag, Map<String, String> style, _Block around) {
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        return around.copy(header: min(int.parse(tag.substring(1)), 3));
      case 'ul' || 'ol':
        final todo = (element.attributes['class'] ?? '').contains('to-do') || element.attributes['data-checked'] != null;
        return around.copy(lists: around.lists + 1, listTag: tag, todo: todo);
      case 'li':
        final level = int.tryParse(element.attributes['aria-level'] ?? '');
        return around.copy(list: _kindOf(element, around), level: level == null ? null : max(level - 1, 0));
      case 'blockquote':
        return around.copy(quote: true);
      case 'pre':
        return around.copy(code: true);
    }
    // A Word list paragraph, `mso-list: l0 level2 lfo1`: its level is the indent.
    final word = RegExp(r'level(\d+)').firstMatch(style['mso-list'] ?? '');
    if (word != null) return around.copy(list: 'bullet', level: max(int.parse(word[1]!) - 1, 0), wordList: true);
    return around;
  }

  /// A list item's kind: a checklist item, ticked or not, or a bullet or numbered item.
  String _kindOf(dom.Element item, _Block around) {
    final parent = item.parent;
    final checked = item.attributes['data-checked'] ?? item.attributes['aria-checked'] ?? parent?.attributes['data-checked'];
    if (checked != null) return checked == 'true' ? 'checked' : 'unchecked';
    // Quill's own HTML names the kind: `<li data-list="checked">`.
    final named = item.attributes['data-list'];
    if (const {'bullet', 'ordered', 'checked', 'unchecked'}.contains(named)) return named!;
    for (final element in _ownElements(item)) {
      final kind = element.localName == 'input' && element.attributes['type'] == 'checkbox'
        ? (element.attributes.containsKey('checked') ? 'checked' : 'unchecked')
        : _todoClass(element.attributes['class'] ?? '');
      if (kind != null) return kind;
    }
    if (around.todo) return 'unchecked';
    return around.listTag == 'ol' ? 'ordered' : 'bullet';
  }

  /// Notion marks a ticked item `checkbox-on` and an open one `checkbox-off`.
  static String? _todoClass(String names) =>
    names.contains('checkbox-on') || names.contains('to-do-children-checked') ? 'checked'
    : names.contains('checkbox-off') || names.contains('to-do-children-unchecked') ? 'unchecked'
    : null;

  /// The elements in [item], not counting the lists in it, whose items have their own.
  static Iterable<dom.Element> _ownElements(dom.Element item) sync* {
    for (final child in item.children) {
      if (child.localName == 'ul' || child.localName == 'ol') continue;
      yield child;
      yield* _ownElements(child);
    }
  }

  void _text(String text, Set<String> marks, _Block block) {
    if (block.code) {
      final parts = text.split('\n');
      for (var at = 0; at < parts.length; at++) {
        if (parts[at].isNotEmpty) _runs.add((parts[at], const {}));
        if (at < parts.length - 1) _breakCode(block);
      }
      return;
    }
    var words = text.replaceAll(RegExp(r'[ \t\n\r\f]+'), ' ');
    if (words.startsWith(' ') && (_runs.isEmpty || _runs.last.$1.endsWith(' ') || _runs.last.$1.endsWith('\n'))) {
      words = words.substring(1);
    }
    if (words.isEmpty) return;
    _runs.add((words.replaceAll(' ', ' '), marks));
  }

  /// A line break inside a list item: the spaces before it go, and the item's words go on under it.
  void _breakItem() {
    while (_runs.isNotEmpty && _runs.last.$1.trimRight().isEmpty && !_runs.last.$1.endsWith('\n')) {
      _runs.removeLast();
    }
    if (_runs.isNotEmpty) _runs.last = (_runs.last.$1.replaceFirst(RegExp(r' +$'), ''), _runs.last.$2);
    _runs.add(('\n', const {}));
  }

  void _breakCode(_Block block) {
    _lines.add(_Line(_runs, block.style));
    _runs = [];
  }

  /// A link whose words are not its address keeps its words, linked to the address, as `[words](address)`: a web
  /// address or a mail address. Words that are the address itself stay as words, which the page shows as a link.
  void _link(dom.Element element, Set<String> marks, _Block block) {
    final href = (element.attributes['href'] ?? '').trim();
    final mail = href.toLowerCase().startsWith('mailto:');
    final address = mail || RegExp(r'^https?://', caseSensitive: false).hasMatch(href) ? href : null;
    final words = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final linked = address == null || address.contains(RegExp(r'\s')) || block.code || words.isEmpty ||
        _sameAddress(words, mail ? address.substring(7) : address)
      ? marks : {...marks, 'link:$address'};
    _children(element, linked, block);
  }

  /// A table of rows and cells pastes as a note's table, with each cell's words. A table that holds another, as an
  /// email lays out its page, or only one cell, is read as the words in it. True when the table was kept.
  bool _table(dom.Element table) {
    if (table.querySelector('table') != null) return false;
    final rows = [
      for (final row in table.querySelectorAll('tr'))
        [for (final cell in row.children) if (cell.localName == 'td' || cell.localName == 'th')
          cell.text.replaceAll(RegExp(r'\s+'), ' ').trim()],
    ]..removeWhere((row) => row.isEmpty);
    final columns = rows.fold(0, (widest, row) => max(widest, row.length));
    if (rows.isEmpty || (rows.length == 1 && columns == 1)) return false;
    _end(const _Block());
    final full = [for (final row in rows) [...row, for (var pad = row.length; pad < columns; pad++) '']];
    _lines.add(_Line(const [], (LineKind.paragraph, 0), table: NoteTable(full)));
    return true;
  }

  static bool _sameAddress(String words, String address) {
    String bare(String text) => text.toLowerCase().replaceFirst(RegExp(r'^(https?://)?(www\.)?'), '')
      .replaceFirst(RegExp(r'/$'), '');
    return bare(words) == bare(address);
  }

  /// Ends the line being read, in [block]'s style. A line with no words is not kept: an empty `<br>` line is.
  void _end(_Block block) {
    final runs = _runs;
    _runs = [];
    if (block.code) {
      if (runs.isNotEmpty) _lines.add(_Line(runs, block.style));
      return;
    }
    final trimmed = _trim(runs);
    if (trimmed.isEmpty) return;
    var style = block.style;
    var kept = trimmed;
    final words = [for (final (text, _) in trimmed) text].join();
    if (block.wordList) {
      // Word writes the bullet or number as words, `·` then spaces, or `1.` then spaces.
      final marker = RegExp(r'^(\S{1,5})\s+').firstMatch(words);
      if (marker != null) {
        if (RegExp(r'^[0-9a-zA-Z]{1,4}[.)]$').hasMatch(marker[1]!)) style = (LineKind.numbered, style.$2);
        kept = _drop(trimmed, marker.end);
      }
    } else if (_plain(style)) {
      final sign = _bulletSign.firstMatch(words);
      if (sign != null) {
        style = (LineKind.bullet, 0);
        kept = _drop(trimmed, sign.end);
      }
    }
    if (kept.isNotEmpty) _lines.add(_Line(kept, style));
  }

  /// [runs] less their first [count] letters.
  static List<(String, Set<String>)> _drop(List<(String, Set<String>)> runs, int count) {
    final kept = <(String, Set<String>)>[];
    var left = count;
    for (final (text, marks) in runs) {
      if (left < text.length) kept.add((text.substring(left), marks));
      left = max(left - text.length, 0);
    }
    return kept;
  }

  /// [runs] with no spaces at the line's start and end; empty when the line has no words.
  static List<(String, Set<String>)> _trim(List<(String, Set<String>)> runs) {
    final kept = [for (final run in runs) if (run.$1.isNotEmpty) run];
    while (kept.isNotEmpty && kept.first.$1.trimLeft().isEmpty) {
      kept.removeAt(0);
    }
    while (kept.isNotEmpty && kept.last.$1.trimRight().isEmpty) {
      kept.removeLast();
    }
    if (kept.isEmpty) return kept;
    kept[0] = (kept.first.$1.trimLeft(), kept.first.$2);
    kept[kept.length - 1] = (kept.last.$1.trimRight(), kept.last.$2);
    return kept;
  }

  /// An element's inline style, each property by name.
  static Map<String, String> _styleOf(dom.Element element) => {
    for (final rule in (element.attributes['style'] ?? '').split(';'))
      if (rule.indexOf(':') case final colon when colon > 0)
        rule.substring(0, colon).trim().toLowerCase(): rule.substring(colon + 1).trim().toLowerCase(),
  };

  /// The inline styles inside an element: its tag's, then its own style's. Google Docs wraps a whole copy in
  /// `<b style="font-weight:normal">`, so a weight under 600 ends bold.
  static Set<String> _marksOf(String tag, Map<String, String> style, Set<String> around) {
    final marks = {...around};
    switch (tag) {
      case 'b' || 'strong':
        marks.add('bold');
      case 'i' || 'em' || 'cite' || 'dfn':
        marks.add('italic');
      case 'u' || 'ins':
        marks.add('underline');
      case 's' || 'strike' || 'del':
        marks.add('strike');
    }
    final weight = style['font-weight'];
    if (weight != null) {
      final number = int.tryParse(weight);
      if (weight == 'bold' || weight == 'bolder' || (number != null && number >= 600)) {
        marks.add('bold');
      } else if (weight == 'normal' || weight == 'lighter' || (number != null && number < 600)) {
        marks.remove('bold');
      }
    }
    final italic = style['font-style'];
    if (italic == 'italic' || italic == 'oblique') marks.add('italic');
    if (italic == 'normal') marks.remove('italic');
    final decoration = '${style['text-decoration'] ?? ''} ${style['text-decoration-line'] ?? ''}';
    if (decoration.contains('underline')) marks.add('underline');
    if (decoration.contains('line-through')) marks.add('strike');
    return marks;
  }
}

/// The part of [nodes] in [range], as a copy keeps it: the first and last lines cut at the range's ends, and each
/// node with a new id, so a paste of it is lines and tables of their own.
List<DocumentNode> copiedNodes(List<DocumentNode> nodes, DocumentRange range) {
  final ids = [for (final node in nodes) node.id];
  var (start, end) = (range.start, range.end);
  if (ids.indexOf(start.nodeId) > ids.indexOf(end.nodeId) || (start.nodeId == end.nodeId &&
      _offsetIn(start.nodePosition) > _offsetIn(end.nodePosition))) {
    (start, end) = (end, start);
  }
  final from = ids.indexOf(start.nodeId), to = ids.indexOf(end.nodeId);
  if (from < 0 || to < 0) return const [];
  final copied = <DocumentNode>[];
  for (var at = from; at <= to; at++) {
    final node = nodes[at];
    if (node is TextNode) {
      final s = at == from ? _offsetIn(start.nodePosition) : 0;
      final e = at == to ? _offsetIn(end.nodePosition) : node.text.length;
      copied.add(lineNode(kindOf(node), node.text.copyText(s, e), indent: indentOf(node)));
    } else if ((at != from || _offsetIn(start.nodePosition) == 0) && (at != to || _offsetIn(end.nodePosition) == 1)) {
      copied.add(switch (node) {
        NoteTableNode() => withNewTableId(node),
        AttachmentNode(:final file) => AttachmentNode(id: Editor.createNodeId(), file: file),
        _ => node,
      });
    }
  }
  return copied;
}

/// The plain words of [nodes], as a copy puts them on the clipboard: each line on its own, a table's cells split by
/// tabs, and no file.
String copiedText(List<DocumentNode> nodes) => [
  for (final node in nodes)
    if (node is TextNode) node.text.toPlainText(includePlaceholders: false)
    else if (node is NoteTableNode) node.table.text,
].join('\n');
