import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// The note editor's magnifier while a finger drags the cursor or a selection handle: Quill's `quillMagnifierBuilder`.
Widget noteMagnifier(Offset dragPosition) => NoteMagnifier(dragPosition: dragPosition);

/// The phone's own lens over the line under the finger: on an iPhone Flutter's `CupertinoMagnifier` capsule, on Android
/// its Material `Magnifier`. It sits centred above the finger's line, inside the screen, as Flutter's
/// `CupertinoTextMagnifier` and `TextMagnifier` place theirs. Quill puts it in the editor's `Stack`, which clips, so the
/// lens shows in the page's overlay: there it can sit above the first line.
class NoteMagnifier extends StatefulWidget {
  const NoteMagnifier({super.key, required this.dragPosition});

  /// The finger, in the editor's own coordinates, as Quill gives it.
  final Offset dragPosition;

  /// The space the lens keeps from the left and right edges of the screen, as `CupertinoTextMagnifier` keeps.
  static const edge = 10.0;

  /// Whether this phone shows the iPhone's capsule, not Android's lens.
  static bool get cupertino =>
    defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

  /// The lens's size without its rim.
  static Size get size => cupertino ? CupertinoMagnifier.kDefaultSize : Magnifier.kDefaultMagnifierSize;

  /// How far the lens's centre sits above the centre of the line it shows: each lens's own focal point.
  static double get above => cupertino
    ? size.height / 2 - CupertinoMagnifier.kMagnifierAboveFocalPoint
    : size.height / 2 + Magnifier.kStandardVerticalFocalPointShift;

  /// The lens's box on [screen], centred above [finger] on the line whose centre is at [line], and kept inside the
  /// screen; and the focal point offset that still points the lens at the finger's place on that line.
  static ({Rect lens, Offset focus}) place({required Offset finger, required double line, required Rect screen}) {
    final wanted = Rect.fromCenter(center: Offset(finger.dx, line - above), width: size.width, height: size.height);
    final lens = MagnifierController.shiftWithinBounds(rect: wanted,
      bounds: Rect.fromLTRB(screen.left + edge, screen.top, screen.right - edge, screen.bottom));
    return (lens: lens, focus: Offset(finger.dx, line) - (lens.center + Offset(0, above)));
  }

  @override
  State<NoteMagnifier> createState() => _NoteMagnifierState();
}

class _NoteMagnifierState extends State<NoteMagnifier> {
  final _overlay = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _overlay.show();
  }

  /// The finger on the screen, and the centre of the line under it on the screen. Both come from the last frame's
  /// layout: Quill shows the magnifier one frame after the drag moves.
  (Offset, double) _finger() {
    final stack = context.findAncestorRenderObjectOfType<RenderStack>();
    final finger = stack == null || !stack.attached ? widget.dragPosition : stack.localToGlobal(widget.dragPosition);
    final editor = context.findAncestorStateOfType<QuillEditorState>()?.editableTextKey.currentState?.renderEditor;
    if (editor == null || !editor.attached || !editor.hasSize) return (finger, finger.dy);
    final caret = editor.getLocalRectForCaret(editor.getPositionForOffset(finger));
    return (finger, editor.localToGlobal(caret.center).dy);
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _overlay,
    overlayChildBuilder: (context) {
      final (finger, line) = _finger();
      final (:lens, :focus) = NoteMagnifier.place(finger: finger, line: line, screen: Offset.zero & MediaQuery.sizeOf(context));
      final overlay = Overlay.of(context).context.findRenderObject();
      final at = overlay is RenderBox && overlay.attached ? overlay.globalToLocal(lens.topLeft) : lens.topLeft;
      return Positioned(left: at.dx, top: at.dy, child: IgnorePointer(child: NoteMagnifier.cupertino
        // The rim takes the app's tint, as the iPhone's own lens and Flutter's `CupertinoTextMagnifier` do.
        ? CupertinoMagnifier(additionalFocalPointOffset: focus,
            borderSide: BorderSide(color: CupertinoTheme.of(context).primaryColor, width: 2))
        : Magnifier(additionalFocalPointOffset: focus)));
    },
    child: const SizedBox.shrink(),
  );
}
