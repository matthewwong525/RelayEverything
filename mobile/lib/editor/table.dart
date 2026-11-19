import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/rendering.dart' show RenderMetaData;
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import '../brand.dart';
import '../screens/more_menu.dart';
import 'attachments.dart' show NoteBlockBox, NoteBlockViewModel;
import 'markdown.dart';
import 'note_editing.dart';

/// How long a cell waits after the last letter before its words go into the note: each pause is one Undo step.
const cellPause = Duration(milliseconds: 600);

/// The room a cell keeps under it when the page scrolls to it: the floating tool bar's, with a margin.
const _cellRoom = 84.0;

/// A cell of a table: its table's id, its row and its column.
typedef TableCellAt = ({String id, int row, int column});

/// Marks a table on the screen, so a tap on it can be told from a tap on the note's words.
const _tableMark = #noteTable;

/// Whether [position] on the screen is on a table. The editor sees each tap, also one in a cell, so it must leave
/// these to the cell, or it takes the cursor.
bool isOnTable(BuildContext context, Offset position) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, position, View.of(context).viewId);
  return result.path.any((entry) => switch (entry.target) {
    RenderMetaData(metaData: _tableMark) => true,
    _ => false,
  });
}

/// A table in a note, a block of its own.
class NoteTableNode extends BlockNode {
  NoteTableNode({required this.id, required this.table, super.metadata}) {
    initAddToMetadata({NodeMetadata.blockType: const NamedAttribution('noteTable')});
  }

  @override
  final String id;

  final NoteTable table;

  /// The same block with [table] in place of its own.
  NoteTableNode withTable(NoteTable table) => NoteTableNode(id: id, table: table, metadata: metadata);

  @override
  String? copyContent(dynamic selection) => table.text;

  @override
  bool hasEquivalentContent(DocumentNode other) => other is NoteTableNode && other.table.sameRows(table);

  @override
  NoteTableNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
    NoteTableNode(id: id, table: table, metadata: {...metadata, ...newProperties});

  @override
  NoteTableNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
    NoteTableNode(id: id, table: table, metadata: newMetadata);

  NoteTableNode copy() => NoteTableNode(id: id, table: table, metadata: Map.of(metadata));

  @override
  bool operator ==(Object other) => identical(this, other) || other is NoteTableNode && other.id == id &&
    identical(other.table, table);

  @override
  int get hashCode => Object.hash(id, table);
}

/// The tables in [nodes], in order.
Iterable<NoteTable> tablesIn(Iterable<DocumentNode> nodes) => [for (final node in nodes) if (node is NoteTableNode) node.table];

/// [node] with a new id for the table it holds, so a pasted copy of a table is a table of its own; any other [node] as
/// it is.
DocumentNode withNewTableId(DocumentNode node) =>
  node is NoteTableNode ? NoteTableNode(id: Editor.createNodeId(), table: node.table.withNewId()) : node;

/// The tables of one note page: the cell in use, the cell changes still to write, and the changes to the note's
/// tables, each as one change of the note, so one Undo takes each back. A table's cells are fields outside the editor,
/// so the page asks here whether the person edits a table.
class NoteTables extends ChangeNotifier {
  NoteTables(this.editing);

  final NoteEditing editing;

  /// The node a cell's keys go up to, outside the editor, so a key in a cell never reaches the editor's own keys.
  final keys = FocusNode(debugLabel: 'Table cells', canRequestFocus: false, skipTraversal: true);

  /// The cell in use. It stays while a handle's menu is open, and goes when the note's words take the cursor back.
  TableCellAt? get active => _active;
  TableCellAt? _active;

  /// The table to put the cursor in once it shows, as a new table does.
  String? _focusFirst;

  final _pending = <String, NoteTable>{};
  Timer? _pause;

  /// A cell took the cursor.
  void enter(TableCellAt cell) {
    if (cell == _active) return;
    _active = cell;
    notifyListeners();
  }

  /// The note's words, or nothing, took the cursor: no cell is in use.
  void leave() {
    flush();
    if (_active == null) return;
    _active = null;
    notifyListeners();
  }

  /// Keeps a cell's words, written to the note after [cellPause].
  void change(NoteTable table) {
    _pending[table.id] = table;
    _pause?.cancel();
    _pause = Timer(cellPause, flush);
  }

  /// Whether [id] has words not yet in the note.
  bool waits(String id) => _pending.containsKey(id);

  /// Writes each cell change still waiting into the note.
  void flush() {
    _pause?.cancel();
    final pending = [..._pending.values];
    _pending.clear();
    pending.forEach(write);
  }

  /// Puts [table] in the note in place of the table with its id, as one Undo step. Nothing happens when the note no
  /// longer holds it, such as after an Undo took it away.
  void write(NoteTable table) {
    _pending.remove(table.id);
    final nodes = editing.nodes;
    final at = _indexOf(nodes, table.id);
    if (at == null) return;
    editing.breakTyping();
    editing.setNodes([
      for (final node in nodes) node is NoteTableNode && node.table.id == table.id ? node.withTable(table) : node,
    ], keepSelection: true);
  }

  /// Where the table with [id] is in [nodes], or null.
  static int? _indexOf(List<DocumentNode> nodes, String id) {
    final at = nodes.indexWhere((node) => node is NoteTableNode && node.table.id == id);
    return at < 0 ? null : at;
  }

  /// Whether the note holds the table with [id].
  bool holds(String id) => _indexOf(editing.nodes, id) != null;

  /// *Table*: a table of 2 columns and 2 rows at the cursor, on its own line, with the cursor in its first cell. Words
  /// after the cursor go to a line under the table, and an empty line stays under it to type in.
  void insert() {
    flush();
    final nodes = editing.nodes;
    final selection = editing.composer.selection;
    final at = selection == null ? nodes.length - 1
      : max(0, nodes.indexWhere((node) => node.id == selection.extent.nodeId));
    final node = nodes[at];
    final table = NoteTable.empty();
    final block = NoteTableNode(id: Editor.createNodeId(), table: table);
    final offset = switch (selection?.extent.nodePosition) {
      TextNodePosition(:final offset) => offset,
      _ => null,
    };
    List<DocumentNode> placed;
    if (node is TextNode && offset != null && offset > 0) {
      final after = lineNode(kindOf(node), node.text.copyText(offset), indent: indentOf(node));
      placed = [...nodes.take(at), node.copyTextNodeWith(text: node.text.copyText(0, offset)), block, after,
        ...nodes.skip(at + 1)];
    } else if (node is TextNode && offset == 0) {
      placed = [...nodes.take(at), block, ...nodes.skip(at)];
    } else {
      placed = [...nodes.take(at + 1), block, if (at == nodes.length - 1) lineNode(LineKind.paragraph, AttributedText()),
        ...nodes.skip(at + 1)];
    }
    _focusFirst = table.id;
    editing.breakTyping();
    editing.setNodes(placed);
    _active = (id: table.id, row: 0, column: 0);
    notifyListeners();
  }

  /// Whether the table with [id] has just been added and waits for the cursor; asked once.
  bool takeFocusFirst(String id) {
    if (_focusFirst != id) return false;
    _focusFirst = null;
    return true;
  }

  /// *Convert to text*: the table in use becomes lines of its cells' words, split by tabs. Returns the node where the
  /// words start, for the cursor, or null with no table in use.
  String? convertActive() {
    final id = _active?.id;
    if (id == null) return null;
    flush();
    final nodes = editing.nodes;
    final at = _indexOf(nodes, id);
    _active = null;
    if (at == null) return null;
    final table = (nodes[at] as NoteTableNode).table;
    final lines = [for (final row in table.rows) lineNode(LineKind.paragraph, AttributedText(row.join('\t')))];
    if (lines.isEmpty) lines.add(lineNode(LineKind.paragraph, AttributedText()));
    editing.breakTyping();
    editing.setNodes([...nodes.take(at), ...lines, ...nodes.skip(at + 1)], selection: DocumentSelection.collapsed(
      position: DocumentPosition(nodeId: lines.first.id, nodePosition: const TextNodePosition(offset: 0))));
    notifyListeners();
    return lines.first.id;
  }

  /// *Delete table*: the table in use goes. Returns the node the cursor goes to, or null with no table in use.
  String? deleteActive() {
    final id = _active?.id;
    if (id == null) return null;
    _pending.remove(id);
    flush();
    final nodes = editing.nodes;
    final at = _indexOf(nodes, id);
    _active = null;
    if (at == null) return null;
    // A table on the last line leaves an empty line.
    final rest = [...nodes.take(at), ...nodes.skip(at + 1)];
    if (at == nodes.length - 1) rest.add(lineNode(LineKind.paragraph, AttributedText()));
    final next = rest[min(at, rest.length - 1)];
    editing.breakTyping();
    editing.setNodes(rest, selection: DocumentSelection.collapsed(
      position: DocumentPosition(nodeId: next.id, nodePosition: next.beginningPosition)));
    notifyListeners();
    return next.id;
  }

  @override
  void dispose() {
    _pause?.cancel();
    keys.dispose();
    super.dispose();
  }
}

/// Draws each table of the note as a [NoteTableView].
class NoteTableComponentBuilder implements ComponentBuilder {
  const NoteTableComponentBuilder(this.tables, {this.readOnly = false, this.style});

  final NoteTables? tables;
  final bool readOnly;
  final TextStyle? style;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) =>
    node is NoteTableNode ? NoteBlockViewModel(nodeId: node.id, node: node) : null;

  @override
  Widget? createComponent(SingleColumnDocumentComponentContext componentContext,
      SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! NoteBlockViewModel) return null;
    final node = componentViewModel.node;
    if (node is! NoteTableNode) return null;
    return NoteBlockBox(
      viewModel: componentViewModel,
      child: BoxComponent(
        key: componentContext.componentKey,
        // Keyed by the table's id: a cell change puts a new node in, and the cell must keep the cursor.
        child: NoteTableView(key: ValueKey(node.table.id), table: node.table, tables: tables,
          readOnly: readOnly || tables == null, style: style),
      ),
    );
  }
}

/// A table in a note: a field for each cell in the note's text style, the head row bold, and sideways scroll when it is
/// wider than the page. While a cell has the cursor, a handle shows above its column and at the left of its row.
class NoteTableView extends StatefulWidget {
  const NoteTableView({super.key, required this.table, required this.tables, this.readOnly = false, this.style});

  final NoteTable table;
  final NoteTables? tables;
  final bool readOnly;
  final TextStyle? style;

  @override
  State<NoteTableView> createState() => _NoteTableViewState();
}

class _NoteTableViewState extends State<NoteTableView> {
  var _cells = <List<TextEditingController>>[];
  var _nodes = <List<FocusNode>>[];
  /// The cell to put the cursor in once the new rows show.
  (int, int)? _focusAfter;

  NoteTables? get _tables => widget.tables;
  String get _id => widget.table.id;

  @override
  void initState() {
    super.initState();
    _build(widget.table.rows);
    _tables?.addListener(_tablesChanged);
    if (_tables?.takeFocusFirst(_id) ?? false) _focusAfter = (0, 0);
    _focusSoon();
  }

  @override
  void didUpdateWidget(NoteTableView old) {
    super.didUpdateWidget(old);
    // A change from outside the cells, such as an Undo, shows in them; words still waiting keep their own.
    if ((_tables?.waits(_id) ?? false) || _sameRows(widget.table.rows)) return;
    final rows = widget.table.rows;
    if (rows.length != _cells.length || (rows.isNotEmpty && rows.first.length != _cells.first.length)) {
      _dispose();
      _build(rows);
    } else {
      for (var row = 0; row < rows.length; row++) {
        for (var column = 0; column < rows[row].length; column++) {
          final cell = _cells[row][column];
          final words = rows[row][column];
          if (cell.text != words) {
            cell.value = TextEditingValue(text: words, selection: TextSelection.collapsed(offset: words.length));
          }
        }
      }
    }
    _focusSoon();
  }

  bool _sameRows(List<List<String>> rows) =>
    rows.length == _cells.length && [
      for (var row = 0; row < rows.length; row++)
        rows[row].length == _cells[row].length &&
          [for (var column = 0; column < rows[row].length; column++) rows[row][column] == _cells[row][column].text]
            .every((same) => same),
    ].every((same) => same);

  void _build(List<List<String>> rows) {
    _cells = [for (final row in rows) [for (final words in row) TextEditingController(text: words)]];
    _nodes = [
      for (var row = 0; row < rows.length; row++)
        [for (var column = 0; column < rows[row].length; column++) _nodeFor(row, column)],
    ];
  }

  FocusNode _nodeFor(int row, int column) {
    final node = FocusNode(debugLabel: 'Cell $row, $column');
    node.addListener(() {
      if (node.hasFocus) {
        _tables?.enter((id: _id, row: row, column: column));
      } else {
        _tables?.flush();
      }
    });
    return node;
  }

  void _focusSoon() {
    final to = _focusAfter;
    if (to == null) return;
    _focusAfter = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final (row, column) = to;
      if (row < _nodes.length && column < _nodes[row].length) _nodes[row][column].requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _tablesChanged() {
    if (mounted) setState(() {});
  }

  void _dispose() {
    for (final cell in _cells.expand((row) => row)) {
      cell.dispose();
    }
    for (final node in _nodes.expand((row) => row)) {
      node.dispose();
    }
  }

  @override
  void dispose() {
    _tables?.removeListener(_tablesChanged);
    _dispose();
    super.dispose();
  }

  List<List<String>> get _rows => [for (final row in _cells) [for (final cell in row) cell.text]];

  int get _columns => _cells.isEmpty ? 0 : _cells.first.length;

  /// A new shape of the table, written at once as one Undo step, with the cursor then in [row], [column].
  void _reshape(List<List<String>> rows, int row, int column) {
    // The editor does not build its embeds again for a change that keeps the cursor out of its words, so the cells
    // take the new shape here. The old fields go after the cursor moves to the new ones.
    final cells = _cells, nodes = _nodes;
    setState(() => _build(rows));
    _focusAfter = (row, column);
    _focusSoon();
    _tables?.write(widget.table.withRows(rows));
    Future(() {
      for (final cell in cells.expand((row) => row)) {
        cell.dispose();
      }
      for (final node in nodes.expand((row) => row)) {
        node.dispose();
      }
    });
  }

  /// Return: the cell below, and a new row from the last row.
  void _down(int row, int column) {
    if (row + 1 < _cells.length) return _nodes[row + 1][column].requestFocus();
    _reshape([..._rows, List.filled(_columns, '')], row + 1, column);
  }

  /// Tab and Shift+Tab: the next cell or the one before, and a new row from the last cell.
  void _step(int row, int column, int by) {
    final at = row * _columns + column + by;
    if (at < 0) return;
    if (at >= _cells.length * _columns) return _reshape([..._rows, List.filled(_columns, '')], row + 1, 0);
    _nodes[at ~/ _columns][at % _columns].requestFocus();
  }

  void _addColumn(int at, int focus) => _reshape([
    for (final row in _rows) [...row.take(at), '', ...row.skip(at)],
  ], _tables?.active?.row ?? 0, focus);

  void _deleteColumn(int at) {
    if (_columns <= 1) return;
    _reshape([for (final row in _rows) [...row.take(at), ...row.skip(at + 1)]],
      _tables?.active?.row ?? 0, min(at, _columns - 2));
  }

  void _addRow(int at, int focus) =>
    _reshape([..._rows.take(at), List.filled(_columns, ''), ..._rows.skip(at)], focus, _tables?.active?.column ?? 0);

  void _deleteRow(int at) {
    if (_cells.length <= 1) return;
    _reshape([..._rows.take(at), ..._rows.skip(at + 1)], min(at, _cells.length - 2), _tables?.active?.column ?? 0);
  }

  /// Each column as wide as its longest words, from 100 to 280 points.
  List<double> _widths(TextStyle style) => [
    for (var column = 0; column < _columns; column++)
      [
        for (var row = 0; row < _cells.length; row++)
          (TextPainter(text: TextSpan(text: _cells[row][column].text,
            style: row == 0 ? style.copyWith(fontWeight: FontWeight.w600) : style),
            textDirection: TextDirection.ltr, maxLines: 1)..layout()).width + 20,
      ].fold(100.0, max).clamp(100.0, 280.0),
  ];

  static const _handle = 28.0;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final style = (widget.style ?? DefaultTextStyle.of(context).style).copyWith(height: 1.3);
    final widths = _widths(style);
    final active = _tables?.active;
    final here = active != null && active.id == _id && !widget.readOnly;
    final line = BorderSide(color: brand.muted.withValues(alpha: 0.35), width: 0.8);
    Widget cell(int row, int column) => DecoratedBox(
      decoration: BoxDecoration(
        color: row == 0 ? brand.card.withValues(alpha: 0.6) : null,
        border: Border(right: line, bottom: line, top: row == 0 ? line : BorderSide.none,
          left: column == 0 ? line : BorderSide.none),
      ),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: _field(row, column, style)),
    );
    final table = Table(
      defaultColumnWidth: const FixedColumnWidth(100),
      columnWidths: {
        if (here) 0: const FixedColumnWidth(_handle),
        for (var column = 0; column < _columns; column++) column + (here ? 1 : 0): FixedColumnWidth(widths[column]),
      },
      // Keyed, so the handles that come with the cursor never build the cells again: a cell keeps its keyboard.
      children: [
        if (here) TableRow(key: const ValueKey('handles'), children: [
          const SizedBox(key: ValueKey((-1, -1)), height: _handle),
          for (var column = 0; column < _columns; column++)
            KeyedSubtree(key: ValueKey((-1, column)), child: column == active.column
              ? Center(child: _columnHandle(column)) : const SizedBox(height: _handle)),
        ]),
        for (var row = 0; row < _cells.length; row++)
          TableRow(key: ValueKey(row), children: [
            if (here) TableCell(key: ValueKey((row, -1)), verticalAlignment: TableCellVerticalAlignment.middle,
              child: row == active.row ? _rowHandle(row) : const SizedBox.shrink()),
            for (var column = 0; column < _columns; column++)
              TableCell(key: ValueKey((row, column)), verticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
                child: cell(row, column)),
          ]),
      ],
    );
    return MetaData(metaData: _tableMark, behavior: HitTestBehavior.translucent, child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      // A cell's keys go up to the page, past the editor's own keys.
      child: Focus(parentNode: _tables?.keys, canRequestFocus: false, skipTraversal: true,
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: table)),
    ));
  }

  Widget _field(int row, int column, TextStyle style) {
    final field = TextField(
      controller: _cells[row][column],
      focusNode: _nodes[row][column],
      readOnly: widget.readOnly,
      style: row == 0 ? style.copyWith(fontWeight: FontWeight.w600) : style,
      maxLines: null,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.next,
      scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, _cellRoom),
      // A tap in the note's words moves the cursor there; a tap elsewhere keeps it in the cell.
      onTapOutside: (_) {},
      onChanged: (_) => _tables?.change(widget.table.withRows(_rows)),
      onEditingComplete: () {},
      onSubmitted: (_) => _down(row, column),
      decoration: const InputDecoration(isCollapsed: true, filled: false, border: InputBorder.none,
        enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
    );
    return CallbackShortcuts(bindings: {
      const SingleActivator(LogicalKeyboardKey.tab): () => _step(row, column, 1),
      const SingleActivator(LogicalKeyboardKey.tab, shift: true): () => _step(row, column, -1),
    }, child: field);
  }

  Widget _columnHandle(int column) => MoreMenu(
    items: [
      ('Add column before', CupertinoIcons.arrow_left_to_line, () => _addColumn(column, column)),
      ('Add column after', CupertinoIcons.arrow_right_to_line, () => _addColumn(column + 1, column + 1)),
    ],
    destructive: _columns > 1 ? ('Delete column', CupertinoIcons.trash, () => _deleteColumn(column)) : null,
    builder: (context, toggle) => _handleButton(CupertinoIcons.ellipsis, 'Column', toggle),
  );

  Widget _rowHandle(int row) => MoreMenu(
    items: [
      ('Add row above', CupertinoIcons.arrow_up_to_line, () => _addRow(row, row)),
      ('Add row below', CupertinoIcons.arrow_down_to_line, () => _addRow(row + 1, row + 1)),
    ],
    destructive: _cells.length > 1 ? ('Delete row', CupertinoIcons.trash, () => _deleteRow(row)) : null,
    builder: (context, toggle) => _handleButton(CupertinoIcons.ellipsis_vertical, 'Row', toggle),
  );

  Widget _handleButton(IconData icon, String tooltip, VoidCallback onPressed) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 16,
    padding: EdgeInsets.zero,
    constraints: BoxConstraints.tight(const Size.square(_handle)),
    color: brandOf(context).accentText,
    icon: Icon(icon),
  );
}
