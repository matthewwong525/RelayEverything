import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMetaData;
import 'package:super_editor/super_editor.dart';

import '../brand.dart';
import '../screens/note_bars.dart' show highlightColourOf;
import 'markdown.dart';

// How a note's words look on its page, as Apple Notes draws them: Title, Heading and Subheading larger and bold, Body
// at 17, lists with a dot, a dash, a number or a round circle, quotes with a bar, and code in a grey box. Each line
// keeps the same height, so a new line and a line inside an item are even.

/// The room each indent level takes.
const indentWidth = 28.0;

/// The room a list item's dot, dash, number or circle takes before its words.
const markWidth = 34.0;

/// The body text of a note.
TextStyle noteBodyStyle(BrandColors brand) =>
  TextStyle(fontFamily: brandFont, fontSize: 17, height: 1.5, color: brand.ink);

/// The note's styles for each kind of line, with [padding] round the words.
Stylesheet noteStylesheet(BuildContext context, {EdgeInsets padding = EdgeInsets.zero}) {
  final brand = brandOf(context);
  final brightness = Theme.of(context).brightness;
  TextStyle header(double size, FontWeight weight) => TextStyle(fontSize: size, fontWeight: weight, height: 1.3);
  return Stylesheet(
    documentPadding: padding,
    rules: [
      StyleRule(BlockSelector.all, (document, node) => {
        Styles.maxWidth: double.infinity,
        Styles.padding: const CascadingPadding.all(0),
        Styles.textStyle: noteBodyStyle(brand),
      }),
      StyleRule(const BlockSelector('header1'), (document, node) => {
        Styles.padding: const CascadingPadding.only(top: 4, bottom: 4),
        Styles.textStyle: header(28, FontWeight.w700),
      }),
      StyleRule(const BlockSelector('header2'), (document, node) => {
        Styles.padding: const CascadingPadding.only(top: 10, bottom: 4),
        Styles.textStyle: header(22, FontWeight.w700),
      }),
      StyleRule(const BlockSelector('header3'), (document, node) => {
        Styles.padding: const CascadingPadding.only(top: 8, bottom: 4),
        Styles.textStyle: header(19, FontWeight.w600),
      }),
      StyleRule(const BlockSelector('code'), (document, node) => {
        Styles.textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 15),
      }),
      StyleRule(const BlockSelector('blockquote'), (document, node) => {
        Styles.textStyle: TextStyle(color: brand.muted),
      }),
    ],
    inlineTextStyler: (attributions, style) => noteInlineStyle(attributions, style, brand, brightness),
  );
}

/// [style] with the inline styles of [attributions]: bold, italic, underline, strikethrough, a highlight and a link.
TextStyle noteInlineStyle(Set<Attribution> attributions, TextStyle style, BrandColors brand, Brightness brightness) {
  final lines = <TextDecoration>[];
  var out = style;
  for (final attribution in attributions) {
    if (attribution == boldAttribution) out = out.copyWith(fontWeight: FontWeight.w700);
    if (attribution == italicsAttribution) out = out.copyWith(fontStyle: FontStyle.italic);
    if (attribution == underlineAttribution) lines.add(TextDecoration.underline);
    if (attribution == strikethroughAttribution) lines.add(TextDecoration.lineThrough);
    if (attribution is HighlightAttribution) {
      out = out.copyWith(backgroundColor: highlightColourOf(attribution.colour, brightness));
    }
    if (attribution is LinkAttribution) {
      out = out.copyWith(color: brand.accentText, decorationColor: brand.accentText);
      if (!lines.contains(TextDecoration.underline)) lines.add(TextDecoration.underline);
    }
  }
  return lines.isEmpty ? out : out.copyWith(decoration: TextDecoration.combine(lines));
}

/// What shows before a line's words.
enum NoteMark { none, bullet, dashed, number, unchecked, checked }

/// A line of a note as the page lays it out: its words, its kind, its mark, and the words shown while the note is
/// empty.
class NoteLineViewModel extends ParagraphComponentViewModel {
  NoteLineViewModel({required super.nodeId, super.createdAt, required super.text, required super.textStyleBuilder,
      required super.selectionColor, super.blockType, super.indent, super.opacity, this.kind = LineKind.paragraph,
      this.number = 0, this.hint});

  LineKind kind;
  /// A numbered item's number.
  int number;
  /// The words that show in the empty line of an empty note.
  String? hint;

  NoteMark get mark => switch (kind) {
    LineKind.bullet => NoteMark.bullet,
    LineKind.dashed => NoteMark.dashed,
    LineKind.numbered => NoteMark.number,
    LineKind.unchecked => NoteMark.unchecked,
    LineKind.checked => NoteMark.checked,
    _ => NoteMark.none,
  };

  @override
  NoteLineViewModel copy() => internalCopy(NoteLineViewModel(nodeId: nodeId, createdAt: createdAt, text: text.copy(),
    textStyleBuilder: textStyleBuilder, selectionColor: selectionColor, opacity: opacity, kind: kind, number: number,
    hint: hint)) as NoteLineViewModel;

  @override
  bool operator ==(Object other) => super == other && other is NoteLineViewModel && other.kind == kind &&
    other.number == number && other.hint == hint;

  @override
  int get hashCode => super.hashCode ^ Object.hash(kind, number, hint);
}

/// Marks a checklist circle on the screen, so a tap on it ticks the line and leaves the cursor.
const _circleMark = #noteCircle;

/// Whether [position] on the screen is on a checklist circle.
bool isOnCircle(BuildContext context, Offset position) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, position, View.of(context).viewId);
  return result.path.any((entry) => switch (entry.target) {
    RenderMetaData(metaData: _circleMark) => true,
    _ => false,
  });
}

/// Draws each text line of a note: a paragraph, a heading, a quote, code, or a list item with its mark. [onTick]
/// ticks a checklist line, or is null where the note reads only. [hint] shows in an empty note's one line.
class NoteLineComponentBuilder implements ComponentBuilder {
  const NoteLineComponentBuilder({this.onTick, this.hint});

  final void Function(String nodeId, bool ticked)? onTick;
  final String? hint;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
    if (node is! TextNode) return null;
    final kind = kindOf(node);
    final number = kind == LineKind.numbered ? itemNumbers(document)[node.id] ?? 1 : 0;
    return NoteLineViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      blockType: node.getMetadataValue(NodeMetadata.blockType),
      indent: indentOf(node),
      text: node.text,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
      kind: kind,
      number: number,
      hint: hint != null && document.nodeCount == 1 && node.text.isEmpty ? hint : null,
    );
  }

  @override
  Widget? createComponent(SingleColumnDocumentComponentContext componentContext,
      SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! NoteLineViewModel) return null;
    return NoteLineComponent(key: componentContext.componentKey, viewModel: componentViewModel, onTick: onTick);
  }
}

/// One text line of a note on its page.
class NoteLineComponent extends StatefulWidget {
  const NoteLineComponent({super.key, required this.viewModel, this.onTick});

  final NoteLineViewModel viewModel;
  final void Function(String nodeId, bool ticked)? onTick;

  @override
  State<NoteLineComponent> createState() => _NoteLineComponentState();
}

class _NoteLineComponentState extends State<NoteLineComponent>
    with ProxyDocumentComponent<NoteLineComponent>, ProxyTextComposable {
  final _textKey = GlobalKey();

  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => _textKey;

  @override
  TextComposable get childTextComposable => childDocumentComponentKey.currentState as TextComposable;

  @override
  Widget build(BuildContext context) {
    final model = widget.viewModel;
    final brand = brandOf(context);
    final style = model.textStyleBuilder({});
    final scaler = MediaQuery.textScalerOf(context);
    final lineHeight = scaler.scale((style.fontSize ?? 17) * (style.height ?? 1.5));
    final mark = model.mark;
    final indent = model.indent * indentWidth;
    Widget words = TextComponent(
      key: _textKey,
      text: model.text,
      textDirection: model.textDirection,
      textAlign: model.textAlignment,
      textScaler: model.textScaler,
      textStyleBuilder: model.textStyleBuilder,
      inlineWidgetBuilders: model.inlineWidgetBuilders,
      metadata: model.blockType != null ? {'blockType': model.blockType} : const {},
      textSelection: model.selection,
      selectionColor: model.selectionColor,
      highlightWhenEmpty: model.highlightWhenEmpty,
      underlines: model.createUnderlines(),
    );
    if (model.hint case final hint?) {
      words = Stack(children: [
        words,
        Positioned.fill(child: IgnorePointer(child: Text(hint, maxLines: 1, overflow: TextOverflow.clip,
          style: style.copyWith(color: brand.muted)))),
      ]);
    }
    if (model.kind == LineKind.quote) {
      words = Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: brand.line, width: 3))),
        child: words,
      );
    } else if (model.kind == LineKind.code) {
      words = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: brand.paper, borderRadius: BorderRadius.circular(6)),
        child: words,
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: indent),
      if (mark != NoteMark.none)
        SizedBox(width: markWidth, height: lineHeight, child: _mark(context, brand, style, mark)),
      Expanded(child: words),
    ]);
  }

  Widget _mark(BuildContext context, BrandColors brand, TextStyle style, NoteMark mark) {
    final model = widget.viewModel;
    final words = style.copyWith(color: brand.ink, fontWeight: FontWeight.w400, decoration: TextDecoration.none,
      fontStyle: FontStyle.normal, backgroundColor: const Color(0x00000000));
    switch (mark) {
      case NoteMark.bullet:
        return Center(child: Text('•', style: words));
      case NoteMark.dashed:
        return Center(child: Text('–', style: words));
      case NoteMark.number:
        return Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(right: 8),
          child: Text('${model.number}.', style: words)));
      case NoteMark.unchecked || NoteMark.checked:
        final ticked = mark == NoteMark.checked;
        final tick = widget.onTick;
        return MetaData(metaData: _circleMark, behavior: HitTestBehavior.opaque, child: Semantics(
          checked: ticked,
          label: ticked ? 'Ticked' : 'Not ticked',
          child: InkResponse(
            onTap: tick == null ? null : () => tick(model.nodeId, !ticked),
            radius: 18,
            child: Center(child: Icon(ticked ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, size: 24,
              color: ticked ? brand.accent : brand.muted)),
          ),
        ));
      case NoteMark.none:
        return const SizedBox.shrink();
    }
  }
}

/// A triple tap or a triple click selects one line of words: from the line break before to the line break after, not
/// the whole item with its later lines.
class LineTapDelegate extends ContentTapDelegate {
  LineTapDelegate(this.editor);

  final Editor editor;

  @override
  TapHandlingInstruction onTripleTap(DocumentTapDetails details) {
    final position = details.documentLayout.getDocumentPositionNearestToOffset(details.layoutOffset);
    if (position == null) return TapHandlingInstruction.continueHandling;
    final node = editor.document.getNodeById(position.nodeId);
    final at = position.nodePosition;
    if (node is! TextNode || at is! TextNodePosition) return TapHandlingInstruction.continueHandling;
    final range = lineAround(node.text.toPlainText(includePlaceholders: false), at.offset);
    editor.execute([
      ChangeSelectionRequest(DocumentSelection(
        base: DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: range.start)),
        extent: DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: range.end)),
      ), SelectionChangeType.expandSelection, SelectionReason.userInteraction),
    ]);
    return TapHandlingInstruction.halt;
  }
}

/// The line of [words] that holds [offset]: from the line break before it to the line break after it.
TextRange lineAround(String words, int offset) {
  final at = offset.clamp(0, words.length);
  final start = at == 0 ? 0 : words.lastIndexOf('\n', at - 1) + 1;
  final next = words.indexOf('\n', at);
  return TextRange(start: start, end: next < 0 ? words.length : next);
}

/// The page's own handling of taps in a note's words: [handle] gets each tap's place on the screen and in the words,
/// and answers true when it took the tap.
class NoteTapDelegate extends ContentTapDelegate {
  NoteTapDelegate(this.handle);

  final bool Function(Offset global, DocumentPosition? position) handle;

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    final position = details.documentLayout.getDocumentPositionNearestToOffset(details.layoutOffset);
    return handle(details.globalOffset, position) ? TapHandlingInstruction.halt : TapHandlingInstruction.continueHandling;
  }
}
