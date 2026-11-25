import 'dart:math' show max;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../editor/markdown.dart' show LineKind, highlightColours;
import '../editor/note_commands.dart';
import '../editor/shortcuts.dart';
import '../editor/web_note/cover.dart';
import '../editor/web_note/web_note.dart';
import 'more_menu.dart';
import 'round_button.dart';

/// A round, frosted pill of buttons, as Apple Notes floats its tool bar: the page shows through, blurred.
class _FrostedPill extends StatelessWidget {
  const _FrostedPill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _Frost(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(mainAxisSize: MainAxisSize.min, children: children)));
}

/// The frosted, round fill of a floating bar.
class _Frost extends StatelessWidget {
  const _Frost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: const ShapeBorderClipper(shape: StadiumBorder()),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: brandOf(context).card.withValues(alpha: 0.8), shape: const StadiumBorder()),
        child: child,
      ),
    ),
  );
}

/// The name of each highlight colour, as the colour row says it.
const colourNames = {'purple': 'Purple', 'pink': 'Pink', 'orange': 'Orange', 'green': 'Green', 'blue': 'Blue'};

/// The colour a highlight draws in a note, strong enough to see and soft enough to read the words through, in light
/// and dark.
Color highlightColourOf(String colour, Brightness brightness) {
  final base = switch (colour) {
    'pink' => const Color(0xFFE5508C),
    'orange' => const Color(0xFFF5A524),
    'green' => const Color(0xFF2FB37A),
    'blue' => const Color(0xFF3B82F6),
    _ => const Color(0xFF9B6BE0),
  };
  return base.withValues(alpha: brightness == Brightness.dark ? 0.45 : 0.3);
}

/// Picks photos ([photos] true) or any files for a note.
typedef AttachPick = void Function({required bool photos});

/// *Attach*, the paperclip: on the phone a small menu opens beside it, *Photos* or *Files*, not a sheet from the bottom
/// of the screen. With no [menu], as in the browser, which has one picker for every kind of file, a tap picks files.
/// With no [onPick], such as on a note from elsewhere, it is off.
class AttachButton extends StatelessWidget {
  const AttachButton({super.key, required this.onPick, this.menu = true});

  final AttachPick? onPick;
  final bool menu;

  @override
  Widget build(BuildContext context) {
    final pick = onPick;
    if (pick == null || !menu) {
      return PillIconButton(icon: CupertinoIcons.paperclip, tooltip: 'Attach',
        onPressed: pick == null ? null : () => pick(photos: false));
    }
    return MoreMenu(
      items: [
        ('Photos', CupertinoIcons.photo, () => pick(photos: true)),
        ('Files', CupertinoIcons.doc, () => pick(photos: false)),
      ],
      builder: (context, toggle) => PillIconButton(icon: CupertinoIcons.paperclip, tooltip: 'Attach', onPressed: toggle),
    );
  }
}

/// *Record*: the microphone, which records into the open note. Null [onRecord] shows none, as in the browser, on the
/// Mac, on a note from elsewhere and on a deleted note.
Widget? _recordButton(VoidCallback? onRecord) => onRecord == null ? null
  : PillIconButton(icon: CupertinoIcons.mic, tooltip: 'Record', onPressed: onRecord);

/// *Table*: a new table at the cursor, or, with the cursor in a table, *Convert to text* and *Delete table*.
class TableButton extends StatelessWidget {
  const TableButton({super.key, required this.onAdd, this.inTable = false, this.onConvert, this.onDelete});

  final VoidCallback? onAdd;
  final bool inTable;
  final VoidCallback? onConvert;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    if (!inTable) return PillIconButton(icon: CupertinoIcons.table, tooltip: 'Table', onPressed: onAdd);
    return MoreMenu(
      items: [('Convert to text', CupertinoIcons.doc_plaintext, onConvert ?? () {})],
      destructive: ('Delete table', CupertinoIcons.trash, onDelete ?? () {}),
      builder: (context, toggle) => PillIconButton(icon: CupertinoIcons.table, tooltip: 'Table', onPressed: toggle),
    );
  }
}

/// A frosted bar as wide as the screen whose buttons scroll sideways, as Apple's bar over the keyboard does. Buttons
/// that fit share the width; else each takes a slot so that 4 and a half show, and part of the next one shows at the edge.
class _ScrollingBar extends StatelessWidget {
  const _ScrollingBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _Frost(child: SizedBox(height: 44, child: LayoutBuilder(builder: (context, size) {
    final width = size.maxWidth;
    final slot = children.length * 44 <= width ? width / children.length : max(44.0, width / 4.5);
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      children: [for (final child in children) SizedBox(width: slot, child: Center(child: child))],
    );
  })));
}

/// Over the keyboard while the person edits, as wide as the screen: *Text styles*, *Checklist*, *Table*, *Attach* and,
/// on a phone, *Record*, then, by a swipe, *Bulleted list*, *Numbered list*, *Link*, *Indent less*, *Indent more* and
/// *Hide keyboard*. A null action shows its button off, as the styles are in a table's cell.
class FloatingToolBar extends StatelessWidget {
  const FloatingToolBar({super.key, required this.onStyles, required this.onChecklist, required this.table,
    required this.onAttach, this.attachMenu = true, this.onList, this.onLink, this.onIndent, this.onHideKeyboard,
    this.onRecord});

  final VoidCallback? onStyles;
  final VoidCallback? onChecklist;
  /// *Table*, which opens its menu with the cursor in a table.
  final Widget table;
  final AttachPick? onAttach;
  /// *Attach* opens *Photos* and *Files*; false in the browser.
  final bool attachMenu;
  final void Function(LineKind kind)? onList;
  final VoidCallback? onLink;
  final void Function(bool more)? onIndent;
  final VoidCallback? onHideKeyboard;
  /// *Record*, on a phone only.
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    final list = onList, indent = onIndent;
    // One ordered list: a new tool, such as *Record*, takes its place in it, after *Attach*.
    return _ScrollingBar(children: [
      PillIconButton(icon: CupertinoIcons.textformat, tooltip: 'Text styles', onPressed: onStyles),
      PillIconButton(icon: CupertinoIcons.checkmark_circle, tooltip: 'Checklist', onPressed: onChecklist),
      table,
      AttachButton(onPick: onAttach, menu: attachMenu),
      ?_recordButton(onRecord),
      PillIconButton(icon: CupertinoIcons.list_bullet, tooltip: 'Bulleted list',
        onPressed: list == null ? null : () => list(LineKind.bullet)),
      PillIconButton(icon: CupertinoIcons.list_number, tooltip: 'Numbered list',
        onPressed: list == null ? null : () => list(LineKind.numbered)),
      PillIconButton(icon: CupertinoIcons.link, tooltip: 'Link', onPressed: onLink),
      PillIconButton(icon: CupertinoIcons.decrease_indent, tooltip: 'Indent less',
        onPressed: indent == null ? null : () => indent(false)),
      PillIconButton(icon: CupertinoIcons.increase_indent, tooltip: 'Indent more',
        onPressed: indent == null ? null : () => indent(true)),
      PillIconButton(icon: CupertinoIcons.keyboard_chevron_compact_down, tooltip: 'Hide keyboard',
        onPressed: onHideKeyboard),
    ]);
  }
}

/// In the keyboard bar's place while words are selected: bold, italic, underline, strikethrough, *Highlight*, *Link*
/// and *Lists*, each lit when the words have it.
class SelectionToolBar extends StatelessWidget {
  const SelectionToolBar({super.key, required this.page, required this.colour, required this.onLink});

  final WebNote page;
  /// The highlight pen's colour.
  final String colour;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: page, builder: (context, _) {
    final format = NoteCommands(page);
    Widget toggle(IconData icon, String tooltip, String mark) => PillIconButton(icon: icon, tooltip: tooltip,
      selected: format.has(mark), onPressed: () => format.toggle(mark));
    final list = format.list;
    return _ScrollingBar(children: [
      toggle(CupertinoIcons.bold, 'Bold', 'bold'),
      toggle(CupertinoIcons.italic, 'Italic', 'italic'),
      toggle(CupertinoIcons.underline, 'Underline', 'underline'),
      toggle(CupertinoIcons.strikethrough, 'Strikethrough', 'strike'),
      PillIconButton(icon: CupertinoIcons.paintbrush, tooltip: 'Highlight', selected: format.highlight != null,
        onPressed: () => format.highlightWith(colour)),
      PillIconButton(icon: CupertinoIcons.link, tooltip: 'Link',
        selected: format.linked, onPressed: onLink),
      MoreMenu(
        items: [
          ('Bulleted List', CupertinoIcons.list_bullet, () => format.run(FormatAction.bulleted)),
          ('Dashed List', CupertinoIcons.list_dash, () => format.run(FormatAction.dashed)),
          ('Numbered List', CupertinoIcons.list_number, () => format.run(FormatAction.numbered)),
        ],
        builder: (context, toggle) => PillIconButton(icon: CupertinoIcons.list_bullet_indent, tooltip: 'Lists',
          selected: _isList(list), onPressed: toggle),
      ),
    ]);
  });
}

/// At the bottom while the person reads: *Checklist*, *Attach* and, on a phone, *Record* in a pill, and the round
/// compose button.
class ReadingBar extends StatelessWidget {
  const ReadingBar({super.key, required this.onChecklist, required this.onAttach, required this.onCompose,
    this.attachMenu = true, this.onRecord});

  final VoidCallback onChecklist;
  final AttachPick? onAttach;
  final VoidCallback onCompose;
  /// *Attach* opens *Photos* and *Files*; false in the browser.
  final bool attachMenu;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) => Row(children: [
    // The same order as the bar over the keyboard: a new tool, such as *Record*, goes after *Attach* here too.
    _FrostedPill(children: [
      PillIconButton(icon: CupertinoIcons.checkmark_circle, tooltip: 'Checklist', onPressed: onChecklist),
      AttachButton(onPick: onAttach, menu: attachMenu),
      ?_recordButton(onRecord),
    ]),
    const Spacer(),
    AccentGlow(child: RoundIconButton(icon: CupertinoIcons.square_pencil, tooltip: 'New note', onPressed: onCompose,
      accent: true, size: 52)),
  ]);
}

/// *Find in Note*, over the keyboard in the tool bar's place: the words to find, then *2 of 14* or *No matches*, clear,
/// up and down in a frosted pill, and ✓, which closes it.
class FindBar extends StatelessWidget {
  const FindBar({super.key, required this.controller, required this.focus, required this.onChanged, required this.found,
    required this.onStep, required this.onDone});

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onChanged;
  /// *2 of 14* or *No matches*; null while the field is empty.
  final String? found;
  /// Goes to the next match (1) or the one before (-1); null with no match.
  final void Function(int step)? onStep;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final step = onStep;
    return Row(spacing: 8, children: [
      Expanded(child: _FrostedPill(children: [
        Padding(padding: const EdgeInsets.only(left: 10, right: 6), child: Icon(CupertinoIcons.search, size: 20, color: brand.muted)),
        Expanded(child: TextField(controller: controller, focusNode: focus, onChanged: (_) => onChanged(),
          textInputAction: TextInputAction.search, onSubmitted: (_) => step?.call(1),
          // No outline or fill: the app's field look would draw a green box inside the pill when it has focus.
          decoration: const InputDecoration(hintText: 'Find in Note', isCollapsed: true, filled: false,
            border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none))),
        if (found case final found?) Text(found, style: TextStyle(fontSize: 13, color: brand.muted)),
        if (controller.text.isNotEmpty) PillIconButton(icon: CupertinoIcons.xmark_circle_fill, tooltip: 'Clear',
          onPressed: () {
            controller.clear();
            onChanged();
          }),
        PillIconButton(icon: CupertinoIcons.chevron_up, tooltip: 'Previous match', onPressed: step == null ? null : () => step(-1)),
        PillIconButton(icon: CupertinoIcons.chevron_down, tooltip: 'Next match', onPressed: step == null ? null : () => step(1)),
      ])),
      RoundIconButton(icon: CupertinoIcons.checkmark_alt, tooltip: 'Done', onPressed: onDone, accent: true),
    ]);
  }
}

/// The line styles the format tools offer, in their order, each with its look in the Format sheet and menu.
const lineStyles = <(String, FormatAction)>[
  ('Title', FormatAction.title), ('Heading', FormatAction.heading), ('Subheading', FormatAction.subheading),
  ('Body', FormatAction.body), ('Monostyled', FormatAction.monostyled),
];

/// How a line style's name looks in the Format sheet and menu: as the style itself, smaller.
TextStyle lineStyleLook(FormatAction style) => switch (style) {
  FormatAction.title => const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
  FormatAction.heading => const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
  FormatAction.subheading => const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  FormatAction.monostyled => const TextStyle(fontSize: 15, fontFamily: 'monospace'),
  _ => const TextStyle(fontSize: 15),
};

/// Whether [kind] is a bulleted, dashed or numbered list.
bool _isList(LineKind? kind) => kind == LineKind.bullet || kind == LineKind.dashed || kind == LineKind.numbered;

/// A colour dot: the highlight colour, ringed when it is the one in use.
class _ColourDot extends StatelessWidget {
  const _ColourDot({required this.colour, required this.tooltip, required this.onPressed, this.ringed = false});

  final String colour;
  final String tooltip;
  final VoidCallback onPressed;
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final fill = highlightColourOf(colour, Brightness.light).withValues(alpha: 1);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: BoxConstraints.tight(const Size.square(44)),
      isSelected: ringed ? true : null,
      icon: Container(width: 24, height: 24, decoration: BoxDecoration(color: fill, shape: BoxShape.circle,
        border: ringed ? Border.all(color: brand.ink, width: 2) : null)),
    );
  }
}

/// A group of buttons on one rounded fill, as Apple's Format sheet draws them.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: brandOf(context).paper, borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

/// *Text styles*, in the keyboard's place, in Apple's grouped look: the line styles, each in its own look; bold,
/// italic, underline and strikethrough; the highlight pen and its colour; the three lists, indent and block quote. ✕
/// brings the keyboard back.
class FormatSheet extends StatefulWidget {
  const FormatSheet({super.key, required this.page, required this.height, required this.onClose,
    this.colour = 'purple', this.onColour});

  final WebNote page;
  final double height;
  final VoidCallback onClose;
  /// The highlight pen's colour.
  final String colour;
  /// Keeps a new highlight colour.
  final void Function(String colour)? onColour;

  @override
  State<FormatSheet> createState() => _FormatSheetState();
}

class _FormatSheetState extends State<FormatSheet> {
  /// The row of colours shows over the sheet's lower rows.
  bool _colours = false;
  /// The pen's colour: a pick shows at once, before the page builds the sheet again.
  late String _colour = widget.colour;

  @override
  void didUpdateWidget(FormatSheet old) {
    super.didUpdateWidget(old);
    if (widget.colour != old.colour) _colour = widget.colour;
  }

  NoteCommands get _format => NoteCommands(widget.page);

  /// A new colour: kept, and on the words picked when they have a highlight.
  void _pick(String colour) {
    widget.onColour?.call(colour);
    _format.recolour(colour);
    setState(() {
      _colour = colour;
      _colours = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final format = _format;
    Widget toggle(IconData icon, String tooltip, String mark) => PillIconButton(icon: icon, tooltip: tooltip,
      selected: format.has(mark), onPressed: () => format.toggle(mark));
    Widget list(IconData icon, String tooltip, LineKind kind, FormatAction action) => PillIconButton(icon: icon,
      tooltip: tooltip, selected: format.list == kind, onPressed: () => format.run(action));
    return Material(
      color: brand.card,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: widget.height,
          child: ListenableBuilder(
            listenable: widget.page,
            builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), children: [
              Row(children: [
                Text('Format', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(tooltip: 'Close', icon: const Icon(CupertinoIcons.xmark), onPressed: widget.onClose),
              ]),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(spacing: 8, children: [
                for (final (label, style) in lineStyles)
                  ChoiceChip(label: Text(label, style: lineStyleLook(style)), selected: format.lineStyle == style,
                    showCheckmark: false, selectedColor: brand.accentSoft, onSelected: (_) => format.run(style)),
              ])),
              const SizedBox(height: 10),
              if (_colours)
                _Group(children: [
                  for (final colour in highlightColours)
                    _ColourDot(colour: colour, tooltip: colourNames[colour]!, ringed: colour == _colour,
                      onPressed: () => _pick(colour)),
                ])
              else ...[
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _Group(children: [
                    toggle(CupertinoIcons.bold, 'Bold', 'bold'),
                    toggle(CupertinoIcons.italic, 'Italic', 'italic'),
                    toggle(CupertinoIcons.underline, 'Underline', 'underline'),
                    toggle(CupertinoIcons.strikethrough, 'Strikethrough', 'strike'),
                  ]),
                  _Group(children: [
                    PillIconButton(icon: CupertinoIcons.paintbrush, tooltip: 'Highlight',
                      selected: format.highlight != null, onPressed: () => format.highlightWith(_colour)),
                    _ColourDot(colour: _colour, tooltip: 'Highlight colour',
                      onPressed: () => setState(() => _colours = true)),
                  ]),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _Group(children: [
                    list(CupertinoIcons.list_bullet, 'Bulleted list', LineKind.bullet, FormatAction.bulleted),
                    list(CupertinoIcons.list_dash, 'Dashed list', LineKind.dashed, FormatAction.dashed),
                    list(CupertinoIcons.list_number, 'Numbered list', LineKind.numbered, FormatAction.numbered),
                  ]),
                  _Group(children: [
                    PillIconButton(icon: CupertinoIcons.decrease_indent, tooltip: 'Indent less',
                      onPressed: () => format.run(FormatAction.indentLess)),
                    PillIconButton(icon: CupertinoIcons.increase_indent, tooltip: 'Indent more',
                      onPressed: () => format.run(FormatAction.indentMore)),
                  ]),
                  _Group(children: [PillIconButton(icon: CupertinoIcons.text_quote, tooltip: 'Block quote',
                    selected: format.kind == LineKind.quote, onPressed: () => format.run(FormatAction.quote))]),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// *Text styles* in the computer's top bar: a menu under its button, as Notes on a Mac has it. Bold, italic, underline,
/// strikethrough, the highlight pen and its colours at the top; then each line style and list in its own look, with ✓
/// at the current one; then Block Quote. A pick closes the menu, and the note keeps the cursor.
class FormatMenu extends StatefulWidget {
  const FormatMenu({super.key, required this.page, required this.onPick, required this.colour,
    required this.onColour, this.enabled = true});

  final WebNote page;
  /// Styles the note and gives it the cursor back.
  final void Function(FormatAction action) onPick;
  final String colour;
  final void Function(String colour) onColour;
  final bool enabled;

  @override
  State<FormatMenu> createState() => _FormatMenuState();
}

class _FormatMenuState extends State<FormatMenu> with CoversNote {
  final _menu = MenuController();
  /// The pen's colour: a pick rings at once, before the page builds the menu again.
  late String _colour = widget.colour;

  @override
  void didUpdateWidget(FormatMenu old) {
    super.didUpdateWidget(old);
    if (widget.colour != old.colour) _colour = widget.colour;
  }

  void _pick(FormatAction action) {
    _menu.close();
    widget.onPick(action);
  }

  /// A new colour: kept, and on the words picked when they have a highlight, as the Format sheet does.
  void _pickColour(String colour) {
    setState(() => _colour = colour);
    widget.onColour(colour);
    NoteCommands(widget.page).recolour(colour);
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    Widget tool(IconData icon, String tooltip, FormatAction action, {bool on = false}) =>
      PillIconButton(icon: icon, tooltip: tooltip, selected: on, onPressed: () => _pick(action));
    Widget item(String label, FormatAction action, TextStyle look, {required bool on}) => MenuItemButton(
      requestFocusOnHover: false,
      leadingIcon: SizedBox(width: 20, child: on ? Icon(CupertinoIcons.checkmark_alt, size: 18, color: brand.accentText) : null),
      onPressed: () => _pick(action),
      child: Text(label, style: look.copyWith(color: brand.ink)),
    );
    // Each part of the open menu follows the cursor, so its ✓ and lit tools move as the cursor does. The menu is part
    // of the note's tap region: a click in it never takes the cursor from the note.
    Widget live(Widget Function(NoteCommands format) part) => TextFieldTapRegion(child: ListenableBuilder(
      listenable: widget.page, builder: (context, _) => part(NoteCommands(widget.page))));
    return TextFieldTapRegion(child: MenuAnchor(
      controller: _menu,
      // Over the note's frame in the browser, the menu takes the clicks.
      onOpen: menuOpened,
      onClose: menuClosed,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(brand.card),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
      ),
      menuChildren: [
        live((format) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tool(CupertinoIcons.bold, 'Bold', FormatAction.bold, on: format.has('bold')),
            tool(CupertinoIcons.italic, 'Italic', FormatAction.italic, on: format.has('italic')),
            tool(CupertinoIcons.underline, 'Underline', FormatAction.underline, on: format.has('underline')),
            tool(CupertinoIcons.strikethrough, 'Strikethrough', FormatAction.strikethrough, on: format.has('strike')),
            tool(CupertinoIcons.paintbrush, 'Highlight', FormatAction.highlight, on: format.highlight != null),
          ],
        ))),
        TextFieldTapRegion(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final colour in highlightColours)
              _ColourDot(colour: colour, tooltip: colourNames[colour]!, ringed: colour == _colour,
                onPressed: () => _pickColour(colour)),
          ],
        ))),
        const Divider(height: 8),
        for (final (label, style) in lineStyles)
          live((format) => item(label, style, lineStyleLook(style),
            on: !_isList(format.list) && format.lineStyle == style)),
        for (final (label, action, kind) in _lists)
          live((format) => item(label, action, const TextStyle(fontSize: 15), on: format.list == kind)),
        const Divider(height: 8),
        live((format) => item('Block Quote', FormatAction.quote, const TextStyle(fontSize: 15),
          on: format.kind == LineKind.quote)),
      ],
      builder: (context, menu, _) => PillIconButton(icon: CupertinoIcons.textformat, tooltip: 'Text styles',
        onPressed: !widget.enabled ? null : () => menu.isOpen ? menu.close() : menu.open()),
    ));
  }

  static const _lists = [
    ('Bulleted List', FormatAction.bulleted, LineKind.bullet),
    ('Dashed List', FormatAction.dashed, LineKind.dashed),
    ('Numbered List', FormatAction.numbered, LineKind.numbered),
  ];
}
