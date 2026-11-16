import 'dart:math';

import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart' show Document, Line;
import 'package:flutter_quill/quill_delta.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'markdown.dart';

// Every paste into a note goes through here: the iPhone's own Paste, the editor's own menu and keys, and the browser.
// A paste keeps only the styles a note can store as Markdown, so the page shows what the note keeps.

/// What a paste puts in a note: [html] when it holds words, else [plain] read as Markdown, as a note's own words are.
/// Only the note's styles stay: headings 1 to 3, lists with their indent, quotes, code blocks, tables, links on words,
/// and bold, italic, underlined and struck words.
/// Runs of empty lines become one, and empty lines at the start and end go. The result has gone to Markdown and back,
/// so it is what the note stores; it ends with a line break, or is empty when the paste has no words.
Delta pastedDelta({String? html, required String plain}) {
  final fromHtml = html == null || html.trim().isEmpty ? null : _HtmlReader().read(html);
  final lines = _tidy(fromHtml != null && fromHtml.any((line) => line.words.trim().isNotEmpty)
    ? fromHtml
    : _linesOf(markdownToDelta(_plainMarkdown(plain))));
  if (lines.isEmpty) return Delta();
  return markdownToDelta(deltaToMarkdown(_deltaOf(lines)));
}

/// The change that puts [pasted], from [pastedDelta], over [selection] in [document], and where the caret goes after
/// it; null when there is nothing to put. It is one change, so one *Undo* takes it back.
///
/// The line at the cursor keeps its own style where it can: one line with no line style joins it, and the last
/// pasted line with no line style joins the words after the cursor. A paste at the end of a line gives that line's
/// style to the last pasted line, so a paste into a new note's empty Title line does not make its last line a Title.
({Delta change, int caret})? pasteChange(Document document, TextSelection selection, Delta pasted) {
  final lines = _linesOf(pasted);
  if (lines.isEmpty) return null;
  final start = selection.start, end = selection.end;
  final first = document.queryChild(start), last = document.queryChild(end);
  final line = last.node is Line ? last.node! as Line : null;
  final cursorStyle = <String, dynamic>{
    for (final attribute in line?.style.attributes.values ?? const <Never>[]) attribute.key: attribute.value,
  };
  final wordsBefore = first.offset > 0;
  final nothingAfter = line != null && last.offset >= line.length - 1;
  final lastStyle = lines.last.style;
  // Whether the last pasted line ends where the cursor's line ends, in place of its own line break. A table takes a
  // line of its own, so it never joins the words after the cursor.
  final joinsLast = lines.last.embed ? nothingAfter
    : (lines.length == 1 && lastStyle.isEmpty) || nothingAfter || lastStyle.isEmpty;
  final change = Delta();
  if (start > 0) change.retain(start);
  if (end > start) change.delete(end - start);
  var length = 0;
  for (var at = 0; at < lines.length; at++) {
    // Nor does a table join the words before the cursor.
    if (at == 0 && wordsBefore && lines[at].embed) {
      change.insert('\n', cursorStyle.isEmpty ? null : cursorStyle);
      length++;
    }
    for (final (data, marks) in lines[at].runs) {
      change.insert(data, marks);
      length += data is String ? data.length : 1;
    }
    if (at == lines.length - 1 && joinsLast) break;
    // The words before the cursor stay in their line's style when the first pasted line has none.
    final style = at == 0 && wordsBefore && lines[at].style.isEmpty && !lines[at].embed ? cursorStyle : lines[at].style;
    change.insert('\n', style.isEmpty ? null : style);
    length++;
  }
  final singleJoin = lines.length == 1 && lastStyle.isEmpty && !lines.last.embed;
  if (joinsLast && nothingAfter && !singleJoin) {
    final restyle = {for (final key in cursorStyle.keys) if (!lastStyle.containsKey(key)) key: null, ...lastStyle};
    if (restyle.entries.any((entry) => cursorStyle[entry.key] != entry.value)) change.retain(1, restyle);
  }
  if (length == 0 && end == start) return null;
  return (change: change, caret: start + length);
}

/// One line of a paste: its runs of words, each with its inline styles, and its line style. A table's line holds its
/// embed alone, as a run whose data is the embed's map.
class _Line {
  _Line(this.runs, this.style);

  final List<(Object, Map<String, dynamic>?)> runs;
  final Map<String, dynamic> style;

  String get words => [for (final (text, _) in runs) if (text is String) text].join();

  bool get embed => runs.any((run) => run.$1 is! String);
}

/// The lines of [delta]; a last line with no line break counts too.
List<_Line> _linesOf(Delta delta) {
  final lines = <_Line>[];
  var runs = <(Object, Map<String, dynamic>?)>[];
  for (final op in delta.toList()) {
    final data = op.data;
    if (data is Map) {
      runs.add((data, null));
      continue;
    }
    if (data is! String) continue;
    final parts = data.split('\n');
    for (var at = 0; at < parts.length; at++) {
      if (parts[at].isNotEmpty) runs.add((parts[at], op.attributes));
      if (at == parts.length - 1) break;
      lines.add(_Line(runs, {...?op.attributes}));
      runs = [];
    }
  }
  if (runs.isNotEmpty) lines.add(_Line(runs, const {}));
  return lines;
}

Delta _deltaOf(List<_Line> lines) {
  final delta = Delta();
  for (final line in lines) {
    for (final (text, marks) in line.runs) {
      delta.insert(text, marks == null || marks.isEmpty ? null : marks);
    }
    delta.insert('\n', line.style.isEmpty ? null : line.style);
  }
  return delta;
}

/// A line with no words, outside a code block: an empty heading or list item, or spaces read as an indent, is one too.
bool _blank(_Line line) => line.words.trim().isEmpty && !line.embed && !line.style.containsKey('code-block');

/// Runs of empty lines become one, and empty lines at the start and end go.
List<_Line> _tidy(List<_Line> lines) {
  final kept = <_Line>[];
  for (final line in lines) {
    if (_blank(line) && (kept.isEmpty || _blank(kept.last))) continue;
    kept.add(_blank(line) ? _Line(const [], const {}) : line);
  }
  while (kept.isNotEmpty && _blank(kept.last)) {
    kept.removeLast();
  }
  return kept;
}

/// A bullet typed as a sign, such as `• Milk`, as Apple Notes and many apps copy a list as words.
final _bulletSign = RegExp(r'^([ \t]*)[•◦▪·]\s+');

/// [plain] as a note's Markdown: one kind of line break, and a bullet sign as a `* ` bullet.
String _plainMarkdown(String plain) => [
  for (final line in plain.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
    line.replaceFirstMapped(_bulletSign, (match) => '${match[1]!.replaceAll('\t', '  ')}* '),
].join('\n');

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

  Map<String, dynamic> get style {
    if (code) return {'code-block': true};
    final indent = min(level ?? max(lists - 1, 0), _maxIndent);
    return {
      if (list != null) 'list': list,
      if (list != null && indent > 0) 'indent': indent,
      if (header != null && list == null) 'header': header,
      if (quote && list == null && header == null) 'blockquote': true,
    };
  }
}

/// Reads a page's HTML into the note's lines, keeping only the styles a note can show.
class _HtmlReader {
  final _lines = <_Line>[];
  var _runs = <(String, Map<String, dynamic>?)>[];


  List<_Line> read(String source) {
    final document = html_parser.parse(source);
    final root = document.body ?? document.documentElement;
    if (root != null) _children(root, const {}, const _Block());
    _end(const _Block());
    return _lines;
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
      if (_runs.every((run) => run.$1.trim().isEmpty)) _lines.add(_Line(const [], const {}));
      return _end(block);
    }
    final inner = _marksOf(tag, style, marks);
    if (tag == 'a') return _link(node, inner, block);
    if (tag == 'table' && !block.code && _table(node)) return;
    if (tag == 'td' || tag == 'th') {
      if (_runs.isNotEmpty) _runs.add((' | ', null));
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
        if (parts[at].isNotEmpty) _runs.add((parts[at], null));
        if (at < parts.length - 1) _breakCode(block);
      }
      return;
    }
    var words = text.replaceAll(RegExp(r'[ \t\n\r\f]+'), ' ');
    if (words.startsWith(' ') && (_runs.isEmpty || _runs.last.$1.endsWith(' '))) words = words.substring(1);
    if (words.isEmpty) return;
    _runs.add((words.replaceAll(' ', ' '), _attributesOf(marks)));
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
    _lines.add(_Line([({tableEmbed: NoteTable(full).toJson()}, null)], const {}));
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
        if (RegExp(r'^[0-9a-zA-Z]{1,4}[.)]$').hasMatch(marker[1]!)) style = {...style, 'list': 'ordered'};
        kept = _drop(trimmed, marker.end);
      }
    } else if (style.isEmpty) {
      final sign = _bulletSign.firstMatch(words);
      if (sign != null) {
        style = {'list': 'bullet'};
        kept = _drop(trimmed, sign.end);
      }
    }
    if (kept.isNotEmpty) _lines.add(_Line(kept, style));
  }

  /// [runs] less their first [count] letters.
  static List<(String, Map<String, dynamic>?)> _drop(List<(String, Map<String, dynamic>?)> runs, int count) {
    final kept = <(String, Map<String, dynamic>?)>[];
    var left = count;
    for (final (text, marks) in runs) {
      if (left < text.length) kept.add((text.substring(left), marks));
      left = max(left - text.length, 0);
    }
    return kept;
  }

  /// [runs] with no spaces at the line's start and end; empty when the line has no words.
  static List<(String, Map<String, dynamic>?)> _trim(List<(String, Map<String, dynamic>?)> runs) {
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

  static Map<String, dynamic>? _attributesOf(Set<String> marks) => attributesOfMarks(marks);

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
