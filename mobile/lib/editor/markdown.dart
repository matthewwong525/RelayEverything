import 'dart:math';

import 'package:flutter_quill/quill_delta.dart';

// A note keeps its styles in its words as Markdown, so the server, Claude and webhooks read plain text. The editor's
// Delta goes to it and back byte for byte; underline, which Markdown lacks, is `<u>…</u>`.

/// The editor's own list kind for a `- ` line: drawn as a dash, where `* ` is a bullet.
const dashedList = 'dashed';

const _fence = '```';
const _maxIndent = 8;
final _ordered = RegExp(r'^(\d{1,9})\. ');

/// Line marks, longest first, and the Delta line style each stands for.
const _lineMarks = <(String, String, Object)>[
  ('- [ ] ', 'list', 'unchecked'), ('- [x] ', 'list', 'checked'), ('* ', 'list', 'bullet'), ('- ', 'list', dashedList),
  ('> ', 'blockquote', true), ('### ', 'header', 3), ('## ', 'header', 2), ('# ', 'header', 1),
];

/// Inline marks other than `*`, in the order they open when several start together; italic last, as `_` is the
/// loosest. Stars pair up first, by [_pairStars].
const _inlineMarks = <(String, String, String)>[
  ('strike', '~~', '~~'), ('underline', '<u>', '</u>'), ('italic', '_', '_'),
];
const _writeOrder = ['bold', 'italic', 'strike', 'underline'];

/// The Delta of [markdown]. With [title], a first line with no line style shows as a Title, as an old note's first line
/// did in the list; its text gains `# ` only once the person changes the note.
Delta markdownToDelta(String markdown, {bool title = false}) {
  final delta = Delta();
  final lines = markdown.split('\n');
  final counts = <int, int>{};
  var code = false;
  for (var at = 0; at < lines.length; at++) {
    final end = lines[at] == _fence ? lines.indexOf(_fence, at + 1) : -1;
    if (end > at + 1) {
      // Two code blocks that touch would join into one in the editor, so an empty line keeps them two.
      if (code) delta.insert('\n');
      for (final row in lines.sublist(at + 1, end)) {
        if (row.isNotEmpty) delta.insert(row);
        delta.insert('\n', {'code-block': true});
      }
      counts.clear();
      code = true;
      at = end;
      continue;
    }
    code = false;
    final (style, words) = _lineOf(lines[at], counts);
    if (at == 0 && title && style.isEmpty && words.trim().isNotEmpty) style['header'] = 1;
    for (final (text, marks) in _inline(words, 0, words.length, const {}, _pairStars(words))) {
      delta.insert(text, marks.isEmpty ? null : {for (final mark in marks) mark: true});
    }
    delta.insert('\n', style.isEmpty ? null : style);
  }
  return delta;
}

/// A line's style and its words after the marks. A `N. ` line is numbered only when N is the next number of its list,
/// so `2020. was a year` stays words; [counts] holds each indent level's last number, as [deltaToMarkdown] counts.
(Map<String, dynamic>, String) _lineOf(String line, Map<int, int> counts) {
  var spaces = 0;
  while (spaces < line.length && line[spaces] == ' ') {
    spaces++;
  }
  final level = min(spaces ~/ 2, _maxIndent);
  final rest = line.substring(level * 2);
  final style = <String, dynamic>{if (level > 0) 'indent': level};
  final number = _ordered.firstMatch(rest);
  if (number != null && int.parse(number[1]!) == (counts[level] ?? 0) + 1) {
    _count(counts, level, ordered: true);
    return (style..['list'] = 'ordered', rest.substring(number.end));
  }
  _count(counts, level, ordered: false);
  for (final (mark, key, value) in _lineMarks) {
    if (rest.startsWith(mark)) return (style..[key] = value, rest.substring(mark.length));
  }
  return (style, rest);
}

/// Counts a numbered line at [level], or ends the lists at [level] and deeper; returns the line's number.
int _count(Map<int, int> counts, int level, {required bool ordered}) {
  counts.removeWhere((at, _) => at > level || (!ordered && at == level));
  if (!ordered) return 0;
  return counts[level] = (counts[level] ?? 0) + 1;
}

bool _space(String char) => char.trim().isEmpty;
bool _word(String char) => RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(char);

/// Where a `*` mark pairs: bold or italic, its length, and where its closing stars start.
typedef _Stars = ({String key, int length, int close});

/// Pairs the runs of `*` in [line], keyed by where each opening mark starts: `**` is bold and `*` italic. Marks nest,
/// so a run closes the marks open on top, then opens new ones, bold before italic, as [deltaToMarkdown] writes them:
/// `**foo***bar*` is bold *foo* then italic *bar*, and `x*a**b***` closes bold, then italic. A `*` italic counts only
/// when it touches a letter, as [deltaToMarkdown] writes it, so `5 * 3` and an old `*word*` stay as typed.
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
  for (final (key, open, close) in _inlineMarks) {
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

bool _closes(String line, int to, int at, String close, String key) =>
  !_space(line[at - 1]) && (key != 'italic' || at + close.length >= to || !_word(line[at + close.length]));

/// The Markdown of [delta], the inverse of [markdownToDelta]. Only bold, italic, underline and strike are kept inline;
/// a link or a colour pasted in keeps its words.
String deltaToMarkdown(Delta delta) {
  final lines = <String>[];
  final counts = <int, int>{};
  var runs = <(String, Set<String>)>[];
  var code = false;
  for (final op in delta.toList()) {
    final data = op.data;
    if (data is! String) continue;
    final attributes = op.attributes ?? const <String, dynamic>{};
    final parts = data.split('\n');
    for (var at = 0; at < parts.length; at++) {
      if (parts[at].isNotEmpty) runs.add((parts[at], {for (final key in _writeOrder) if (attributes[key] == true) key}));
      if (at == parts.length - 1) break;
      final isCode = attributes['code-block'] == true;
      if (isCode != code) lines.add(_fence);
      code = isCode;
      if (isCode) {
        counts.clear();
        lines.add([for (final (text, _) in runs) text].join());
      } else {
        lines.add(_markOf(attributes, counts) + _inlineOf(runs));
      }
      runs = [];
    }
  }
  if (code) lines.add(_fence);
  return lines.join('\n');
}

/// The indent and line mark that start a line of [style].
String _markOf(Map<String, dynamic> style, Map<int, int> counts) {
  final level = min(style['indent'] as int? ?? 0, _maxIndent);
  final indent = '  ' * level;
  final list = style['list'], header = style['header'];
  if (list == 'ordered') return '$indent${_count(counts, level, ordered: true)}. ';
  _count(counts, level, ordered: false);
  for (final (mark, key, value) in _lineMarks) {
    if ((key == 'list' && list == value) || (key == 'header' && header == value) ||
      (key == 'blockquote' && style['blockquote'] == true)) {
      return indent + mark;
    }
  }
  return indent;
}

const _opens = {'bold': '**', 'italic': '_', 'strike': '~~', 'underline': '<u>'};
const _closesOf = {'bold': '**', 'italic': '_', 'strike': '~~', 'underline': '</u>'};

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
      marks += _closesOf[key]!;
    }
    text = trimmed + marks + spaces;
    open.removeRange(cut, open.length);
  }
  for (final (words, marks) in runs) {
    // Spaces keep the marks still open that they share, and open none, as a mark opened on spaces reads back as words.
    final blank = words.trim().isEmpty;
    final want = blank ? marks.intersection(open.toSet()) : marks;
    closeTo(want);
    final opening = [if (!blank) for (final key in _writeOrder) if (want.contains(key) && !open.contains(key)) key];
    final lead = opening.isEmpty ? 0 : words.length - words.trimLeft().length;
    var head = text + words.substring(0, lead);
    for (final key in opening) {
      if (key == 'italic') italics.add(head.length);
      head += _opens[key]!;
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
  return text;
}

/// [markdown] with no marks: the words as the page shows them, line by line. The list, search and Share read it.
String plainText(String markdown) {
  final text = [for (final op in markdownToDelta(markdown).toList()) if (op.data is String) op.data as String].join();
  return text.substring(0, text.length - 1);
}
