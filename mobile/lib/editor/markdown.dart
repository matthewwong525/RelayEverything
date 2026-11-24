import 'dart:convert';
import 'dart:math';

// A note keeps its styles in its words as Markdown, so the server, Claude and webhooks read plain text. The editor
// page's document goes to it and back byte for byte; underline, which Markdown lacks, is `<u>…</u>`, a highlight is
// `<mark class="pink">…</mark>`, a link on words is `[words](address)`, a table is a Markdown table, and a note's file
// is a line `![name](attachment:<id>)` at its place.
//
// Markdown is read into [NoteBlock]s, one for each line the page shows, and the blocks go to the page as its document
// JSON ([blocksToDoc]) and come back from it ([docToBlocks]).

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

/// A highlight's inline mark, `mark:pink`, and a link's, `link:https://…`: a run's marks are words, so a mark with a
/// value carries it after the colon.
const _markKey = 'mark:', _linkKey = 'link:';

/// The highlight marks, one for each colour.
final _highlightMarks = <(String, String, String)>[
  for (final colour in highlightColours) ('$_markKey$colour', '<mark class="$colour">', '</mark>'),
];

/// Words with the inline marks on them: `bold`, `italic`, `strike`, `underline`, `mark:<colour>` and `link:<address>`.
typedef Run = (String, Set<String>);

/// Whether a note can keep [mark]: bold, italic, strike and underline, a highlight in one of the [highlightColours],
/// and a link with an address. Any other style keeps only its words.
bool keptMark(String mark) => _writeOrder.contains(mark) ||
  (mark.startsWith(_markKey) && highlightColours.contains(mark.substring(_markKey.length))) ||
  (mark.startsWith(_linkKey) && mark.length > _linkKey.length);

/// [runs] with only the marks a note keeps, no empty run, and each run joined to the one before it with the same marks.
List<Run> tidyRuns(Iterable<Run> runs) {
  final out = <Run>[];
  for (final (words, marks) in runs) {
    if (words.isEmpty) continue;
    final kept = {for (final mark in marks) if (keptMark(mark)) mark};
    final last = out.lastOrNull;
    if (last != null && _sameSet(last.$2, kept)) {
      out.last = (last.$1 + words, last.$2);
    } else {
      out.add((words, kept));
    }
  }
  return out;
}

bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

/// Where a mark opens among others that open together: a link outside all, then a highlight, then the rest.
int _rankOf(String key) => key.startsWith(_linkKey) ? 0 : key.startsWith(_markKey) ? 1 : 2 + _writeOrder.indexOf(key);

/// One block of a note as the page shows it: a line of words, a table or a file.
sealed class NoteBlock {
  const NoteBlock();
}

/// A line of words: its kind, its indent and its runs of marked words. A list item's words may hold `\n`: each line
/// after the first is a line under the item, such as `Why:`. A code block's words hold its lines.
final class NoteLine extends NoteBlock {
  NoteLine(this.kind, Iterable<Run> runs, {int indent = 0, this.title = false})
    : runs = List.unmodifiable(tidyRuns(runs)), indent = indent.clamp(0, _maxIndent);

  /// A line of [words] with no marks.
  NoteLine.plain(LineKind kind, String words, {int indent = 0}) : this(kind, [(words, const {})], indent: indent);

  final LineKind kind;
  final int indent;
  final List<Run> runs;

  /// Whether the line is a plain first line shown as a Title: an old note's first line, as the list showed it.
  final bool title;

  String get text => [for (final (words, _) in runs) words].join();

  NoteLine copyWith({LineKind? kind, List<Run>? runs, int? indent}) =>
    NoteLine(kind ?? this.kind, runs ?? this.runs, indent: indent ?? this.indent, title: title);
}

/// A table, with its rows of plain words.
final class NoteTableBlock extends NoteBlock {
  const NoteTableBlock(this.table);

  final NoteTable table;
}

/// A note's file at its place in the words.
final class NoteFileBlock extends NoteBlock {
  const NoteFileBlock(this.file);

  final NoteAttachment file;
}

/// Whether [kind] is a list item: its later lines are indented to its words.
bool isItem(LineKind kind) => const {LineKind.bullet, LineKind.dashed, LineKind.numbered, LineKind.unchecked,
  LineKind.checked}.contains(kind);

/// The blocks of [markdown]. With [title], a first line with no line style shows as a Title, as an old note's first
/// line did in the list; its text gains `# ` only once the person changes the note. A file's line is a block only when
/// [files] holds its id, or [files] is null; else it stays words.
List<NoteBlock> markdownToBlocks(String markdown, {bool title = false, Set<String>? files}) {
  final blocks = <NoteBlock>[];
  final lines = markdown.split('\n');
  var counts = <int, int>{};
  // The list item that later lines indented to its words join, and where its words start.
  NoteLine? item;
  var itemStart = 0;
  for (var at = 0; at < lines.length; at++) {
    final end = lines[at] == _fence ? lines.indexOf(_fence, at + 1) : -1;
    if (end > at + 1) {
      blocks.add(NoteLine.plain(LineKind.code, lines.sublist(at + 1, end).join('\n')));
      counts.clear();
      item = null;
      at = end;
      continue;
    }
    if (NoteTable.readAt(lines, at) case (final table, final next)) {
      blocks.add(NoteTableBlock(table));
      counts.clear();
      item = null;
      at = next - 1;
      continue;
    }
    if (NoteAttachment.read(lines[at]) case final file? when files == null || files.contains(file.id)) {
      blocks.add(NoteFileBlock(file));
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
        blocks.last = item = item.copyWith(runs: [...item.runs, ('\n' * (later - at), const {}), ('\n', const {}),
          ..._lineRuns(lines[later].substring(itemStart))]);
        at = later;
        continue;
      }
    }
    final next = {...counts};
    final (kind, level, words) = _lineOf(line, next);
    final spaces = line.length - line.trimLeft().length;
    if (item != null && kind == LineKind.paragraph && line.trim().isNotEmpty && spaces >= itemStart) {
      // A line indented to the words of the list item above belongs to that item, so `Why:` under an item stays in it.
      blocks.last = item = item.copyWith(runs: [...item.runs, ('\n', const {}), ..._lineRuns(line.substring(itemStart))]);
      continue;
    }
    counts = next;
    final heading = at == 0 && title && kind == LineKind.paragraph && level == 0 && words.trim().isNotEmpty;
    final block = NoteLine(heading ? LineKind.header1 : kind, _lineRuns(words), indent: level, title: heading);
    blocks.add(block);
    item = isItem(kind) ? block : null;
    itemStart = level * 2 + _markLength(line.substring(level * 2), kind);
  }
  return blocks;
}

/// Whether line [at] of [lines] is words indented to the words of a list item that starts its words at [itemStart],
/// so it belongs to that item: not a file's line, a table, a code block or a new item.
bool _continues(List<String> lines, int at, int itemStart, Map<int, int> counts) {
  final line = lines[at];
  return line.trim().isNotEmpty && line.length - line.trimLeft().length >= itemStart && line != _fence &&
    NoteAttachment.read(line) == null && NoteTable.readAt(lines, at) == null &&
    _lineOf(line, {...counts}).$1 == LineKind.paragraph;
}

List<Run> _lineRuns(String words) => _inline(words, 0, words.length, const {}, _pairStars(words));

int _markLength(String rest, LineKind kind) => kind == LineKind.numbered ? _ordered.firstMatch(rest)!.end
  : [for (final (mark, of) in _lineMarks) if (of == kind) mark.length].firstOrNull ?? 0;

/// A line's kind, its indent level and its words after the marks. A `N. ` line is numbered only when N is the next
/// number of its list, so `2020. was a year` stays words; [counts] holds each indent level's last number, as
/// [blocksToMarkdown] counts.
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

/// The number each numbered item in [blocks] shows, by its place, as the Markdown counts them. The page counts the
/// same way.
Map<int, int> itemNumbers(List<NoteBlock> blocks) {
  final numbers = <int, int>{};
  final counts = <int, int>{};
  for (var at = 0; at < blocks.length; at++) {
    final block = blocks[at];
    if (block is! NoteLine || block.kind == LineKind.code) {
      counts.clear();
      continue;
    }
    final number = _count(counts, block.indent, ordered: block.kind == LineKind.numbered);
    if (block.kind == LineKind.numbered) numbers[at] = number;
  }
  return numbers;
}

bool _space(String char) => char.trim().isEmpty;
bool _word(String char) => RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(char);

/// Where a `*` mark pairs: bold or italic, its length, and where its closing stars start.
typedef _Stars = ({String key, int length, int close});

/// Pairs the runs of `*` in [line], keyed by where each opening mark starts: `**` is bold and `*` italic. Marks nest,
/// so a run closes the marks open on top, then opens new ones, bold before italic, as [blocksToMarkdown] writes
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

/// The Markdown of [blocks], the inverse of [markdownToBlocks]. Bold, italic, underline, strike, a highlight and a link
/// are kept inline; any other style keeps its words. A table is kept as a Markdown table.
String blocksToMarkdown(Iterable<NoteBlock> blocks) {
  final lines = <String>[];
  final counts = <int, int>{};
  for (final block in blocks) {
    switch (block) {
      case NoteTableBlock(:final table):
        counts.clear();
        lines.add(table.markdown);
      case NoteFileBlock(:final file):
        counts.clear();
        lines.add(file.markdown);
      case NoteLine(kind: LineKind.code):
        counts.clear();
        lines.addAll([_fence, block.text, _fence]);
      case NoteLine(:final kind):
        final level = min(block.indent, _maxIndent);
        final mark = _markOf(kind, level, counts);
        // Each later line of the block starts where its words do: inside a list item, at the item's words, so it reads
        // back as part of the item; else at its indent, with a quote's mark.
        final later = isItem(kind) ? ' ' * mark.length : '  ' * level + (kind == LineKind.quote ? '> ' : '');
        final parts = _split(block.runs);
        for (var at = 0; at < parts.length; at++) {
          // A blank line inside a list item is written blank, with no spaces: it reads back in the item all the same.
          final blank = at > 0 && isItem(kind) && parts[at].isEmpty;
          lines.add(blank ? '' : (at == 0 ? mark : later) + _inlineOf(parts[at]));
        }
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
const _linkOpen = '\uE000', _linkClose = '\uE001', _linkEnd = '\uE002';

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
String plainText(String markdown) => blocksText(markdownToBlocks(markdown));

/// The words of [blocks] as [plainText] gives them.
String blocksText(Iterable<NoteBlock> blocks) => [
  for (final block in blocks)
    if (block is NoteLine) block.text
    else if (block is NoteTableBlock) block.table.text,
].join('\n');

/// The files placed in [blocks], in order.
List<NoteAttachment> attachmentsIn(Iterable<NoteBlock> blocks) =>
  [for (final block in blocks) if (block is NoteFileBlock) block.file];

// The editor page's document: ProseMirror JSON. Each line of words is a `paragraph`, `heading`, `blockquote` or
// `codeBlock` with an `indent`; a list item is an `item` with its `kind`, `checked` and `indent`, whose first paragraph
// is its words and each later paragraph a line under it; a table is a `table` of rows of cells, each one paragraph of
// plain words; a file is an `attachment` with its `id` and `name`. The marks are `bold`, `italic`, `underline`,
// `strike`, `highlight` with its `colour`, and `link` with its `href` and `auto`: a link the page made on a web address
// it found in the words, which the Markdown keeps as the bare address.

typedef Json = Map<String, Object?>;

const _itemKinds = {
  LineKind.bullet: 'bullet', LineKind.dashed: 'dashed', LineKind.numbered: 'numbered',
  LineKind.unchecked: 'task', LineKind.checked: 'task',
};

/// The page's document of [markdown], as [markdownToBlocks] reads it.
Json markdownToDoc(String markdown, {bool title = false, Set<String>? files}) =>
  blocksToDoc(markdownToBlocks(markdown, title: title, files: files));

/// The Markdown of the page's document [doc].
String docToMarkdown(Json doc) => blocksToMarkdown(docToBlocks(doc));

/// The page's document of [blocks]: never empty, as a note has one line at least.
Json blocksToDoc(Iterable<NoteBlock> blocks) {
  final content = [for (final block in blocks) ...blockToNodes(block)];
  return {'type': 'doc', 'content': content.isEmpty ? [_paragraph(const [], 0)] : content};
}

/// The page's nodes of one [block]: a line of words with `\n` outside a list item is a node for each line.
List<Json> blockToNodes(NoteBlock block) => switch (block) {
  NoteFileBlock(:final file) => [{'type': 'attachment', 'attrs': {'id': file.id, 'name': file.name}}],
  NoteTableBlock(:final table) => [_tableNode(table)],
  NoteLine(kind: LineKind.code) => [{
    'type': 'codeBlock',
    if (block.text.isNotEmpty) 'content': [{'type': 'text', 'text': block.text}],
  }],
  NoteLine(:final kind) when isItem(kind) => [{
    'type': 'item',
    'attrs': {'kind': _itemKinds[kind], 'checked': kind == LineKind.checked, 'indent': block.indent},
    'content': [for (final line in _split(block.runs)) _paragraph(line, 0)],
  }],
  NoteLine(:final kind, :final indent) => [
    for (final (at, line) in _split(block.runs).indexed)
      switch (kind) {
        LineKind.header1 || LineKind.header2 || LineKind.header3 => {
          'type': 'heading',
          'attrs': {'level': kind.index - LineKind.header1.index + 1, 'indent': indent, 'title': block.title && at == 0},
          if (line.isNotEmpty) 'content': _textNodes(line),
        },
        LineKind.quote => {'type': 'blockquote', 'attrs': {'indent': indent}, if (line.isNotEmpty) 'content': _textNodes(line)},
        _ => _paragraph(line, indent),
      },
  ],
};

Json _paragraph(List<Run> runs, int indent) =>
  {'type': 'paragraph', 'attrs': {'indent': indent}, if (runs.isNotEmpty) 'content': _textNodes(runs)};

Json _tableNode(NoteTable table) => {
  'type': 'table',
  'attrs': {'source': table.source},
  'content': [
    for (final (at, row) in table.rows.indexed)
      {'type': 'tableRow', 'content': [
        for (final cell in row)
          {'type': at == 0 ? 'tableHeader' : 'tableCell', 'content': [_paragraph([(cell, const {})], 0)]},
      ]},
  ],
};

List<Json> _textNodes(List<Run> runs) => [
  for (final (words, marks) in tidyRuns(runs))
    {'type': 'text', 'text': words, if (marks.isNotEmpty) 'marks': [
      for (final mark in marks.toList()..sort((a, b) => _rankOf(a).compareTo(_rankOf(b)))) _markJson(mark),
    ]},
];

Json _markJson(String mark) {
  if (mark.startsWith(_linkKey)) return {'type': 'link', 'attrs': {'href': mark.substring(_linkKey.length), 'auto': false}};
  if (mark.startsWith(_markKey)) return {'type': 'highlight', 'attrs': {'colour': mark.substring(_markKey.length)}};
  return {'type': mark};
}

/// The mark key of a page's [mark], or null for one a note does not keep. A link the page made on a web address is
/// none: the address stays words.
String? _markOfJson(Json mark) {
  final attrs = (mark['attrs'] as Map?) ?? const {};
  return switch (mark['type']) {
    'bold' || 'italic' || 'underline' || 'strike' => mark['type'] as String,
    'highlight' => '$_markKey${attrs['colour']}',
    'link' when attrs['auto'] != true => '$_linkKey${attrs['href'] ?? ''}',
    _ => null,
  };
}

List<Json> _children(Json node) => [for (final child in (node['content'] as List?) ?? const []) (child as Map).cast()];

Json _attrs(Json node) => ((node['attrs'] as Map?) ?? const {}).cast();

int _intOf(Object? value, [int or = 0]) => value is num ? value.toInt() : or;

/// The runs of words in a text block [node].
List<Run> _runsOfNode(Json node) => tidyRuns([
  for (final child in _children(node))
    if (child['type'] == 'text')
      (child['text'] as String? ?? '', {for (final mark in (child['marks'] as List?) ?? const []) ?_markOfJson((mark as Map).cast())})
    else if (child['type'] == 'hardBreak') ('\n', const {}),
]);

/// The words in a [node] and all inside it, with no marks.
String _wordsOf(Json node) => node['type'] == 'text' ? node['text'] as String? ?? ''
  : [for (final child in _children(node)) _wordsOf(child)].join(node['type'] == 'tableRow' ? '\t' : '');

/// The blocks of the page's document [doc], the inverse of [blocksToDoc].
List<NoteBlock> docToBlocks(Json doc) => [
  for (final node in _children(doc)) ?_blockOf(node),
];

NoteBlock? _blockOf(Json node) {
  final attrs = _attrs(node);
  final indent = _intOf(attrs['indent']);
  switch (node['type']) {
    case 'attachment':
      final id = '${attrs['id'] ?? ''}';
      return NoteAttachment.placeable(id) ? NoteFileBlock(NoteAttachment(id, '${attrs['name'] ?? ''}')) : null;
    case 'table':
      final rows = [
        for (final row in _children(node))
          [for (final cell in _children(row)) _wordsOf(cell).replaceAll('\n', ' ')],
      ];
      if (rows.isEmpty) return null;
      final source = attrs['source'];
      return NoteTableBlock(NoteTable(rows, source: source is String ? source : null));
    case 'codeBlock':
      return NoteLine.plain(LineKind.code, _wordsOf(node));
    case 'heading':
      final level = _intOf(attrs['level'], 1).clamp(1, 3);
      return NoteLine(LineKind.values[LineKind.header1.index + level - 1], _runsOfNode(node), indent: indent,
        title: attrs['title'] == true);
    case 'blockquote':
      return NoteLine(LineKind.quote, _runsOfNode(node), indent: indent);
    case 'item':
      final kind = switch (attrs['kind']) {
        'bullet' => LineKind.bullet,
        'numbered' => LineKind.numbered,
        'task' => attrs['checked'] == true ? LineKind.checked : LineKind.unchecked,
        _ => LineKind.dashed,
      };
      final lines = _children(node);
      return NoteLine(kind, [
        for (final (at, line) in lines.indexed) ...[if (at > 0) ('\n', const <String>{}), ..._runsOfNode(line)],
      ], indent: indent);
    default:
      return NoteLine(LineKind.paragraph, _runsOfNode(node), indent: indent);
  }
}

/// A note's file at its place in the words: its id, and the name a reader of the text sees. The editor keeps it as one
/// [NoteFileBlock].
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
/// keeps it as one [NoteTableBlock].
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
