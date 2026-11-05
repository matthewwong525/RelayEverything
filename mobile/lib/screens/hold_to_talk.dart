import 'dart:async';

import 'package:flutter/material.dart';

import '../relay.dart';
import '../voice/model.dart' show megabytes;

void _say(BuildContext context, String? message) {
  if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Hold to talk: press to record, let go to save, slide off to cancel. A `Listener` over the button, because Material
/// buttons give no release-outside event. With no speech model yet, a press asks to get it.
class HoldToTalkButton extends StatefulWidget {
  const HoldToTalkButton({super.key, required this.relay});

  final Relay relay;

  @override
  State<HoldToTalkButton> createState() => _HoldToTalkButtonState();
}

/// How far, in logical pixels, a finger may go past the button's edge before the note is cancelled.
const _slop = 24.0;

class _HoldToTalkButtonState extends State<HoldToTalkButton> {
  // This press records; false for a press that asks for the model instead.
  bool _holding = false;
  bool _cancelled = false;
  // A finger is on the button, so the Listener acts and onPressed does not.
  bool _touched = false;

  Relay get _relay => widget.relay;

  Future<void> _down(PointerDownEvent event) async {
    _touched = true;
    _cancelled = false;
    _holding = _relay.speechModel == ModelState.ready;
    if (!_holding) return;
    final problem = await _relay.startVoiceNote();
    if (mounted) _say(context, problem);
  }

  void _move(PointerMoveEvent event) {
    final size = context.size;
    if (!_holding || _cancelled || size == null) return;
    final at = event.localPosition;
    if (at.dx < -_slop || at.dy < -_slop || at.dx > size.width + _slop || at.dy > size.height + _slop) _cancel();
  }

  Future<void> _up(PointerUpEvent event) async {
    _untouch();
    if (!_holding) return _whenNotReady();
    _holding = false;
    if (_cancelled) return;
    final problem = await _relay.endVoiceNote();
    if (mounted) _say(context, problem);
  }

  // The button's own tap comes in the same pointer event, so the flag clears after it.
  void _untouch() => scheduleMicrotask(() => _touched = false);

  /// A screen reader's double tap sends no pointer events: it can not hold, but it can get the model.
  void _pressed() {
    if (_touched || _relay.speechModel == ModelState.ready) return;
    unawaited(_whenNotReady());
  }

  void _cancel() {
    _cancelled = true;
    unawaited(_relay.cancelVoiceNote());
  }

  Future<void> _whenNotReady() async {
    if (_relay.speechModel == ModelState.downloading) {
      return _say(context, 'The speech model is still coming. You can type notes now.');
    }
    _relay.askSpeechModel();
    final yes = await showDialog<bool>(context: context, builder: (context) => ModelDialog(bytes: _relay.modelBytes));
    if (yes == true) {
      unawaited(_relay.getSpeechModel());
    } else {
      _relay.notNowSpeechModel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: (_) {
        _untouch();
        if (_holding && !_cancelled) _cancel();
        _holding = false;
      },
      child: OutlinedButton.icon(
        // The Listener acts on a finger; the button gives the look, the ripple, the screen reader's label and its tap.
        onPressed: _pressed,
        style: OutlinedButton.styleFrom(minimumSize: const Size(56, 56), backgroundColor: Theme.of(context).colorScheme.surface),
        icon: const Icon(Icons.mic_none),
        label: const Text('Hold to talk'),
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

/// Shows while the phone listens: for how long, and how to save or cancel. It covers nothing and moves nothing.
class ListeningCard extends StatefulWidget {
  const ListeningCard({super.key, required this.since});

  final DateTime since;

  @override
  State<ListeningCard> createState() => _ListeningCardState();
}

class _ListeningCardState extends State<ListeningCard> {
  late final Timer _tick;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final length = DateTime.now().difference(widget.since);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            Chip(avatar: const Icon(Icons.mic, size: 16), label: const Text('Listening'), visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.primaryContainer),
            Text(clockOf(length.isNegative ? Duration.zero : length)),
          ]),
          Text('Let go to save. Slide off to cancel.', style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

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
