import 'markdown.dart';

// Where a note's files go in its words when the note opens. Later files go in through the editor page's `attach`, by
// the same rules.

/// The ids of the files placed in [blocks].
Set<String> attachmentIdsIn(Iterable<NoteBlock> blocks) => {for (final file in attachmentsIn(blocks)) file.id};

/// The ids of the files placed in the editor page's document [doc].
Set<String> attachmentIdsInDoc(Json doc) => {
  for (final node in (doc['content'] as List?) ?? const [])
    if (node is Map && node['type'] == 'attachment' && node['attrs'] is Map) '${(node['attrs'] as Map)['id']}',
};

NoteLine _emptyLine() => NoteLine(LineKind.paragraph, const []);

/// [blocks] with [files] in them, each a block of its own, and the place of the line the cursor goes to after them.
/// At [at], the cursor's block, they go in place of its line when it is empty, which stays under them, else under it;
/// with no cursor, or on the last line, they go at the end. An empty line always stays under the last file, to type in.
({List<NoteBlock> blocks, int caret}) placeFiles(List<NoteBlock> blocks, List<NoteAttachment> files, int? at) {
  final index = at == null || at < 0 || at >= blocks.length ? -1 : at;
  final from = index < 0 ? blocks.length - 1 : index;
  final placed = [for (final file in files) NoteFileBlock(file)];
  if (blocks.isEmpty) return (blocks: [...placed, _emptyLine()], caret: placed.length);
  final line = blocks[from];
  final empty = line is NoteLine && line.text.isEmpty;
  if (empty || (index >= 0 && from < blocks.length - 1)) {
    final to = empty ? from : from + 1;
    return (blocks: [...blocks.take(to), ...placed, ...blocks.skip(to)], caret: to + placed.length);
  }
  // The last line has words or a block: a new empty line comes after the files.
  final out = [...blocks, ...placed, _emptyLine()];
  return (blocks: out, caret: out.length - 1);
}

/// [blocks] with [top] first and [rest] at the end, as an older note shows them, and an empty line last.
List<NoteBlock> withFilesPlaced(List<NoteBlock> blocks,
    {List<NoteAttachment> top = const [], List<NoteAttachment> rest = const []}) {
  var placed = rest.isEmpty ? blocks : placeFiles(blocks, rest, null).blocks;
  placed = [for (final file in top) NoteFileBlock(file), ...placed];
  // A file on the last line leaves nowhere to type under it.
  if (placed.lastOrNull is NoteFileBlock) placed = [...placed, _emptyLine()];
  return placed;
}
