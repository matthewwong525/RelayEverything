import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../brand.dart';
import '../editor/markdown.dart' show dashedList;
import 'more_menu.dart';
import 'round_button.dart';

/// A round, frosted pill of buttons, as Apple Notes floats its tool bar: the page shows through, blurred.
class _FrostedPill extends StatelessWidget {
  const _FrostedPill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: const ShapeBorderClipper(shape: StadiumBorder()),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: brandOf(context).card.withValues(alpha: 0.8), shape: const StadiumBorder()),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: children)),
      ),
    ),
  );
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

/// Over the keyboard while the person edits: *Text styles*, *Checklist* and *Attach*.
class FloatingToolBar extends StatelessWidget {
  const FloatingToolBar({super.key, required this.onStyles, required this.onChecklist, required this.onAttach,
    this.attachMenu = true});

  final VoidCallback onStyles;
  final VoidCallback onChecklist;
  final AttachPick? onAttach;
  /// *Attach* opens *Photos* and *Files*; false in the browser.
  final bool attachMenu;

  @override
  Widget build(BuildContext context) => _FrostedPill(children: [
    PillIconButton(icon: CupertinoIcons.textformat, tooltip: 'Text styles', onPressed: onStyles),
    PillIconButton(icon: CupertinoIcons.checkmark_circle, tooltip: 'Checklist', onPressed: onChecklist),
    AttachButton(onPick: onAttach, menu: attachMenu),
  ]);
}

/// At the bottom while the person reads: *Checklist* and *Attach* in a pill, and the round compose button.
class ReadingBar extends StatelessWidget {
  const ReadingBar({super.key, required this.onChecklist, required this.onAttach, required this.onCompose,
    this.attachMenu = true});

  final VoidCallback onChecklist;
  final AttachPick? onAttach;
  final VoidCallback onCompose;
  /// *Attach* opens *Photos* and *Files*; false in the browser.
  final bool attachMenu;

  @override
  Widget build(BuildContext context) => Row(children: [
    _FrostedPill(children: [
      PillIconButton(icon: CupertinoIcons.checkmark_circle, tooltip: 'Checklist', onPressed: onChecklist),
      AttachButton(onPick: onAttach, menu: attachMenu),
    ]),
    const Spacer(),
    AccentGlow(child: RoundIconButton(icon: CupertinoIcons.square_pencil, tooltip: 'New note', onPressed: onCompose,
      accent: true, size: 52)),
  ]);
}

/// The line styles *Text styles* offers, with the Delta attribute each sets.
final _lineStyles = <(String, Attribute?)>[
  ('Title', Attribute.h1), ('Heading', Attribute.h2), ('Subheading', Attribute.h3), ('Body', null),
];

/// Shows a list kind on [controller]'s lines: a second tap on the same kind takes it off.
/// The list style that turns [kind] on for the cursor's lines, or off when they have it.
Attribute listToggle(QuillController controller, String kind) {
  final now = controller.getSelectionStyle().attributes[Attribute.list.key]?.value;
  return kind == now ? Attribute.clone(Attribute.list, null) : ListAttribute(kind);
}

/// *Text styles*, in the keyboard's place: a line's style, bold, italic, underline and strikethrough for the words
/// picked, the three lists, a quote, and indent in and out. ✕ brings the keyboard back.
class FormatSheet extends StatelessWidget {
  const FormatSheet({super.key, required this.controller, required this.height, required this.onClose});

  final QuillController controller;
  final double height;
  final VoidCallback onClose;

  bool _has(Attribute attribute) => controller.getSelectionStyle().attributes[attribute.key]?.value == attribute.value;

  /// Styles one change without the editor bringing the keyboard back over the panel.
  void _format(Attribute attribute) => controller
    ..skipRequestKeyboard = true
    ..formatSelection(attribute)
    ..skipRequestKeyboard = false;

  void _indent(bool more) => controller
    ..skipRequestKeyboard = true
    ..indentSelection(more)
    ..skipRequestKeyboard = false;

  void _toggle(Attribute attribute) => _format(_has(attribute) ? Attribute.clone(attribute, null) : attribute);

  /// A line's style: one header level, Monostyled, or Body, which takes both off.
  void _line(Attribute? header) {
    _format(Attribute.clone(Attribute.codeBlock, null));
    _format(header ?? Attribute.clone(Attribute.header, null));
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    // Read on each draw, inside the builder below, so a style tap lights its chip at once.
    Widget lineChip(String label, Attribute? style) {
      final header = controller.getSelectionStyle().attributes[Attribute.header.key]?.value;
      final on = !_has(Attribute.codeBlock) && header == style?.value;
      return ChoiceChip(label: Text(label), selected: on, showCheckmark: false, onSelected: (_) => _line(style),
        selectedColor: brand.accentSoft);
    }
    Widget toggle(IconData icon, String tooltip, Attribute attribute) => IconButton(tooltip: tooltip, icon: Icon(icon),
      isSelected: _has(attribute), onPressed: () => _toggle(attribute));
    Widget list(IconData icon, String tooltip, String kind) => IconButton(tooltip: tooltip, icon: Icon(icon),
      isSelected: controller.getSelectionStyle().attributes[Attribute.list.key]?.value == kind,
      onPressed: () => _format(listToggle(controller, kind)));
    return Material(
      color: brand.card,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), children: [
              Row(children: [
                Text('Format', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(tooltip: 'Close', icon: const Icon(CupertinoIcons.xmark), onPressed: onClose),
              ]),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (label, style) in _lineStyles) lineChip(label, style),
                ChoiceChip(label: const Text('Monostyled', style: TextStyle(fontFamily: 'monospace')),
                  selected: _has(Attribute.codeBlock),
                  showCheckmark: false, selectedColor: brand.accentSoft,
                  onSelected: (_) => _toggle(Attribute.codeBlock)),
              ]),
              const SizedBox(height: 8),
              Wrap(children: [
                toggle(CupertinoIcons.bold, 'Bold', Attribute.bold),
                toggle(CupertinoIcons.italic, 'Italic', Attribute.italic),
                toggle(CupertinoIcons.underline, 'Underline', Attribute.underline),
                toggle(CupertinoIcons.strikethrough, 'Strikethrough', Attribute.strikeThrough),
              ]),
              Wrap(children: [
                list(CupertinoIcons.list_bullet, 'Bulleted list', 'bullet'),
                list(CupertinoIcons.list_dash, 'Dashed list', dashedList),
                list(CupertinoIcons.list_number, 'Numbered list', 'ordered'),
                toggle(CupertinoIcons.text_quote, 'Block quote', Attribute.blockQuote),
                IconButton(tooltip: 'Indent less', icon: const Icon(CupertinoIcons.decrease_indent),
                  onPressed: () => _indent(false)),
                IconButton(tooltip: 'Indent more', icon: const Icon(CupertinoIcons.increase_indent),
                  onPressed: () => _indent(true)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
