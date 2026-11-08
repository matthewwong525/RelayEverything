import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../brand.dart';
import '../editor/markdown.dart' show dashedList;
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

/// Over the keyboard while the person edits: *Text styles*, *Checklist* and *Attach*.
class FloatingToolBar extends StatelessWidget {
  const FloatingToolBar({super.key, required this.onStyles, required this.onChecklist, required this.onAttach});

  final VoidCallback onStyles;
  final VoidCallback onChecklist;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) => _FrostedPill(children: [
    PillIconButton(icon: CupertinoIcons.textformat, tooltip: 'Text styles', onPressed: onStyles),
    PillIconButton(icon: CupertinoIcons.checkmark_circle, tooltip: 'Checklist', onPressed: onChecklist),
    PillIconButton(icon: CupertinoIcons.paperclip, tooltip: 'Attach', onPressed: onAttach),
  ]);
}

/// At the bottom while the person reads: *Checklist* and *Attach* in a pill, and the round compose button.
class ReadingBar extends StatelessWidget {
  const ReadingBar({super.key, required this.onChecklist, required this.onAttach, required this.onCompose});

  final VoidCallback onChecklist;
  final VoidCallback? onAttach;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) => Row(children: [
    _FrostedPill(children: [
      PillIconButton(icon: CupertinoIcons.checkmark_circle, tooltip: 'Checklist', onPressed: onChecklist),
      PillIconButton(icon: CupertinoIcons.paperclip, tooltip: 'Attach', onPressed: onAttach),
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
void toggleList(QuillController controller, String kind) {
  final now = controller.getSelectionStyle().attributes[Attribute.list.key]?.value;
  controller.formatSelection(kind == now ? Attribute.clone(Attribute.list, null) : ListAttribute(kind));
}

/// *Text styles*, in the keyboard's place: a line's style, bold, italic, underline and strikethrough for the words
/// picked, the three lists, a quote, and indent in and out. ✕ brings the keyboard back.
class FormatSheet extends StatelessWidget {
  const FormatSheet({super.key, required this.controller, required this.height, required this.onClose});

  final QuillController controller;
  final double height;
  final VoidCallback onClose;

  bool _has(Attribute attribute) => controller.getSelectionStyle().attributes[attribute.key]?.value == attribute.value;

  void _toggle(Attribute attribute) =>
    controller.formatSelection(_has(attribute) ? Attribute.clone(attribute, null) : attribute);

  /// A line's style: one header level, Monostyled, or Body, which takes both off.
  void _line(Attribute? header) {
    controller.formatSelection(Attribute.clone(Attribute.codeBlock, null));
    controller.formatSelection(header ?? Attribute.clone(Attribute.header, null));
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final header = controller.getSelectionStyle().attributes[Attribute.header.key]?.value;
    final mono = _has(Attribute.codeBlock);
    Widget lineChip(String label, Attribute? style) {
      final on = !mono && header == style?.value;
      return ChoiceChip(label: Text(label), selected: on, showCheckmark: false, onSelected: (_) => _line(style),
        selectedColor: brand.accentSoft);
    }
    Widget toggle(IconData icon, String tooltip, Attribute attribute) => IconButton(tooltip: tooltip, icon: Icon(icon),
      isSelected: _has(attribute), onPressed: () => _toggle(attribute));
    Widget list(IconData icon, String tooltip, String kind) => IconButton(tooltip: tooltip, icon: Icon(icon),
      isSelected: controller.getSelectionStyle().attributes[Attribute.list.key]?.value == kind,
      onPressed: () => toggleList(controller, kind));
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
                ChoiceChip(label: const Text('Monostyled', style: TextStyle(fontFamily: 'monospace')), selected: mono,
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
                  onPressed: () => controller.indentSelection(false)),
                IconButton(tooltip: 'Indent more', icon: const Icon(CupertinoIcons.increase_indent),
                  onPressed: () => controller.indentSelection(true)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
