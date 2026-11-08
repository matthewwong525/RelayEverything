import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../brand.dart';
import '../relay.dart';
import '../voice/model.dart' show megabytes;

void _say(BuildContext context, String? message) {
  if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// *New note*: a tap writes, a hold talks. A press held [holdToTalk] buzzes, turns the button into the spark mic, and
/// starts a voice note, which keeps recording after the finger lifts; the listening card saves it. A shorter press
/// opens the page to write. With no speech model yet, a hold asks to get it.
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

class _NewNoteButtonState extends State<NewNoteButton> {
  // From the hold until the voice note has started, or said why not.
  bool _starting = false;

  Relay get _relay => widget.relay;

  Future<void> _talk() async {
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
    return Semantics(
      label: 'New note',
      button: true,
      onTap: widget.onWrite,
      customSemanticsActions: {const CustomSemanticsAction(label: 'Record a voice note'): _talk},
      excludeSemantics: true,
      // A tap fires on a lift before [holdToTalk]; the long press at it, so lifting after a hold does nothing.
      child: GestureDetector(
        onTap: widget.onWrite,
        onLongPress: _talk,
        child: AccentGlow(child: Material(
          color: live ? brand.spark : brand.accent,
          shape: const CircleBorder(),
          elevation: live ? 0 : 3,
          child: SizedBox.square(dimension: 52,
            child: Icon(live ? CupertinoIcons.mic_fill : CupertinoIcons.square_pencil, color: live ? brand.onSpark : brand.onAccent)),
        )),
      ),
    );
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

/// *Start a voice note* from Shortcuts or the Action button: it records at once, in the same listening card as a hold
/// on *New note*, or, with no speech model yet, asks the same question.
Future<void> recordFromShortcut(BuildContext context, Relay relay) async {
  if (relay.speechModel != ModelState.ready) return askForModel(context, relay);
  final problem = await relay.startVoiceNote();
  if (context.mounted) _say(context, problem);
}

/// Over the whole app while the phone listens: a tap anywhere saves the voice note and writes its words; *Cancel*
/// keeps nothing. The timeline shows it whenever [Relay.listening] is set, from a hold or from Shortcuts.
class ListeningOverlay extends StatefulWidget {
  const ListeningOverlay({super.key, required this.relay, required this.onSaved});

  final Relay relay;
  /// After a tap saved the voice note: gets the time it started, which is its note's time, so the note's page opens.
  final void Function(DateTime at) onSaved;

  @override
  State<ListeningOverlay> createState() => _ListeningOverlayState();
}

class _ListeningOverlayState extends State<ListeningOverlay> {
  late final Timer _tick;
  bool _done = false;

  Relay get _relay => widget.relay;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    if (_done) return;
    _done = true;
    final messenger = ScaffoldMessenger.of(context);
    final onSaved = widget.onSaved;
    // Read first: the save ends the listening, and the note keeps this time.
    final since = _relay.listening;
    try {
      final problem = await _relay.endVoiceNote();
      if (problem != null) {
        messenger.showSnackBar(SnackBar(content: Text(problem)));
      } else if (since != null) {
        onSaved(since);
      }
    } catch (_) {
      // A guard: the app's Relay returns its problems. A card still listening stays usable: a tap tries again, and
      // Cancel closes it.
      _done = false;
      final listening = _relay.listening != null;
      messenger.showSnackBar(SnackBar(content: Text(listening
        ? 'The voice note did not save. Tap to try again, or Cancel.'
        : 'The voice note did not save.')));
    }
  }

  // Cancel always runs, also after a save that failed, so the card can never stay stuck.
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
    final theme = Theme.of(context);
    final brand = brandOf(context);
    final since = _relay.listening;
    final length = since == null ? Duration.zero : DateTime.now().difference(since);
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _save,
        child: Stack(children: [
          Positioned.fill(child: Semantics(label: 'Save the voice note', button: true, onTap: _save,
            child: const ColoredBox(color: Color(0x59000000)))),
          Positioned(left: 16, right: 16, bottom: 96 + MediaQuery.paddingOf(context).bottom, child: Card(
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 10, children: [
                Row(children: [
                  const BrandTag('Listening', spark: true, large: true),
                  const Spacer(),
                  TextButton(onPressed: _cancel, style: quietButton(context), child: const Text('Cancel')),
                ]),
                Text(clockOf(length.isNegative ? Duration.zero : length), style: const TextStyle(fontSize: 32,
                  fontWeight: FontWeight.w600, letterSpacing: -0.64, fontFeatures: [FontFeature.tabularFigures()])),
                DecoratedBox(decoration: ShapeDecoration(color: brand.spark, shape: const StadiumBorder()),
                  child: const SizedBox(height: 4, width: double.infinity)),
                Text('Tap anywhere to save.', style: theme.textTheme.bodySmall?.copyWith(color: brand.muted)),
              ]),
            ),
          )),
        ]),
      ),
    );
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
