import 'dart:convert';
import 'dart:math';

import 'package:super_editor/super_editor.dart';

import 'attachments.dart';
import 'table.dart';

// A note keeps its styles in its words as Markdown, so the server, Claude and webhooks read plain text. The editor's
// document goes to it and back byte for byte; underline, which Markdown lacks, is `<u>…</u>`, a highlight is
// `<mark class="pink">…</mark>`, a link on words is `[words](address)`, a table is a Markdown table, and a note's file
// is a line `![name](attachment:<id>)` at its place.

/// The metadata key of a `- ` list item, drawn as a dash, where `* ` is a bullet.
const dashedList = 'dashed';

const _fence = '```';
const _maxIndent = 8;
final _ordered = RegExp(r'^(\d{1,9})\. ');

/// The kinds of line a mark starts.
enum LineKind { paragraph, header1, header2, header3, quote, code, bullet, dashed, numbered, unchecked, checked }

/// Line marks, longest first, and the kind of line each stands for.
const _lineMarks = <(String, LineKind)>[
  ('- [ ] ', LineKind.unchecked), ('- [x] ', LineKind.checked), ('* ', LineKind.bullet), ('- ', LineKind.dashed),
  ('> ', LineKind.quote), ('### ', LineKind.header3), ('## ', LineKind.header2), ('# ', LineKind.header1),
];

/// Inline marks other than `*`, in the order they open when several start together; italic last, as `_` is the
/// loosest. Stars pair up first, by [_pairStars].
const _inlineMarks = <(String, String, String)>[
  ('strike', '~~', '~~'), ('underline', '<u>', '</u>'), ('italic', '_', '_'),
];
const _writeOrder = ['bold', 'italic', 'strike', 'underline'];

/// The highlight colours, as Apple Notes orders them.
const highlightColours = ['purple', 'pink', 'orange', 'green', 'blue'];

/// A highlight on words, in one of the [highlightColours].
class HighlightAttribution implements Attribution {
  const HighlightAttribution(this.colour);

  final String colour;

  @override
  String get id => 'highlight';

  @override
  bool canMergeWith(Attribution other) => this == other;

  @override
  bool operator ==(Object other) => other is HighlightAttribution && other.colour == colour;

  @override
  int get hashCode => colour.hashCode;

  @override
  String toString() => '[HighlightAttribution]: $colour';
}

/// A highlight's inline mark, `mark:pink`, and a link's, `link:https://…`: a run's marks are words, so a mark with a
/// value carries it after the colon.
const _markKey = 'mark:', _linkKey = 'link:';

/// The highlight marks, one for each colour.
final _highlightMarks = <(String, String, String)>[
  for (final colour in highlightColours) ('$_markKey$colour', '<mark class="$colour">', '</mark>'),
];

const _attributionOf = {
  'bold': boldAttribution, 'italic': italicsAttribution, 'strike': strikethroughAttribution,
  'underline': underlineAttribution,
};

/// The attribution of an inline mark.
Attribution attributionOfMark(String mark) => mark.startsWith(_linkKey) ? LinkAttribution(mark.substring(_linkKey.length))
  : mark.startsWith(_markKey) ? HighlightAttribution(mark.substring(_markKey.length)) : _attributionOf[mark]!;

/// The inline marks of [attributions]: bold, italic, strike and underline, a highlight in one of the
/// [highlightColours], and a link. Any other style keeps only its words.
Set<String> marksOf(Set<Attribution> attributions) => {
  for (final attribution in attributions)
    if (attribution is LinkAttribution && attribution.plainTextUri.isNotEmpty) '$_linkKey${attribution.plainTextUri}',
  for (final attribution in attributions)
    if (attribution is HighlightAttribution && highlightColours.contains(attribution.colour)) '$_markKey${attribution.colour}',
  for (final key in _writeOrder) if (attributions.contains(_attributionOf[key])) key,
};

/// Words with the inline marks of each run.
AttributedText attributedOf(List<(String, Set<String>)> runs) {
  final text = AttributedText(runs.map((run) => run.$1).join());
  var at = 0;
  for (final (words, marks) in runs) {
    if (words.isNotEmpty) {
      for (final mark in marks) {
        text.addAttribution(attributionOfMark(mark), SpanRange(at, at + words.length - 1));
      }
    }
    at += words.length;
  }
  return text;
}

/// [text] in runs, each with its inline marks.
List<(String, Set<String>)> runsOf(AttributedText text) {
  final words = text.toPlainText(includePlaceholders: false);
  final runs = <(String, Set<String>)>[];
  var start = 0;
  Set<String>? marks;
  for (var at = 0; at <= words.length; at++) {
    final here = at < words.length ? marksOf(text.getAllAttributionsAt(at)) : null;
    if (marks != null && (here == null || !_sameSet(here, marks))) {
      runs.add((words.substring(start, at), marks));
      start = at;
    }
    if (marks == null || here == null || !_sameSet(here, marks)) marks = here;
  }
  return runs;
}

bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

/// Where a mark opens among others that open together: a link outside all, then a highlight, then the rest.
int _rankOf(String key) => key.startsWith(_linkKey) ? 0 : key.startsWith(_markKey) ? 1 : 2 + _writeOrder.indexOf(key);

/// The kind of a text [node].
LineKind kindOf(DocumentNode node) => switch (node) {
  TaskNode(:final isComplete) => isComplete ? LineKind.checked : LineKind.unchecked,
  ListItemNode(:final type) => type == ListItemType.ordered ? LineKind.numbered
    : node.getMetadataValue(dashedList) == true ? LineKind.dashed : LineKind.bullet,
  ParagraphNode() => switch (node.getMetadataValue(NodeMetadata.blockType)) {
    header1Attribution => LineKind.header1,
    header2Attribution => LineKind.header2,
    header3Attribution => LineKind.header3,
    blockquoteAttribution => LineKind.quote,
    codeAttribution => LineKind.code,
    _ => LineKind.paragraph,
  },
  _ => LineKind.paragraph,
};

/// The indent level of a text [node].
int indentOf(DocumentNode node) => switch (node) {
  TaskNode(:final indent) || ListItemNode(:final indent) || ParagraphNode(:final indent) => indent,
  _ => 0,
};

/// A text node of [kind] with [text] at [indent], keeping [id] when given.
TextNode lineNode(LineKind kind, AttributedText text, {int indent = 0, String? id}) {
  id ??= Editor.createNodeId();
  indent = indent.clamp(0, _maxIndent);
  return switch (kind) {
    LineKind.unchecked || LineKind.checked =>
      TaskNode(id: id, text: text, isComplete: kind == LineKind.checked, indent: indent),
    LineKind.numbered => ListItemNode.ordered(id: id, text: text, indent: indent),
    LineKind.bullet => ListItemNode.unordered(id: id, text: text, indent: indent),
    LineKind.dashed => ListItemNode.unordered(id: id, text: text, indent: indent, metadata: {dashedList: true}),
    _ => ParagraphNode(id: id, text: text, indent: indent, metadata: {
      NodeMetadata.blockType: switch (kind) {
        LineKind.header1 => header1Attribution,
        LineKind.header2 => header2Attribution,
        LineKind.header3 => header3Attribution,
        LineKind.quote => blockquoteAttribution,
        LineKind.code => codeAttribution,
        _ => paragraphAttribution,
      },
    }),
  };
}

/// Whether [kind] is a list item: its later lines are indented to its words.
bool isItem(LineKind kind) => const {LineKind.bullet, LineKind.dashed, LineKind.numbered, LineKind.unchecked,
  LineKind.checked}.contains(kind);

/// The editor's document of [markdown]. With [title], a first line with no line style shows as a Title, as an old
/// note's first line did in the list; its text gains `# ` only once the person changes the note. A file's line is a
/// block only when [files] holds its id, or [files] is null; else it stays words.
MutableDocument markdownToDocument(String markdown, {bool title = false, Set<String>? files}) =>
  MutableDocument(nodes: markdownToNodes(markdown, title: title, files: files));

/// The nodes of [markdown], as [markdownToDocument] reads them.
List<DocumentNode> markdownToNodes(String markdown, {bool title = false, Set<String>? files}) {
  final nodes = <DocumentNode>[];
  final lines = markdown.split('\n');
  var counts = <int, int>{};
  // The list item that later lines indented to its words join, and where its words start.
  TextNode? item;
  var itemStart = 0;
  for (var at = 0; at < lines.length; at++) {
    final end = lines[at] == _fence ? lines.indexOf(_fence, at + 1) : -1;
    if (end > at + 1) {
      nodes.add(lineNode(LineKind.code, AttributedText(lines.sublist(at + 1, end).join('\n'))));
      counts.clear();
      item = null;
      at = end;
      continue;
    }
    if (NoteTable.readAt(lines, at) case (final table, final next)) {
      nodes.add(NoteTableNode(id: Editor.createNodeId(), table: table));
      counts.clear();
      item = null;
      at = next - 1;
      continue;
    }
    if (NoteAttachment.read(lines[at]) case final file? when files == null || files.contains(file.id)) {
      nodes.add(AttachmentNode(id: Editor.createNodeId(), file: file));
      counts.clear();
      item = null;
      continue;
    }
    final line = lines[at];
    if (item != null && line.trim().isEmpty) {
      // Blank lines inside a list item stay in it while a later line still continues the item, as Markdown reads them.
      var later = at + 1;
      while (later < lines.length && lines[later].trim().isEmpty) {
        later++;
      }
      if (later < lines.length && _continues(lines, later, itemStart, counts)) {
        final blanks = AttributedText('\n' * (later - at));
        nodes.last = item = item.copyTextNodeWith(text: item.text.copyAndAppend(blanks)
          .copyAndAppend(AttributedText('\n')).copyAndAppend(_attributedLine(lines[later].substring(itemStart))));
        at = later;
        continue;
      }
    }
    final next = {...counts};
    final (kind, level, words) = _lineOf(line, next);
    final spaces = line.length - line.trimLeft().length;
    if (item != null && kind == LineKind.paragraph && line.trim().isNotEmpty && spaces >= itemStart) {
      // A line indented to the words of the list item above belongs to that item, so `Why:` under an item stays in it.
      final text = item.text.copyAndAppend(AttributedText('\n'))
        .copyAndAppend(_attributedLine(line.substring(itemStart)));
      nodes.last = item = item.copyTextNodeWith(text: text);
      continue;
    }
    counts = next;
    final heading = at == 0 && title && kind == LineKind.paragraph && level == 0 && words.trim().isNotEmpty;
    final node = lineNode(heading ? LineKind.header1 : kind, _attributedLine(words), indent: level);
    nodes.add(node);
    item = isItem(kind) ? node : null;
    itemStart = level * 2 + _markLength(line.substring(level * 2), kind);
    if (heading) nodes.last = node.copyWithAddedMetadata({'title': true});
  }
  return nodes;
}

/// Whether line [at] of [lines] is words indented to the words of a list item that starts its words at [itemStart],
/// so it belongs to that item: not a file's line, a table, a code block or a new item.
bool _continues(List<String> lines, int at, int itemStart, Map<int, int> counts) {
  final line = lines[at];
  return line.trim().isNotEmpty && line.length - line.trimLeft().length >= itemStart && line != _fence &&
    NoteAttachment.read(line) == null && NoteTable.readAt(lines, at) == null &&
    _lineOf(line, {...counts}).$1 == LineKind.paragraph;
}

AttributedText _attributedLine(String words) => attributedOf(_inline(words, 0, words.length, const {}, _pairStars(words)));

int _markLength(String rest, LineKind kind) => kind == LineKind.numbered ? _ordered.firstMatch(rest)!.end
  : [for (final (mark, of) in _lineMarks) if (of == kind) mark.length].firstOrNull ?? 0;

/// A line's kind, its indent level and its words after the marks. A `N. ` line is numbered only when N is the next
/// number of its list, so `2020. was a year` stays words; [counts] holds each indent level's last number, as
/// [documentToMarkdown] counts.
(LineKind, int, String) _lineOf(String line, Map<int, int> counts) {
  var spaces = 0;
  while (spaces < line.length && line[spaces] == ' ') {
    spaces++;
  }
  final level = min(spaces ~/ 2, _maxIndent);
  final rest = line.substring(level * 2);
  final number = _ordered.firstMatch(rest);
  if (number != null && int.parse(number[1]!) == (counts[level] ?? 0) + 1) {
    _count(counts, level, ordered: true);
    return (LineKind.numbered, level, rest.substring(number.end));
  }
  _count(counts, level, ordered: false);
  for (final (mark, kind) in _lineMarks) {
    if (rest.startsWith(mark)) return (kind, level, rest.substring(mark.length));
  }
  return (LineKind.paragraph, level, rest);
}

/// Counts a numbered line at [level], or ends the lists at [level] and deeper; returns the line's number.
int _count(Map<int, int> counts, int level, {required bool ordered}) {
  counts.removeWhere((at, _) => at > level || (!ordered && at == level));
  if (!ordered) return 0;
  return counts[level] = (counts[level] ?? 0) + 1;
}

/// The number each numbered item in [nodes] shows, by its id, as the Markdown counts them.
Map<String, int> itemNumbers(Iterable<DocumentNode> nodes) {
  final numbers = <String, int>{};
  final counts = <int, int>{};
  for (final node in nodes) {
    if (node is! TextNode || kindOf(node) == LineKind.code) {
      counts.clear();
      continue;
    }
    final kind = kindOf(node);
    final number = _count(counts, indentOf(node), ordered: kind == LineKind.numbered);
    if (kind == LineKind.numbered) numbers[node.id] = number;
  }
  return numbers;
}

bool _space(String char) => char.trim().isEmpty;
bool _word(String char) => RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(char);

/// Where a `*` mark pairs: bold or italic, its length, and where its closing stars start.
typedef _Stars = ({String key, int length, int close});

/// Pairs the runs of `*` in [line], keyed by where each opening mark starts: `**` is bold and `*` italic. Marks nest,
/// so a run closes the marks open on top, then opens new ones, bold before italic, as [documentToMarkdown] writes
/// them: `**foo***bar*` is bold *foo* then italic *bar*, and `x*a**b***` closes bold, then italic. A `*` italic counts
/// only when it touches a letter, so `5 * 3` and an old `*word*` stay as typed.
Map<int, _Stars> _pairStars(String line) {
  final pairs = <int, _Stars>{};
  // The marks open now, innermost last: each its key and where its stars start.
  final open = <(String, int)>[];
  for (var at = 0; at < line.length;) {
    if (line[at] != '*') {
      at++;
      continue;
    }
    var end = at;
    while (end < line.length && line[end] == '*') {
      end++;
    }
    final plan = _plan([for (final (key, _) in open) key], end - at,
      opens: end < line.length && !_space(line[end]), closes: at > 0 && !_space(line[at - 1]));
    if (plan != null) {
      final (drop, closing, opening) = plan;
      open.removeRange(open.length - drop, open.length);
      var star = at;
      for (var count = 0; count < closing; count++) {
        final (key, start) = open.removeLast();
        pairs[start] = (key: key, length: _starsOf[key]!, close: star);
        star += _starsOf[key]!;
      }
      for (final key in opening) {
        open.add((key, star));
        star += _starsOf[key]!;
      }
    }
    at = end;
  }
  pairs.removeWhere((start, pair) => pair.key == 'italic' && !_wordAt(line, start - 1) && !_wordAt(line, pair.close + 1));
  return pairs;
}

const _starsOf = {'bold': 2, 'italic': 1};

/// How a run of [length] stars acts on the marks [open], innermost last: how many marks on top it leaves as words, how
/// many under those it closes, and which it opens. A run opens a mark only when [opens], with words after it, and
/// closes one only when [closes]. It never opens again the last mark it closes, as the writer would have kept that
/// mark open. Null when nothing fits, so the stars are words.
(int, int, List<String>)? _plan(List<String> open, int length, {required bool opens, required bool closes}) {
  for (var drop = 0; drop <= open.length; drop++) {
    final kept = open.sublist(0, open.length - drop);
    for (var closing = drop == 0 ? 0 : 1; closing <= kept.length; closing++) {
      if (closing > 0 && !closes) break;
      final closed = kept.sublist(kept.length - closing);
      final used = closed.fold(0, (sum, key) => sum + _starsOf[key]!);
      if (used > length) break;
      for (final opening in const [<String>[], ['bold'], ['italic'], ['bold', 'italic']]) {
        if (opening.isNotEmpty && !opens) continue;
        if (opening.any((key) => kept.sublist(0, kept.length - closing).contains(key) || closed.firstOrNull == key)) continue;
        if (used + opening.fold(0, (sum, key) => sum + _starsOf[key]!) == length) return (drop, closing, opening);
      }
    }
  }
  return null;
}

bool _wordAt(String text, int at) => at >= 0 && at < text.length && _word(text[at]);

/// [line] from [from] to [to] in runs, each with the inline marks around it. A mark counts only with a partner and
/// words between, and `_` only at a word's edge, so `snake_case` and a lone `**` stay as typed.
List<(String, Set<String>)> _inline(String line, int from, int to, Set<String> on, Map<int, _Stars> stars) {
  final runs = <(String, Set<String>)>[];
  var start = from, at = from;
  while (at < to) {
    final span = _span(line, from, to, at, on, stars);
    if (span == null) {
      at++;
      continue;
    }
    final (key, open, close, end) = span;
    if (at > start) runs.add((line.substring(start, at), on));
    runs.addAll(_inline(line, open, close, {...on, key}, stars));
    at = start = end;
  }
  if (start < to) runs.add((line.substring(start, to), on));
  return runs;
}

/// The inline mark that opens at [at], between [from] and [to]: its key, where its words start and stop, and where its
/// closing mark ends.
(String, int, int, int)? _span(String line, int from, int to, int at, Set<String> on, Map<int, _Stars> stars) {
  if (stars[at] case final pair?) {
    final end = pair.close + pair.length;
    return on.contains(pair.key) || end > to ? null : (pair.key, at + pair.length, pair.close, end);
  }
  if (line[at] == '[' && !on.any((mark) => mark.startsWith(_linkKey))) {
    if (_linkAt(line, at, to) case final link?) return link;
  }
  final highlighted = on.any((mark) => mark.startsWith(_markKey));
  for (final (key, open, close) in [..._inlineMarks, if (!highlighted) ..._highlightMarks]) {
    if (on.contains(key) || !line.startsWith(open, at)) continue;
    final words = at + open.length;
    if (words >= to || _space(line[words]) || (key == 'italic' && at > from && _word(line[at - 1]))) continue;
    var stop = line.indexOf(close, words + 1);
    while (stop >= 0 && stop + close.length <= to && !_closes(line, to, stop, close, key)) {
      stop = line.indexOf(close, stop + 1);
    }
    if (stop >= 0 && stop + close.length <= to) return (key, words, stop, stop + close.length);
  }
  return null;
}

/// The link `[words](address)` that opens at [at] before [to]: its key, where its words start and stop, and where it
/// ends. The words have no `]` and no space at either edge, and the address no space; its brackets may pair inside it,
/// as in `https://en.wikipedia.org/wiki/Mercury_(planet)`.
(String, int, int, int)? _linkAt(String line, int at, int to) {
  final stop = line.indexOf(']', at + 1);
  if (stop < at + 2 || stop + 1 >= to || line[stop + 1] != '(') return null;
  if (_space(line[at + 1]) || _space(line[stop - 1])) return null;
  var depth = 0;
  for (var end = stop + 2; end < to; end++) {
    final char = line[end];
    if (_space(char)) return null;
    if (char == '(') depth++;
    if (char == ')' && depth-- == 0) {
      return end == stop + 2 ? null : ('$_linkKey${line.substring(stop + 2, end)}', at + 1, stop, end + 1);
    }
  }
  return null;
}

bool _closes(String line, int to, int at, String close, String key) =>
  !_space(line[at - 1]) && (key != 'italic' || at + close.length >= to || !_word(line[at + close.length]));

/// The Markdown of [nodes], the inverse of [markdownToNodes]. Bold, italic, underline, strike, a highlight and a link
/// are kept inline; any other style keeps its words. A table is kept as a Markdown table.
String documentToMarkdown(Iterable<DocumentNode> nodes) {
  final lines = <String>[];
  final counts = <int, int>{};
  for (final node in nodes) {
    if (node is NoteTableNode) {
      counts.clear();
      lines.add(node.table.markdown);
      continue;
    }
    if (node is AttachmentNode) {
      counts.clear();
      lines.add(node.file.markdown);
      continue;
    }
    if (node is! TextNode) continue;
    final kind = kindOf(node);
    if (kind == LineKind.code) {
      counts.clear();
      lines.addAll([_fence, node.text.toPlainText(includePlaceholders: false), _fence]);
      continue;
    }
    final level = min(indentOf(node), _maxIndent);
    final mark = _markOf(kind, level, counts);
    // Each later line of the node starts where its words do: inside a list item, at the item's words, so it reads
    // back as part of the item; else at its indent, with a quote's mark.
    final later = isItem(kind) ? ' ' * mark.length : '  ' * level + (kind == LineKind.quote ? '> ' : '');
    final parts = _split(runsOf(node.text));
    for (var at = 0; at < parts.length; at++) {
      // A blank line inside a list item is written blank, with no spaces: it reads back in the item all the same.
      final blank = at > 0 && isItem(kind) && parts[at].isEmpty;
      lines.add(blank ? '' : (at == 0 ? mark : later) + _inlineOf(parts[at]));
    }
  }
  return lines.join('\n');
}

/// [runs] split at each `\n`, a list of runs for each line.
List<List<(String, Set<String>)>> _split(List<(String, Set<String>)> runs) {
  final lines = <List<(String, Set<String>)>>[[]];
  for (final (words, marks) in runs) {
    final parts = words.split('\n');
    for (var at = 0; at < parts.length; at++) {
      if (at > 0) lines.add([]);
      if (parts[at].isNotEmpty) lines.last.add((parts[at], marks));
    }
  }
  return lines;
}

/// The indent and line mark that start a line of [kind].
String _markOf(LineKind kind, int level, Map<int, int> counts) {
  final indent = '  ' * level;
  if (kind == LineKind.numbered) return '$indent${_count(counts, level, ordered: true)}. ';
  _count(counts, level, ordered: false);
  for (final (mark, of) in _lineMarks) {
    if (of == kind) return indent + mark;
  }
  return indent;
}

const _opens = {'bold': '**', 'italic': '_', 'strike': '~~', 'underline': '<u>'};
const _closesOf = {'bold': '**', 'italic': '_', 'strike': '~~', 'underline': '</u>'};

/// A link's marks while a line is written, swapped for `[` and `](address)` at the end: a link whose words are its
/// address is written as the bare address, so an address shown as a link never gains brackets. Private-use letters,
/// which no note types.
const _linkOpen = '', _linkClose = '', _linkEnd = '';

String _openOf(String key) => key.startsWith(_linkKey) ? _linkOpen
  : key.startsWith(_markKey) ? '<mark class="${key.substring(_markKey.length)}">' : _opens[key]!;

String _closeOf(String key) => key.startsWith(_linkKey) ? '$_linkClose${key.substring(_linkKey.length)}$_linkEnd'
  : key.startsWith(_markKey) ? '</mark>' : _closesOf[key]!;

final _writtenLink = RegExp('$_linkOpen([^$_linkClose]*)$_linkClose([^$_linkEnd]*)$_linkEnd');

/// One line's runs with their marks. Spaces at a style's edge go outside its marks, so `**a **` never comes out, as
/// it would read back as words. Italic is `_`, or `*` where a `_` would touch a letter and read back as words, as in
/// `*foo*bar`.
String _inlineOf(List<(String, Set<String>)> runs) {
  var text = '';
  final open = <String>[];
  // Where each italic mark starts, opening and closing in turn.
  final italics = <int>[];
  void closeTo(Set<String> keep) {
    final cut = open.indexWhere((key) => !keep.contains(key));
    if (cut < 0) return;
    final trimmed = text.trimRight();
    final spaces = text.substring(trimmed.length);
    var marks = '';
    for (final key in open.sublist(cut).reversed) {
      if (key == 'italic') italics.add(trimmed.length + marks.length);
      marks += _closeOf(key);
    }
    text = trimmed + marks + spaces;
    open.removeRange(cut, open.length);
  }
  for (final (words, marks) in runs) {
    // Spaces keep the marks still open that they share, and open none, as a mark opened on spaces reads back as words.
    final blank = words.trim().isEmpty;
    final want = blank ? marks.intersection(open.toSet()) : marks;
    closeTo(want);
    final opening = [if (!blank) for (final key in want) if (!open.contains(key)) key]
      ..sort((a, b) => _rankOf(a).compareTo(_rankOf(b)));
    final lead = opening.isEmpty ? 0 : words.length - words.trimLeft().length;
    var head = text + words.substring(0, lead);
    for (final key in opening) {
      if (key == 'italic') italics.add(head.length);
      head += _openOf(key);
    }
    text = head + words.substring(lead);
    open.addAll(opening);
  }
  closeTo(const {});
  for (var at = 0; at + 1 < italics.length; at += 2) {
    final (start, end) = (italics[at], italics[at + 1]);
    if (_wordAt(text, start - 1) || _wordAt(text, end + 1)) {
      text = text.replaceRange(start, start + 1, '*').replaceRange(end, end + 1, '*');
    }
  }
  return text.replaceAllMapped(_writtenLink, (link) => link[1] == link[2] ? link[1]! : '[${link[1]}](${link[2]})');
}

/// [markdown] with no marks: the words as the page shows them, line by line, and a table's rows with a tab between
/// cells. A file's line is left out. The list, search and Share read it.
String plainText(String markdown) => nodesText(markdownToNodes(markdown));

/// The words of [nodes] as [plainText] gives them.
String nodesText(Iterable<DocumentNode> nodes) => [
  for (final node in nodes)
    if (node is TextNode) node.text.toPlainText(includePlaceholders: false)
    else if (node is NoteTableNode) node.table.text,
].join('\n');

/// A note's file at its place in the words: its id, and the name a reader of the text sees. The editor keeps it as one
/// [AttachmentNode].
class NoteAttachment {
  const NoteAttachment(this.id, this.name);

  final String id;
  final String name;

  static final _line = RegExp(r'^!\[([^\]\n]*)\]\(attachment:([A-Za-z0-9:_-]{1,80})\)$');
  static final _id = RegExp(r'^[A-Za-z0-9:_-]{1,80}$');

  /// Whether a file's [id] can make its line: a file with no id, or an odd one, shows outside the words.
  static bool placeable(String id) => _id.hasMatch(id);

  /// The file a whole [line] names, or null for words.
  static NoteAttachment? read(String line) {
    final match = _line.firstMatch(line);
    return match == null ? null : NoteAttachment(match[2]!, match[1]!);
  }

  /// The line that marks the file's place. A name's brackets and line breaks become `_`, so the line reads back.
  String get markdown => '![${name.replaceAll(RegExp(r'[\[\]\r\n]'), '_')}](attachment:$id)';

  /// The ids of the files whose lines [text] holds.
  static Set<String> idsIn(String text) => {for (final line in text.split('\n')) ?read(line)?.id};

  /// [text] with no line for a file in [ids]: a note never names a file it does not keep.
  static String without(String text, Set<String> ids) => ids.isEmpty ? text
    : text.split('\n').where((line) => !ids.contains(read(line)?.id)).join('\n');

  @override
  bool operator ==(Object other) => other is NoteAttachment && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A table in a note: its rows of plain words, the first the head row, and the Markdown it was read from. The editor
/// keeps it as one [NoteTableNode]; [id] tells two tables apart while the page is open.
class NoteTable {
  NoteTable(List<List<String>> rows, {this.source, String? id})
    : rows = List.unmodifiable([for (final row in rows) List<String>.unmodifiable(row)]), id = id ?? _newId();

  final List<List<String>> rows;
  /// The table's Markdown as it was read, written back while the cells are the same, so a table from Claude keeps its
  /// spacing and alignment marks.
  final String? source;
  final String id;

  int get columns => rows.isEmpty ? 0 : rows.first.length;

  static final _random = Random();
  static String _newId() => [for (var at = 0; at < 4; at++) _random.nextInt(1 << 16).toRadixString(16)].join();

  /// The same table with [rows] in place of its own.
  NoteTable withRows(List<List<String>> rows) => NoteTable(rows, source: source, id: id);

  /// The same table with a new [id], for a copy pasted in.
  NoteTable withNewId() => NoteTable(rows, source: source);

  /// A new empty table, [columns] wide and [count] rows long.
  factory NoteTable.empty({int columns = 2, int count = 2}) =>
    NoteTable([for (var row = 0; row < count; row++) List.filled(columns, '')]);

  String toJson() => jsonEncode({'id': id, 'rows': rows, 'source': ?source});

  static NoteTable? fromJson(String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final rows = [for (final row in json['rows'] as List) [for (final cell in row as List) '$cell']];
      return NoteTable(rows, source: json['source'] as String?, id: json['id'] as String?);
    } on Object {
      return null;
    }
  }

  /// Whether [other] holds the same cells.
  bool sameRows(NoteTable other) => _sameRows(other.rows, rows);

  /// The table as Markdown: [source] while the cells are those it holds, else a plain table with `\|` for a pipe.
  String get markdown {
    final from = source;
    if (from != null && _sameRows(readAt(from.split('\n'), 0)?.$1.rows, rows)) return from;
    String line(List<String> cells) =>
      '| ${[for (final cell in cells) cell.replaceAll('\n', ' ').replaceAll('|', r'\|')].join(' | ')} |';
    return [
      if (rows.isNotEmpty) ...[line(rows.first), line(List.filled(columns, '---'))],
      for (final row in rows.skip(1)) line(row),
    ].join('\n');
  }

  /// The rows as words: a tab between cells, a line for each row.
  String get text => [for (final row in rows) row.join('\t')].join('\n');

  static bool _sameRows(List<List<String>>? a, List<List<String>> b) =>
    a != null && a.length == b.length && [for (var at = 0; at < a.length; at++) a[at].join('\u0000') == b[at].join('\u0000')]
      .every((same) => same);

  static final _divider = RegExp(r'^\|\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$');

  /// A `---` row with at least three dashes in each cell, as this codec writes it. Only such a row starts a next
  /// table inside one, so a body row of `-` cells (a "none" mark) stays a row.
  static final _fullDivider = RegExp(r'^\|\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$');

  /// The table whose head row is [lines] at [at], and the index of the first line after it; null when no table starts
  /// there. A table is a head row and a `---` row, each starting with `|` and with as many cells, then each row after
  /// them that starts with `|`, up to the head row of a next table. So a line of pipes alone stays words, and two
  /// tables written one after the other open as two again.
  static (NoteTable, int)? readAt(List<String> lines, int at) {
    if (!_startsAt(lines, at)) return null;
    final head = _cells(lines[at]);
    var end = at + 2;
    while (end < lines.length && lines[end].startsWith('|') && !_startsAt(lines, end, divider: _fullDivider)) {
      end++;
    }
    // Each row as wide as the head row: a short row gets empty cells, and a long one's extra cells only show in
    // [source], which stays while nothing changes.
    final rows = [
      head,
      for (final line in lines.sublist(at + 2, end))
        if (_cells(line) case final cells) [for (var column = 0; column < head.length; column++) column < cells.length ? cells[column] : ''],
    ];
    return (NoteTable(rows, source: lines.sublist(at, end).join('\n')), end);
  }

  /// Whether a table's head row is [lines] at [at]: a row and a `---` row after it, with as many cells.
  static bool _startsAt(List<String> lines, int at, {RegExp? divider}) {
    if (at + 1 >= lines.length || !lines[at].startsWith('|') || !(divider ?? _divider).hasMatch(lines[at + 1])) return false;
    final head = _cells(lines[at]);
    return head.isNotEmpty && _cells(lines[at + 1]).length == head.length;
  }

  /// A row's cells, trimmed, with `\|` read as a pipe in a cell.
  static List<String> _cells(String line) {
    var body = line.trimRight();
    if (body.startsWith('|')) body = body.substring(1);
    if (body.endsWith('|') && !body.endsWith(r'\|')) body = body.substring(0, body.length - 1);
    final cells = <String>[];
    var cell = StringBuffer();
    for (var at = 0; at < body.length; at++) {
      if (body[at] == r'\' && at + 1 < body.length && body[at + 1] == '|') {
        cell.write('|');
        at++;
      } else if (body[at] == '|') {
        cells.add(cell.toString().trim());
        cell = StringBuffer();
      } else {
        cell.write(body[at]);
      }
    }
    cells.add(cell.toString().trim());
    return cells;
  }
}
