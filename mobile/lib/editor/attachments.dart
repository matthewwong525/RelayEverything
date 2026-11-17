import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/rendering.dart' show RenderMetaData;
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import 'markdown.dart';

/// Marks a file's block on the screen, so a tap on it can be told from a tap on the note's words.
const _fileMark = #noteFile;

/// The letter an embed is in the editor's plain words.
const embedLetter = '\uFFFC';

/// Whether [position] on the screen is on a file's block: the block takes the tap, such as *Play*, not the editor.
bool isOnAttachment(BuildContext context, Offset position) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, position, View.of(context).viewId);
  return result.path.any((entry) => switch (entry.target) {
    RenderMetaData(metaData: _fileMark) => true,
    _ => false,
  });
}

/// Each file embed in [delta], with where it is in the note.
Iterable<(int, NoteAttachment)> attachmentsIn(Delta delta) sync* {
  var offset = 0;
  for (final op in delta.toList()) {
    if (op.data case final Map<dynamic, dynamic> embed) {
      if (NoteAttachment.fromEmbed(embed) case final file?) yield (offset, file);
    }
    offset += op.length ?? 0;
  }
}

/// The ids of the files placed in [delta].
Set<String> attachmentIdsIn(Delta delta) => {for (final (_, file) in attachmentsIn(delta)) file.id};

/// The change that puts [files] in [document], each on a line of its own, and where the cursor goes after them. At
/// [at], the cursor, they go on its line when it is empty, else under it; with no cursor, or on the last line, they go
/// at the end. An empty line always stays under the last file, to type in.
({Delta change, int caret}) placeFiles(Document document, List<NoteAttachment> files, int? at) {
  final text = document.toPlainText();
  final last = text.length - 1;
  final from = at == null ? last : at.clamp(0, last);
  final start = from == 0 ? 0 : text.lastIndexOf('\n', from - 1) + 1;
  final end = text.indexOf('\n', start);
  final change = Delta();
  if (start == end || (at != null && end < last)) {
    // An empty line takes them and stays under them; another line keeps them under it.
    change.retain(start == end ? start : end + 1);
    _insert(change, files);
    return (change: change, caret: (start == end ? start : end + 1) + files.length * 2);
  }
  // The last line has words or a block: a new line ends it, and the old line end comes after, with no line style.
  final lineStyle = _lineStyleAt(document, last);
  change
    ..retain(last)
    ..insert('\n', lineStyle.isEmpty ? null : lineStyle);
  _insert(change, files);
  if (lineStyle.isNotEmpty) change.retain(1, {for (final key in lineStyle.keys) key: null});
  return (change: change, caret: last + 1 + files.length * 2);
}

/// The change that puts each file in [document] back on a line of its own, as a paste beside one can leave it: words
/// before a file end their line, in its style, and words after it start a new line. Null when each file has its line.
/// A file's line holds the file alone, so the words would be lost when the note is kept.
Delta? filesApartChange(Document document) {
  final text = document.toPlainText();
  final breaks = <int, bool>{};
  for (final (at, _) in attachmentsIn(document.toDelta())) {
    if (at > 0 && text[at - 1] != '\n') breaks[at] = (breaks[at] ?? true) && text[at - 1] != embedLetter;
    if (at + 1 < text.length && text[at + 1] != '\n') breaks[at + 1] = false;
  }
  if (breaks.isEmpty) return null;
  final change = Delta();
  var done = 0;
  for (final at in breaks.keys.toList()..sort()) {
    final style = breaks[at]! ? _lineStyleAt(document, at) : const <String, dynamic>{};
    change
      ..retain(at - done)
      ..insert('\n', style.isEmpty ? null : style);
    done = at;
  }
  return change;
}

Delta _insert(Delta change, List<NoteAttachment> files) {
  for (final file in files) {
    change
      ..insert({attachmentEmbed: file.toJson()})
      ..insert('\n');
  }
  return change;
}

Map<String, dynamic> _lineStyleAt(Document document, int at) => {
  for (final attribute in document.collectStyle(at, 0).attributes.values)
    if (attribute.scope == AttributeScope.block) attribute.key: attribute.value,
};

/// [delta] with [top] first and [rest] at the end, as an older note shows them, and an empty line last.
Delta withFilesPlaced(Delta delta, {List<NoteAttachment> top = const [], List<NoteAttachment> rest = const []}) {
  final document = Document.fromDelta(delta);
  if (rest.isNotEmpty) document.compose(placeFiles(document, rest, null).change, ChangeSource.local);
  if (top.isNotEmpty) document.compose(_insert(Delta(), top), ChangeSource.local);
  final text = document.toPlainText();
  // A file on the last line leaves nowhere to type under it.
  if (attachmentsIn(document.toDelta()).lastOrNull?.$1 == text.length - 2) {
    document.compose(Delta()..retain(text.length - 1)..insert('\n'), ChangeSource.local);
  }
  return document.toDelta();
}

/// Shows each file embed as [blockOf] draws it, or nothing for a file the note no longer has.
class AttachmentEmbedBuilder extends EmbedBuilder {
  const AttachmentEmbedBuilder(this.blockOf);

  final Widget? Function(NoteAttachment file) blockOf;

  @override
  String get key => attachmentEmbed;

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final file = NoteAttachment.fromEmbed({attachmentEmbed: embedContext.node.value.data});
    final block = file == null ? null : blockOf(file);
    if (block == null) return const SizedBox.shrink();
    return MetaData(key: ValueKey('file ${file!.id}'), metaData: _fileMark, behavior: HitTestBehavior.translucent,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: block));
  }
}
