import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/rendering.dart' show RenderMetaData;
import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import 'markdown.dart';

/// Marks a file's block on the screen, so a tap on it can be told from a tap on the note's words.
const _fileMark = #noteFile;

/// Whether [position] on the screen is on a file's block: the block takes the tap, such as *Play*, not the editor.
bool isOnAttachment(BuildContext context, Offset position) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, position, View.of(context).viewId);
  return result.path.any((entry) => switch (entry.target) {
    RenderMetaData(metaData: _fileMark) => true,
    _ => false,
  });
}

/// A note's file at its place in the words, a block of its own.
class AttachmentNode extends BlockNode {
  AttachmentNode({required this.id, required this.file, super.metadata}) {
    initAddToMetadata({NodeMetadata.blockType: const NamedAttribution('attachment')});
  }

  @override
  final String id;

  final NoteAttachment file;

  @override
  String? copyContent(dynamic selection) => null;

  @override
  bool hasEquivalentContent(DocumentNode other) => other is AttachmentNode && other.file == file;

  @override
  AttachmentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
    AttachmentNode(id: id, file: file, metadata: {...metadata, ...newProperties});

  @override
  AttachmentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
    AttachmentNode(id: id, file: file, metadata: newMetadata);

  AttachmentNode copy() => AttachmentNode(id: id, file: file, metadata: Map.of(metadata));

  @override
  bool operator ==(Object other) => identical(this, other) || other is AttachmentNode && other.id == id && other.file == file;

  @override
  int get hashCode => Object.hash(id, file);
}

/// The files placed in [nodes], in order.
Iterable<NoteAttachment> attachmentsIn(Iterable<DocumentNode> nodes) =>
  [for (final node in nodes) if (node is AttachmentNode) node.file];

/// The ids of the files placed in [nodes].
Set<String> attachmentIdsIn(Iterable<DocumentNode> nodes) => {for (final file in attachmentsIn(nodes)) file.id};

DocumentNode _fileNode(NoteAttachment file) => AttachmentNode(id: Editor.createNodeId(), file: file);

DocumentNode _emptyLine() => lineNode(LineKind.paragraph, AttributedText());

/// [nodes] with [files] in them, each a block of its own, and the node the cursor goes to after them. At [at], the
/// cursor's node, they go in place of its line when it is empty, which stays under them, else under it; with no
/// cursor, or on the last line, they go at the end. An empty line always stays under the last file, to type in.
({List<DocumentNode> nodes, String caret}) placeFiles(List<DocumentNode> nodes, List<NoteAttachment> files, String? at) {
  final index = at == null ? -1 : nodes.indexWhere((node) => node.id == at);
  final from = index < 0 ? nodes.length - 1 : index;
  final line = nodes[from];
  final empty = line is TextNode && line.text.isEmpty;
  final placed = [for (final file in files) _fileNode(file)];
  if (empty || (index >= 0 && from < nodes.length - 1)) {
    final to = empty ? from : from + 1;
    return (nodes: [...nodes.take(to), ...placed, ...nodes.skip(to)], caret: nodes[to].id);
  }
  // The last line has words or a block: a new empty line comes after the files.
  final last = _emptyLine();
  return (nodes: [...nodes, ...placed, last], caret: last.id);
}

/// [nodes] with [top] first and [rest] at the end, as an older note shows them, and an empty line last.
List<DocumentNode> withFilesPlaced(List<DocumentNode> nodes,
    {List<NoteAttachment> top = const [], List<NoteAttachment> rest = const []}) {
  var placed = rest.isEmpty ? nodes : placeFiles(nodes, rest, null).nodes;
  placed = [for (final file in top) _fileNode(file), ...placed];
  // A file on the last line leaves nowhere to type under it.
  if (placed.lastOrNull is AttachmentNode) placed = [...placed, _emptyLine()];
  return placed;
}

/// A table's or a file's block as the page lays it out: its node, and whether it is selected.
class NoteBlockViewModel extends SingleColumnLayoutComponentViewModel with SelectionAwareViewModelMixin {
  NoteBlockViewModel({required super.nodeId, required this.node, super.createdAt, super.maxWidth,
      super.padding = EdgeInsets.zero, super.opacity = 1.0, DocumentNodeSelection? selection,
      Color selectionColor = const Color(0x00000000)}) {
    super.selection = selection;
    super.selectionColor = selectionColor;
  }

  final DocumentNode node;

  @override
  NoteBlockViewModel copy() => NoteBlockViewModel(nodeId: nodeId, node: node, createdAt: createdAt, maxWidth: maxWidth,
    padding: padding, opacity: opacity, selection: selection, selectionColor: selectionColor);

  @override
  bool operator ==(Object other) => super == other && other is NoteBlockViewModel && identical(other.node, node);

  @override
  int get hashCode => super.hashCode ^ node.hashCode;
}

/// A block in the note's words, tinted while it is selected. Unlike super_editor's `SelectableBox`, it lets taps
/// through, so a file opens and a table cell takes the cursor.
class NoteBlockBox extends StatelessWidget {
  const NoteBlockBox({super.key, required this.viewModel, required this.child});

  final NoteBlockViewModel viewModel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selection = viewModel.selection?.nodeSelection;
    final picked = selection is UpstreamDownstreamNodeSelection && !selection.isCollapsed;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(color: picked ? viewModel.selectionColor.withValues(alpha: 0.5) : null),
      child: child,
    );
  }
}

/// Shows each file's block as [blockOf] draws it, or nothing for a file the note no longer has.
class AttachmentComponentBuilder implements ComponentBuilder {
  const AttachmentComponentBuilder(this.blockOf);

  final Widget? Function(NoteAttachment file) blockOf;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) =>
    node is AttachmentNode ? NoteBlockViewModel(nodeId: node.id, node: node) : null;

  @override
  Widget? createComponent(SingleColumnDocumentComponentContext componentContext,
      SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! NoteBlockViewModel) return null;
    final node = componentViewModel.node;
    if (node is! AttachmentNode) return null;
    final block = blockOf(node.file);
    return NoteBlockBox(
      viewModel: componentViewModel,
      child: BoxComponent(
        key: componentContext.componentKey,
        child: block == null ? const SizedBox(height: 1) : MetaData(key: ValueKey('file ${node.file.id}'),
          metaData: _fileMark, behavior: HitTestBehavior.translucent,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: block)),
      ),
    );
  }
}
