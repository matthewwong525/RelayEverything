import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextAffinity, TextSelection;
import 'package:super_editor/super_editor.dart';

import 'attachments.dart';
import 'markdown.dart';
import 'paste.dart' show deleteRange;

// The note page's editor: super_editor's document, composer and editor, with the note's own Undo and the line marks
// typed at the start of a line. The note's words also read as one text, each node a line and a table or a file one
// letter, so Find, links and tests count letters as they did.

/// The letter a table or a file takes in [documentText].
const blockLetter = '￼';

/// The words of [nodes] as one text: each node its line, ended by `\n`, and a table or a file one [blockLetter].
String documentText(Iterable<DocumentNode> nodes) =>
  nodes.map((node) => '${node is TextNode ? node.text.toPlainText(includePlaceholders: false) : blockLetter}\n').join();

int _lengthOf(DocumentNode node) => node is TextNode ? node.text.length : 1;

/// Where [offset] in [documentText] is in [nodes].
DocumentPosition positionAt(List<DocumentNode> nodes, int offset) {
  var start = 0;
  for (final node in nodes) {
    final length = _lengthOf(node);
    if (offset <= start + length || node == nodes.last) {
      final at = (offset - start).clamp(0, length);
      return DocumentPosition(nodeId: node.id, nodePosition: node is TextNode ? TextNodePosition(offset: at)
        : at == 0 ? const UpstreamDownstreamNodePosition.upstream() : const UpstreamDownstreamNodePosition.downstream());
    }
    start += length + 1;
  }
  throw StateError('An empty document');
}

/// Where [position] is in [documentText] of [nodes], or null when no node holds it.
int? offsetAt(List<DocumentNode> nodes, DocumentPosition position) {
  var start = 0;
  for (final node in nodes) {
    if (node.id == position.nodeId) {
      return start + switch (position.nodePosition) {
        TextNodePosition(:final offset) => min(offset, _lengthOf(node)),
        UpstreamDownstreamNodePosition(:final affinity) => affinity == TextAffinity.upstream ? 0 : 1,
        _ => 0,
      };
    }
    start += _lengthOf(node) + 1;
  }
  return null;
}

/// [selection] in [documentText] of [nodes]; collapsed at the start for none.
TextSelection textSelectionOf(List<DocumentNode> nodes, DocumentSelection? selection) {
  if (selection == null) return const TextSelection.collapsed(offset: -1);
  final base = offsetAt(nodes, selection.base), extent = offsetAt(nodes, selection.extent);
  if (base == null || extent == null) return const TextSelection.collapsed(offset: -1);
  return TextSelection(baseOffset: base, extentOffset: extent);
}

/// The document selection of [selection] in [documentText] of [nodes].
DocumentSelection documentSelectionOf(List<DocumentNode> nodes, TextSelection selection) => DocumentSelection(
  base: positionAt(nodes, max(selection.baseOffset, 0)), extent: positionAt(nodes, max(selection.extentOffset, 0)));

/// Puts [nodes] in the document in place of its own, keeping each node whose id stays.
class SetNoteNodesRequest implements EditRequest {
  const SetNoteNodesRequest(this.nodes);

  final List<DocumentNode> nodes;
}

class _SetNoteNodesCommand extends EditCommand {
  _SetNoteNodesCommand(this.nodes);

  final List<DocumentNode> nodes;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  String describe() => 'Set the note nodes';

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final ids = {for (final node in nodes) node.id};
    final changes = <EditEvent>[];
    for (final node in List.of(document)) {
      if (ids.contains(node.id)) continue;
      document.deleteNode(node.id);
      changes.add(DocumentEdit(NodeRemovedEvent(node.id, node)));
    }
    for (var at = 0; at < nodes.length; at++) {
      final node = nodes[at];
      final old = document.getNodeById(node.id);
      if (old == null) {
        document.insertNodeAt(at, node);
        changes.add(DocumentEdit(NodeInsertedEvent(node.id, at)));
        continue;
      }
      final from = document.getNodeIndexById(node.id);
      if (from != at) {
        document.moveNode(nodeId: node.id, targetIndex: at);
        changes.add(DocumentEdit(NodeMovedEvent(nodeId: node.id, from: from, to: at)));
      }
      if (identical(old, node)) continue;
      document.replaceNodeById(node.id, node);
      if (old.runtimeType == node.runtimeType) {
        changes.add(DocumentEdit(NodeChangeEvent(node.id)));
      } else {
        changes.addAll([DocumentEdit(NodeRemovedEvent(node.id, old)), DocumentEdit(NodeInsertedEvent(node.id, at))]);
      }
    }
    executor.logChanges(changes);
  }
}

/// The marks typed at the start of a line, and the line each makes, as Notes reads them.
const typedMarks = <String, LineKind>{
  '#': LineKind.header1, '##': LineKind.header2, '###': LineKind.header3, '-': LineKind.dashed, '*': LineKind.bullet,
  '1.': LineKind.numbered, '[]': LineKind.unchecked, '>': LineKind.quote,
};

/// The note's document at one time, for Undo.
typedef _Snapshot = ({List<DocumentNode> nodes, DocumentSelection? selection});

/// How long letters typed one after another stay one Undo step.
const _typingPause = Duration(milliseconds: 1000);

/// One open note's document, its selection and its Undo. Listeners hear each change of the words, and each change of
/// Undo and Redo, not a move of the cursor.
class NoteEditing extends ChangeNotifier {
  NoteEditing(List<DocumentNode> nodes) {
    document = MutableDocument(nodes: nodes.isEmpty ? [lineNode(LineKind.paragraph, AttributedText())] : nodes);
    composer = MutableDocumentComposer();
    editor = Editor(
      editables: {Editor.documentKey: document, Editor.composerKey: composer},
      requestHandlers: [
        (editor, request) => request is SetNoteNodesRequest ? _SetNoteNodesCommand(request.nodes) : null,
        ...defaultRequestHandlers,
      ],
      // The next letters typed take the styles of the letters at the cursor, as in Notes.
      reactionPipeline: [UpdateComposerTextStylesReaction(styleTypesToExtend: {...defaultExtendableTypes, HighlightAttribution}),
        _LineMarkReaction(this), _KeepFilesReaction(this)],
    );
    editor.addListener(FunctionalEditListener(_edited));
    _last = _snapshot();
  }

  /// Whether the note's files must stay: a note from elsewhere keeps them, as the server takes changes to them only
  /// from the phone that made it. A change that takes one away is undone at once.
  bool Function() keepFiles = () => false;

  /// The words in Markdown, read as [markdownToNodes] reads them.
  factory NoteEditing.markdown(String markdown, {bool title = false, Set<String>? files}) =>
    NoteEditing(markdownToNodes(markdown, title: title, files: files));

  late final MutableDocument document;
  late final MutableDocumentComposer composer;
  late final Editor editor;

  /// Tells of each change of the words, of the selection, and of the styles the next letters take: what the format
  /// tools light.
  late final Listenable looks = Listenable.merge([this, composer.selectionNotifier, composer.preferences]);

  /// The nodes now.
  List<DocumentNode> get nodes => List.of(document);

  /// The words as one text, as [documentText] counts them.
  String get text => documentText(document);

  /// The words as Markdown.
  String get markdown => documentToMarkdown(document);

  /// The selection in [text]; offset -1 when there is none.
  TextSelection get selection => textSelectionOf(nodes, composer.selection);

  set selection(TextSelection selection) => select(selection);

  /// Puts the selection at [selection] in [text].
  void select(TextSelection selection) => selectAt(documentSelectionOf(nodes, selection));

  /// Puts the selection at [selection]; null takes it away.
  void selectAt(DocumentSelection? selection) => editor.execute([
    ChangeSelectionRequest(selection, SelectionChangeType.placeCaret, SelectionReason.userInteraction),
  ]);

  /// The node the selection's extent is in.
  DocumentNode? get extentNode => switch (composer.selection) {
    final selection? => document.getNodeById(selection.extent.nodeId),
    null => null,
  };

  /// The text nodes the selection touches, in order.
  List<TextNode> get selectedTextNodes {
    final selection = composer.selection;
    if (selection == null) return const [];
    final all = nodes;
    final ids = [selection.base.nodeId, selection.extent.nodeId];
    final from = all.indexWhere((node) => ids.contains(node.id));
    final to = all.lastIndexWhere((node) => ids.contains(node.id));
    if (from < 0) return const [];
    return [for (final node in all.sublist(from, to + 1)) if (node is TextNode) node];
  }

  /// Puts [nodes] in place of the document's, as one Undo step unless [undoable] is false, with the selection then at
  /// [selection] when given.
  void setNodes(List<DocumentNode> nodes, {DocumentSelection? selection, bool undoable = true, bool keepSelection = false}) {
    if (nodes.isEmpty) nodes = [lineNode(LineKind.paragraph, AttributedText())];
    final now = composer.selection;
    final kept = keepSelection && now != null && nodes.any((node) => node.id == now.base.nodeId) &&
      nodes.any((node) => node.id == now.extent.nodeId);
    final to = selection ?? (kept ? now : null);
    if (!undoable) _quiet = true;
    editor.execute([
      SetNoteNodesRequest(nodes),
      if (to != null) ChangeSelectionRequest(to, SelectionChangeType.alteredContent, SelectionReason.contentChange)
      else if (!kept) const ClearSelectionRequest(),
    ]);
    _quiet = false;
  }

  /// Puts [text] in place of [length] letters at [start] in [this.text], as typing does: a `\n` starts a new line. The
  /// line break after a file takes the file with it, as Backspace on the line under a file does.
  void replaceText(int start, int length, String text) => _together(() => _replace(start, length, text));

  void _replace(int start, int length, String text) {
    if (length > 0) {
      final all = nodes;
      final words = this.text;
      if (length == 1 && words[start] == '\n' && start > 0 && words[start - 1] == blockLetter) {
        final file = positionAt(all, start - 1).nodeId;
        if (!removeBlock(file)) return;
      } else {
        final range = documentSelectionOf(all, TextSelection(baseOffset: start, extentOffset: start + length));
        final (nodes: kept, :caret) = deleteRange(all, DocumentRange(start: range.base, end: range.extent));
        breakTyping();
        setNodes(kept, selection: DocumentSelection.collapsed(position: caret));
      }
    }
    select(TextSelection.collapsed(offset: start));
    type(text);
  }

  /// Takes the file or table with [id] out of the note, with the cursor at the start of the line under it. False when
  /// the note keeps its files.
  bool removeBlock(String id) {
    final all = nodes;
    final at = all.indexWhere((node) => node.id == id);
    if (at < 0 || (all[at] is AttachmentNode && keepFiles())) return false;
    final rest = [...all.take(at), ...all.skip(at + 1)];
    if (rest.isEmpty) rest.add(lineNode(LineKind.paragraph, AttributedText()));
    final next = rest[min(at, rest.length - 1)];
    breakTyping();
    setNodes(rest, selection: DocumentSelection.collapsed(
      position: DocumentPosition(nodeId: next.id, nodePosition: next.beginningPosition)));
    return true;
  }

  /// Backspace at the start of a line under a file or a table takes it, as in Apple Notes. True when it did.
  bool backspaceTakesBlock() {
    final selection = composer.selection;
    if (selection == null || !selection.isCollapsed) return false;
    final at = selection.extent.nodePosition;
    if (at is! TextNodePosition || at.offset != 0) return false;
    final all = nodes;
    final index = all.indexWhere((node) => node.id == selection.extent.nodeId);
    if (index <= 0 || all[index - 1] is TextNode) return false;
    final block = all[index - 1];
    if (block is AttachmentNode && keepFiles()) return true;
    removeBlock(block.id);
    // The cursor stays at the start of its own line.
    selectAt(selection);
    return true;
  }

  /// Types [text] at the cursor, as a keyboard puts it in: the words between line breaks in one change each, and a
  /// `\n` as Return. A line mark such as `# ` turns into a style only when its space comes alone, as typed. At a file
  /// or a table, the words go on a new line before or after it.
  void type(String text) {
    final selection = composer.selection;
    if (selection != null && !selection.isCollapsed) {
      editor.execute([DeleteSelectionRequest(TextAffinity.downstream)]);
    }
    if (text.isNotEmpty) _lineBesideBlock();
    final lines = text.split('\n');
    for (var at = 0; at < lines.length; at++) {
      if (at > 0) editor.execute([InsertNewlineAtCaretRequest()]);
      if (lines[at].isNotEmpty) editor.execute([InsertPlainTextAtCaretRequest(lines[at])]);
    }
  }

  /// With the cursor at a file or a table, a new empty line before or after it, with the cursor in it.
  void _lineBesideBlock() {
    final selection = composer.selection;
    final at = selection?.extent.nodePosition;
    if (selection == null || at is! UpstreamDownstreamNodePosition) return;
    final all = nodes;
    final index = all.indexWhere((node) => node.id == selection.extent.nodeId);
    if (index < 0) return;
    final line = lineNode(LineKind.paragraph, AttributedText());
    final after = at.affinity == TextAffinity.downstream;
    breakTyping();
    setNodes([...all.take(after ? index + 1 : index), line, ...all.skip(after ? index + 1 : index)],
      selection: DocumentSelection.collapsed(position: DocumentPosition(nodeId: line.id,
        nodePosition: const TextNodePosition(offset: 0))));
  }

  // Undo: each step is the document and the selection before a change. super_editor's own history plays every change
  // again from the start, which tables, files and paste do not need; so the note keeps whole snapshots.
  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];
  late _Snapshot _last;
  String? _typingIn;
  DateTime _typedAt = DateTime(0);
  bool _restoring = false;
  bool _quiet = false;
  bool _marked = false;
  /// A change took a file the note keeps, and is being undone.
  bool _rejecting = false;

  bool get hasUndo => _undo.isNotEmpty;
  bool get hasRedo => _redo.isNotEmpty;

  _Snapshot _snapshot() => (nodes: List.of(document), selection: composer.selection);

  void _edited(List<EditEvent> changes) {
    if (_restoring) return;
    if (_rejecting) {
      _rejecting = false;
      _last = (nodes: _last.nodes, selection: composer.selection);
      return;
    }
    final edits = [for (final change in changes) if (change is DocumentEdit) change.change];
    if (edits.isEmpty) {
      _last = (nodes: _last.nodes, selection: composer.selection);
      return;
    }
    if (_quiet) {
      _last = _snapshot();
      notifyListeners();
      return;
    }
    final typing = !_marked && edits.every((edit) => edit is TextInsertionEvent || edit is TextDeletedEvent) &&
      edits.map(_nodeOf).toSet().length == 1;
    final now = DateTime.now();
    final joins = typing && _typingIn == _nodeOf(edits.first) && now.difference(_typedAt) < _typingPause;
    if (!joins) _undo.add(_last);
    _redo.clear();
    _typingIn = typing ? _nodeOf(edits.first) : null;
    _typedAt = now;
    _marked = false;
    _last = _snapshot();
    notifyListeners();
  }

  static String? _nodeOf(DocumentChange change) => change is NodeDocumentChange ? change.nodeId : null;

  /// Keeps the words now as their own Undo step, so the change that follows undoes alone: a line mark's change gives
  /// back the marks.
  void _checkpoint(String nodeId) {
    final now = _snapshot();
    if (_typingIn != nodeId || DateTime.now().difference(_typedAt) >= _typingPause) _undo.add(_last);
    _redo.clear();
    _last = now;
    _typingIn = null;
    _marked = true;
  }

  /// Ends the Undo step of letters being typed, so the next change is a step of its own.
  void breakTyping() => _typingIn = null;

  /// Runs [change] as one change: one Undo step, and listeners hear of it once, at the end.
  void _together(void Function() change) {
    final steps = _undo.length;
    _batch++;
    try {
      change();
    } finally {
      _batch--;
    }
    if (_undo.length > steps + 1) _undo.removeRange(steps + 1, _undo.length);
    if (_heldBack) {
      _heldBack = false;
      notifyListeners();
    }
  }

  int _batch = 0;
  bool _heldBack = false;

  @override
  void notifyListeners() {
    if (_batch > 0) {
      _heldBack = true;
    } else {
      super.notifyListeners();
    }
  }

  void undo() => _step(_undo, _redo);

  void redo() => _step(_redo, _undo);

  void _step(List<_Snapshot> from, List<_Snapshot> to) {
    if (from.isEmpty) return;
    to.add(_snapshot());
    final snapshot = from.removeLast();
    _restoring = true;
    editor.execute([
      SetNoteNodesRequest(snapshot.nodes),
      ChangeSelectionRequest(snapshot.selection, SelectionChangeType.alteredContent, SelectionReason.contentChange),
    ]);
    _restoring = false;
    _last = snapshot;
    _typingIn = null;
    notifyListeners();
  }

  /// Changes the document with [change] and, unless [undoSteps] is false, every Undo step with it too, so Undo never
  /// takes it back: a link found in the words, or a file put at its place.
  void changeEverywhere(List<DocumentNode>? Function(List<DocumentNode> nodes) change, {bool undoSteps = true}) {
    List<DocumentNode> each(List<DocumentNode> nodes) => change(nodes) ?? nodes;
    for (final list in [if (undoSteps) _undo, if (undoSteps) _redo]) {
      for (var at = 0; at < list.length; at++) {
        list[at] = (nodes: each(list[at].nodes), selection: list[at].selection);
      }
    }
    final now = change(nodes);
    if (now != null) setNodes(now, undoable: false, keepSelection: true);
    _last = _snapshot();
  }

  @override
  void dispose() {
    editor.dispose();
    composer.dispose();
    document.dispose();
    super.dispose();
  }
}

/// Turns the marks typed at the start of a line, such as `# `, into the line's style once the space is typed. The
/// line's other style goes; its indent stays. A code block keeps its marks as words. Undo gives back the marks.
class _LineMarkReaction extends EditReaction {
  _LineMarkReaction(this.editing);

  final NoteEditing editing;

  @override
  void react(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final edits = [for (final change in changeList) if (change is DocumentEdit) change.change];
    if (edits.length != 1) return;
    final typed = edits.single;
    if (typed is! TextInsertionEvent || typed.text.toPlainText() != ' ') return;
    final document = editorContext.document;
    final node = document.getNodeById(typed.nodeId);
    if (node is! TextNode || kindOf(node) == LineKind.code) return;
    final kind = typedMarks[node.text.toPlainText().substring(0, typed.offset)];
    if (kind == null) return;
    editing._checkpoint(node.id);
    final line = lineNode(kind, node.text.copyText(typed.offset + 1), indent: indentOf(node), id: node.id);
    requestDispatcher.execute([
      SetNoteNodesRequest([for (final each in document) each.id == node.id ? line : each]),
      ChangeSelectionRequest(DocumentSelection.collapsed(position: DocumentPosition(nodeId: node.id,
        nodePosition: const TextNodePosition(offset: 0))), SelectionChangeType.alteredContent, SelectionReason.contentChange),
    ]);
  }
}

/// Puts back a file a change took from a note that keeps its files, in the same change, so nothing is lost or kept.
/// A quiet change, such as a file the server no longer has leaving the words, is not the person's: it stays.
class _KeepFilesReaction extends EditReaction {
  _KeepFilesReaction(this.editing);

  final NoteEditing editing;

  @override
  void react(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    if (editing._restoring || editing._quiet || !editing.keepFiles()) return;
    final removed = [
      for (final change in changeList)
        if (change is DocumentEdit && change.change is NodeRemovedEvent) (change.change as NodeRemovedEvent).removedNode,
    ].whereType<AttachmentNode>();
    final now = attachmentIdsIn(editorContext.document);
    if (removed.every((node) => now.contains(node.file.id))) return;
    editing._rejecting = true;
    final before = editing._last;
    requestDispatcher.execute([
      SetNoteNodesRequest(before.nodes),
      ChangeSelectionRequest(before.selection, SelectionChangeType.alteredContent, SelectionReason.contentChange),
    ]);
  }
}
