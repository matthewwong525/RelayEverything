import 'dart:async';
import 'dart:math' show max, pi;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../brand.dart';
import '../relay.dart';
import '../voice/model.dart' show megabytes;
import '../voice/recorder.dart' show longest;

void _say(BuildContext context, String? message) {
  if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// *New note*: a tap writes, a hold talks. While held, a spark ring fills round the button over [holdToTalk]; when it
/// closes, the phone buzzes, the button turns into the spark mic, and a voice note starts on the recording screen. A
/// shorter press opens the page to write. Until a first voice note, a *Hold to talk* tip shows above it.
class NewNoteButton extends StatefulWidget {
  const NewNoteButton({super.key, required this.relay, required this.onWrite});

  final Relay relay;
  /// Opens the page to write a note.
  final VoidCallback onWrite;

  @override
  State<NewNoteButton> createState() => _NewNoteButtonState();
}

/// How long a press must last to start a voice note: the phone's own long press, and the voice notes rule's floor.
const holdToTalk = kLongPressTimeout;

class _NewNoteButtonState extends State<NewNoteButton> with SingleTickerProviderStateMixin {
  // From the hold until the voice note has started, or said why not.
  bool _starting = false;
  // Preserve: with animations off, the ring must still take [holdToTalk] to fill, as the hold does.
  late final _hold = AnimationController(vsync: this, duration: holdToTalk, animationBehavior: AnimationBehavior.preserve);

  Relay get _relay => widget.relay;

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  Future<void> _talk() async {
    _hold.reset();
    unawaited(HapticFeedback.mediumImpact());
    if (_relay.speechModel != ModelState.ready) return askForModel(context, _relay);
    setState(() => _starting = true);
    final problem = await _relay.startVoiceNote();
    if (!mounted) return;
    setState(() => _starting = false);
    _say(context, problem);
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final live = _starting || _relay.listening != null;
    return Stack(clipBehavior: Clip.none, children: [
      Semantics(
        label: 'New note',
        button: true,
        onTap: widget.onWrite,
        customSemanticsActions: {const CustomSemanticsAction(label: 'Record a voice note'): _talk},
        excludeSemantics: true,
        // A tap fires on a lift before [holdToTalk]; the long press at it, so lifting after a hold does nothing.
        child: GestureDetector(
          onTap: widget.onWrite,
          onLongPressDown: (_) => _hold.forward(from: 0),
          onLongPressCancel: _hold.reset,
          onLongPress: _talk,
          child: AccentGlow(child: Material(
            color: live ? brand.spark : brand.accent,
            shape: const CircleBorder(),
            elevation: live ? 0 : 3,
            child: SizedBox.square(dimension: 52,
              child: Icon(live ? CupertinoIcons.mic_fill : CupertinoIcons.square_pencil, color: live ? brand.onSpark : brand.onAccent)),
          )),
        ),
      ),
      Positioned(left: -6, top: -6, right: -6, bottom: -6, child: IgnorePointer(
        child: CustomPaint(painter: HoldRingPainter(progress: _hold, color: brand.spark)))),
      if (!_relay.holdTipSeen) const Positioned(right: 0, bottom: 64, child: _HoldTip()),
    ]);
  }
}

/// The spark ring round *New note* that fills while it is held, from the top, clockwise.
class HoldRingPainter extends CustomPainter {
  HoldRingPainter({required this.progress, required this.color}) : super(repaint: progress);

  /// From 0, not held, to 1, held for [holdToTalk].
  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress.value == 0) return;
    const width = 4.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawArc((Offset.zero & size).deflate(width / 2), -pi / 2, 2 * pi * progress.value, false, paint);
  }

  @override
  bool shouldRepaint(HoldRingPainter old) => old.progress != progress || old.color != color;
}

/// *Hold to talk*: a small ink bubble above *New note*, pointing at it.
class _HoldTip extends StatelessWidget {
  const _HoldTip();

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Stack(clipBehavior: Clip.none, children: [
      DecoratedBox(
        decoration: BoxDecoration(color: brand.ink, borderRadius: BorderRadius.circular(12)),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text('Hold to talk', softWrap: false,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: brand.paper))),
      ),
      Positioned(right: 21, bottom: -4, child: Transform.rotate(angle: pi / 4,
        child: ColoredBox(color: brand.ink, child: const SizedBox.square(dimension: 10)))),
    ]);
  }
}

/// With no speech model yet: says it is coming, or asks to get it, as a first voice note does.
Future<void> askForModel(BuildContext context, Relay relay) async {
  if (relay.speechModel == ModelState.downloading) {
    return _say(context, 'The speech model is still coming. You can type notes now.');
  }
  relay.askSpeechModel();
  final yes = await showDialog<bool>(context: context, builder: (context) => ModelDialog(bytes: relay.modelBytes));
  if (yes == true) {
    unawaited(relay.getSpeechModel());
  } else {
    relay.notNowSpeechModel();
  }
}

/// *Start a voice note* from Shortcuts or the Action button: it records at once, on the same recording screen as a hold
/// on *New note*, or, with no speech model yet, asks the same question.
Future<void> recordFromShortcut(BuildContext context, Relay relay) async {
  if (relay.speechModel != ModelState.ready) return askForModel(context, relay);
  final problem = await relay.startVoiceNote();
  if (context.mounted) _say(context, problem);
}

/// Over the whole app while the phone listens: the time, a sound level that follows the microphone, and *Tap anywhere
/// to save*. A tap anywhere, a side swipe or the back gesture saves the voice note and writes its words; the X at the
/// top right keeps nothing. Home shows it whenever [Relay.listening] is set, from a hold or from Shortcuts.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key, required this.relay});

  final Relay relay;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

/// How many sound bars the recording screen shows.
const levelBars = 17;

/// Saves on the back gesture of the page under the recording screen, which sits in the overlay, not in a route.
class _BackSaves extends PopEntry<Object?> {
  _BackSaves(this.save);

  final VoidCallback save;

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier(false);

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop) save();
  }
}

class _RecordingScreenState extends State<RecordingScreen> {
  late final Timer _tick;
  StreamSubscription<double>? _heard;
  // The latest level, and how many came, so each new one moves the bars a little.
  double _level = 0;
  int _heardCount = 0;
  late final _back = _BackSaves(() => unawaited(_save()));
  ModalRoute<Object?>? _page;
  bool _done = false;

  Relay get _relay => widget.relay;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
    _heard = _relay.level?.listen((level) => setState(() {
      _level = level;
      _heardCount++;
    }));
    // The page on top gets the back gesture, so this screen holds it there; popUntil only reads the top page here.
    Navigator.of(context, rootNavigator: true).popUntil((route) {
      _page = route is ModalRoute<Object?> ? route : null;
      return true;
    });
    _page?.registerPopEntry(_back);
  }

  @override
  void dispose() {
    _page?.unregisterPopEntry(_back);
    _back.canPopNotifier.dispose();
    _heard?.cancel();
    _tick.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    if (_done) return;
    _done = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final problem = await _relay.endVoiceNote();
      if (problem != null) messenger.showSnackBar(SnackBar(content: Text(problem)));
    } catch (_) {
      // A guard: the app's Relay returns its problems. A screen still listening stays usable: a tap tries again, and
      // the X closes it.
      _done = false;
      final listening = _relay.listening != null;
      messenger.showSnackBar(SnackBar(content: Text(listening
        ? 'The voice note did not save. Tap to try again, or tap X.'
        : 'The voice note did not save.')));
    }
  }

  // The X always runs, also after a save that failed, so the screen can never stay stuck.
  Future<void> _cancel() async {
    _done = true;
    try {
      await _relay.cancelVoiceNote();
    } catch (_) {
      _done = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final since = _relay.listening;
    final length = since == null ? Duration.zero : DateTime.now().difference(since);
    return Material(
      color: brand.paper,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _save,
        onHorizontalDragEnd: (_) => _save(),
        child: SafeArea(child: Stack(children: [
          Positioned.fill(child: Semantics(label: 'Save the voice note', button: true, onTap: _save,
            child: const SizedBox.expand())),
          Column(children: [
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 18, children: [
              Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                DecoratedBox(decoration: ShapeDecoration(color: brand.spark, shape: const CircleBorder()),
                  child: const SizedBox.square(dimension: 9)),
                Text('Listening', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: brand.muted)),
              ]),
              Text(clockOf(length.isNegative ? Duration.zero : length), style: TextStyle(fontSize: 72, color: brand.ink,
                fontWeight: FontWeight.w600, letterSpacing: -2, fontFeatures: const [FontFeature.tabularFigures()])),
              LevelBars(level: _level, step: _heardCount),
            ])),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(spacing: 4, children: [
                Text('Tap anywhere to save', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: brand.ink)),
                Text('Saves by itself at ${clockOf(longest)}', style: TextStyle(fontSize: 13, color: brand.muted)),
              ]),
            ),
          ]),
          Positioned(top: 8, right: 16, child: IconButton(
            tooltip: 'Cancel',
            onPressed: _cancel,
            style: IconButton.styleFrom(backgroundColor: brand.card, foregroundColor: brand.ink, fixedSize: const Size.square(44),
              side: BorderSide(color: brand.line)),
            icon: const Icon(CupertinoIcons.xmark),
          )),
        ])),
      ),
    );
  }
}

/// The recording screen's sound bars in spark: all [levelBars] follow the current [level] at once, tallest in the
/// middle, each a little different at each [step]. A level of 0 keeps every bar at its floor. With *Reduce motion* on,
/// bars jump to each level with no easing.
class LevelBars extends StatelessWidget {
  const LevelBars({super.key, required this.level, this.step = 0});

  /// The current sound level, from 0 for silence to 1 for loud.
  final double level;
  /// How many levels came; it moves each bar's small difference, the same for the same step.
  final int step;

  static const floor = 8.0, top = 72.0;

  /// The height of bar [index] at [level] and [step]: the full height, less a tenth for each bar from the middle, times
  /// the level, times 0.75 to 1 so the bars do not move as one.
  static double heightOf(int index, double level, int step) {
    const middle = (levelBars - 1) ~/ 2;
    final shape = 1 - (index - middle).abs() / 10;
    final wobble = 0.75 + 0.25 * ((index * 7 + step * 5) % levelBars) / (levelBars - 1);
    return max(floor, top * shape * level * wobble);
  }

  @override
  Widget build(BuildContext context) {
    final spark = brandOf(context).spark;
    final ease = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120);
    return SizedBox(height: top, child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
      for (var index = 0; index < levelBars; index++)
        AnimatedContainer(
          duration: ease,
          curve: Curves.easeOut,
          width: 6,
          height: heightOf(index, level, step),
          decoration: ShapeDecoration(color: spark, shape: const StadiumBorder()),
        ),
    ]));
  }
}

/// *Get the speech model?* True for *Get it*.
class ModelDialog extends StatelessWidget {
  const ModelDialog({super.key, required this.bytes});

  final int bytes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Get the speech model?'),
      content: Text('Voice notes need a ${megabytes(bytes)} file, one time. The phone uses it to write your words. '
        'Your voice never leaves this phone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Get it')),
      ],
    );
  }
}

/// m:ss
String clockOf(Duration length) => '${length.inMinutes}:${(length.inSeconds % 60).toString().padLeft(2, '0')}';

/// On the timeline while the speech model downloads, or when its download failed.
class ModelCard extends StatelessWidget {
  const ModelCard({super.key, required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final failed = relay.speechModel == ModelState.failed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: failed ? [
          Text(relay.modelProblem == ModelProblem.damaged
            ? 'The speech model came damaged, so the phone deleted it.'
            : 'The speech model did not finish downloading.'),
          Text('Voice notes stay off until it is here. Typed notes work now.', style: muted),
          Align(alignment: Alignment.centerRight,
            child: TextButton(onPressed: relay.getSpeechModel, child: const Text('Try again'))),
        ] : [
          Text('Getting the speech model… ${(relay.modelProgress * 100).floor()}%'),
          LinearProgressIndicator(value: relay.modelProgress),
          Text('You can type notes now. Voice notes start when it is done.', style: muted),
        ]),
      ),
    );
  }
}
