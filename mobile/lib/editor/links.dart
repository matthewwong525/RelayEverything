import 'package:flutter/widgets.dart' show TextAffinity, TextPosition, TextRange;
import 'package:super_editor/super_editor.dart';

import 'markdown.dart';
import 'note_editing.dart';

// The links in a note's words. Each web address in the words shows as a link to itself, and words linked to another
// address keep their link. The Markdown writer writes an address linked to itself as the bare address, so marking
// links never changes the stored words.

/// A web address in a note's words: `https://…`, `http://…` or `www.…`, up to a space, less the stop or bracket that
/// ends a sentence.
final _webAddress = RegExp(r'(?:https?://|www\.)[^\s<>"]+', caseSensitive: false);
final _endPunctuation = RegExp(r'''[.,;:!?)\]}'"]+$''');

/// A link's own scheme, such as `https:` or `mailto:`; `www.` has none.
final linkScheme = RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false);

const _linkMark = 'link:';

/// Each web address in [words], with where it starts.
Iterable<({int start, String address})> linkRanges(String words) sync* {
  for (final match in _webAddress.allMatches(words)) {
    final address = match[0]!.replaceFirst(_endPunctuation, '');
    if (address.contains('.') && !address.endsWith('://')) yield (start: match.start, address: address);
  }
}

/// The address a person typed in the *Link* box, as the link keeps it: `example.com` gains `https://`, and an address
/// with its own scheme, such as `mailto:`, stays. Null for words that are no address.
String? linkAddressOf(String typed) {
  final words = typed.trim();
  if (words.isEmpty || words.contains(RegExp(r'\s'))) return null;
  if (linkScheme.hasMatch(words)) return words;
  return words.contains('.') ? 'https://$words' : null;
}

/// [nodes] with each web address in their words marked as a link, for the page to show. A link on words that hold no
/// web address and are no piece of the link stays, as `[the menu](…)` does; each other link goes, as an edited
/// address keeps the link of what it was; then each web address is linked to itself. A node with nothing to change
/// stays the same node, so a note kept as it is stays kept.
List<DocumentNode> withLinks(List<DocumentNode> nodes) {
  final out = [for (final node in nodes) _linked(node)];
  return [for (var at = 0; at < nodes.length; at++) identical(out[at], nodes[at])].every((same) => same) ? nodes : out;
}

DocumentNode _linked(DocumentNode node) {
  if (node is! TextNode || kindOf(node) == LineKind.code) return node;
  final words = node.text.toPlainText(includePlaceholders: false);
  if (words.isEmpty) return node;
  // Each letter's marks, with its link apart.
  final marks = <Set<String>>[];
  for (final (run, on) in runsOf(node.text)) {
    for (var at = 0; at < run.length; at++) {
      marks.add(on);
    }
  }
  if (marks.length != words.length) return node;
  String? linkOf(int at) => marks[at].where((mark) => mark.startsWith(_linkMark)).firstOrNull?.substring(_linkMark.length);
  final now = [for (var at = 0; at < words.length; at++) linkOf(at)];
  // The runs of letters with one link.
  final runs = <(int, int, String)>[];
  for (var at = 0; at < words.length; at++) {
    final link = now[at];
    if (link == null) continue;
    final last = runs.lastOrNull;
    if (last != null && last.$3 == link && last.$1 + last.$2 == at) {
      runs.last = (last.$1, last.$2 + 1, link);
    } else {
      runs.add((at, 1, link));
    }
  }
  bool keeps((int, int, String) run) {
    final linked = words.substring(run.$1, run.$1 + run.$2).trim().toLowerCase();
    // Words that are a piece of their own link were an address: `example.com` left from `https://example.com`. Only
    // words with a `.` or a `/` can be such a piece, so *menu* linked to `https://example.com/menu` stays a link.
    final address = run.$3.toLowerCase().replaceFirst(linkScheme, '').replaceFirst(RegExp('^//'), '');
    final piece = linked.isEmpty || (linked.contains(RegExp('[./]')) && address.contains(linked));
    return linkRanges(linked).isEmpty && !piece;
  }
  final want = List<String?>.filled(words.length, null);
  final kept = [for (final run in runs) if (keeps(run)) run];
  for (final run in kept) {
    for (var at = run.$1; at < run.$1 + run.$2; at++) {
      want[at] = run.$3;
    }
  }
  for (final range in linkRanges(words)) {
    final end = range.start + range.address.length;
    if (kept.any((run) => range.start < run.$1 + run.$2 && run.$1 < end)) continue;
    for (var at = range.start; at < end; at++) {
      want[at] = range.address;
    }
  }
  var same = true;
  for (var at = 0; at < words.length && same; at++) {
    if (want[at] != now[at]) same = false;
  }
  if (same) return node;
  final letters = [
    for (var at = 0; at < words.length; at++)
      (words[at], {...marks[at].where((mark) => !mark.startsWith(_linkMark)), if (want[at] case final link?) '$_linkMark$link'}),
  ];
  return node.copyTextNodeWith(text: attributedOf(_joined(letters)));
}

/// [letters] joined into runs of the same marks.
List<(String, Set<String>)> _joined(List<(String, Set<String>)> letters) {
  final runs = <(String, Set<String>)>[];
  for (final (letter, marks) in letters) {
    final last = runs.lastOrNull;
    if (last != null && last.$2.length == marks.length && last.$2.containsAll(marks)) {
      runs.last = (last.$1 + letter, last.$2);
    } else {
      runs.add((letter, marks));
    }
  }
  return runs;
}

/// The link on the letter at [offset] in [documentText] of [nodes], or null. A line's end is no link.
String? linkAt(List<DocumentNode> nodes, int offset) {
  if (offset < 0) return null;
  var start = 0;
  for (final node in nodes) {
    final length = node is TextNode ? node.text.length : 1;
    if (offset < start + length) {
      if (node is! TextNode) return null;
      final link = node.text.getAllAttributionsAt(offset - start).whereType<LinkAttribution>().firstOrNull;
      return link?.plainTextUri;
    }
    if (offset == start + length) return null;
    start += length + 1;
  }
  return null;
}

/// Where the link at [offset] in [documentText] of [nodes] starts and ends: the run of letters with the same link.
TextRange? linkRunAt(List<DocumentNode> nodes, int offset) {
  final link = linkAt(nodes, offset) ?? linkAt(nodes, offset - 1);
  if (link == null) return null;
  var start = offset, end = offset;
  while (start > 0 && linkAt(nodes, start - 1) == link) {
    start--;
  }
  while (linkAt(nodes, end) == link) {
    end++;
  }
  return TextRange(start: start, end: end);
}

/// The link under a tap at [position], or null. A tap on a letter's right half gives the place after that letter,
/// upstream, so the letter before it is the one tapped: the link's last letter opens it, and the space before a link
/// does not.
String? linkAtPosition(List<DocumentNode> nodes, TextPosition position) =>
  linkAt(nodes, position.affinity == TextAffinity.upstream ? position.offset - 1 : position.offset);

/// The link at [position] in a node, as a tap there gives it: the letter after the place, or before it upstream.
String? linkAtDocumentPosition(List<DocumentNode> nodes, DocumentPosition position, {TextAffinity? affinity}) {
  final offset = offsetAt(nodes, position);
  if (offset == null) return null;
  final upstream = affinity ?? (position.nodePosition is TextNodePosition
    ? (position.nodePosition as TextNodePosition).affinity : TextAffinity.downstream);
  return linkAtPosition(nodes, TextPosition(offset: offset, affinity: upstream));
}
