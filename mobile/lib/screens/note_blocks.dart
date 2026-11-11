import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import 'hold_to_talk.dart' show clockOf;

/// A picture of a note: the app's copy on the phone, or the person's space's file route in the browser. [cacheWidth] keeps
/// a small picture small in memory.
class EntryImage extends StatelessWidget {
  const EntryImage({super.key, required this.file, this.width, this.height, this.cacheWidth, required this.fallback});

  final EntryFile file;
  final double? width;
  final double? height;
  final int? cacheWidth;
  /// Shows when the picture does not load.
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    Widget failed(BuildContext context, Object _, StackTrace? _) => fallback;
    if (file.onPhone) {
      return Image.file(File(file.path), width: width, height: height, fit: BoxFit.cover, cacheWidth: cacheWidth,
        errorBuilder: failed);
    }
    final url = file.url;
    if (url == null) return fallback;
    return Image.network(url, width: width, height: height, fit: BoxFit.cover, cacheWidth: cacheWidth, errorBuilder: failed);
  }
}

/// A picture, full width; a tap opens it.
class NotePicture extends StatelessWidget {
  const NotePicture({super.key, required this.file, required this.relay});

  final EntryFile file;
  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Tooltip(
      message: file.name,
      child: InkWell(
        onTap: () => relay.openFile(file),
        borderRadius: BorderRadius.circular(14),
        // The height holds the place while the picture loads.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 180), child: ColoredBox(color: brand.accentSoft,
            child: EntryImage(file: file, width: double.infinity, cacheWidth: 1080,
              fallback: Container(height: 180, color: brand.accentSoft, child: Icon(CupertinoIcons.photo, color: brand.muted))))),
        ),
      ),
    );
  }
}

/// Any other file, or one not on the phone yet: its name and size in a card row; a tap downloads it if needed, then
/// opens it. In the browser a tap opens the file in a new tab.
class NoteFileRow extends StatelessWidget {
  const NoteFileRow({super.key, required this.file, required this.relay});

  final EntryFile file;
  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => relay.openFile(file),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(spacing: 10, children: [
            Icon(file.ready ? CupertinoIcons.doc : CupertinoIcons.cloud_download, size: 20, color: brand.muted),
            Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
            Text([if (file.size > 0) sizeLabel(file.size), if (!file.ready) 'Download'].join(' · '),
              style: TextStyle(fontSize: 13, color: brand.muted)),
          ]),
        ),
      ),
    );
  }
}

/// A voice note's player, at the top of its page: play and pause, the recording's sound waves, which fill in the accent
/// text color as it plays, and the time: *0:12 / 0:42* while it plays or is paused, the length when it is stopped. A tap
/// or a drag on the waves goes to that point, and starts the recording there when it is stopped. With no waves to read,
/// such as in the browser or for a recording that is not a WAV, a plain line takes their place, and it still plays.
/// With no [length], as in the browser, it uses the length the player reads once the recording starts, and shows no
/// time until then: a tap on the line starts it, then goes to that place.
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, required this.relay, required this.recording, required this.length});

  final Relay relay;
  final String recording;
  final Duration? length;

  /// How far a screen reader's swipe up or down moves the playback.
  static const step = Duration(seconds: 5);

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  /// Read once for the open page, and kept by no one after it.
  late Future<List<double>> _wave = widget.relay.waveOf(widget.recording);
  /// A tap on the waves of a stopped recording starts it: a drag meanwhile starts nothing more.
  bool _starting = false;

  /// The length the player read for this recording, kept after it stops.
  Duration? _heard;

  Relay get relay => widget.relay;
  Duration get _length => widget.length ?? _now?.length ?? _heard ?? Duration.zero;

  @override
  void didUpdateWidget(VoicePlayer old) {
    super.didUpdateWidget(old);
    if (old.recording != widget.recording || old.relay != widget.relay) {
      _wave = relay.waveOf(widget.recording);
      _heard = null;
    }
  }

  /// This recording's playback, or null while another plays or none does.
  Playback? get _now => switch (relay.playback.value) {
    final now? when now.recording == widget.recording => now,
    _ => null,
  };

  Duration _clamp(Duration at) => at < Duration.zero ? Duration.zero : at > _length ? _length : at;

  /// Goes to [at], read only after a stopped recording starts: the browser's player knows the length only then.
  Future<void> _seek(Duration Function() at) async {
    Future<void> go() async {
      if (_length > Duration.zero) await relay.seek(_clamp(at()));
    }
    if (_now != null) return go();
    if (_starting) return;
    _starting = true;
    try {
      await relay.play(widget.recording);
      await go();
    } finally {
      _starting = false;
    }
  }

  void _seekAt(double x, double width) {
    if (width <= 0) return;
    final part = (x / width).clamp(0.0, 1.0);
    unawaited(_seek(() => _length * part));
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return ValueListenableBuilder(valueListenable: relay.playback, builder: (context, _, _) {
      final now = _now;
      if (now?.length case final heard?) _heard = heard;
      final playing = now?.playing ?? false;
      final at = now?.at ?? Duration.zero;
      final known = _length > Duration.zero;
      final done = known ? (at.inMilliseconds / _length.inMilliseconds).clamp(0.0, 1.0) : 0.0;
      final time = switch ((now, known)) {
        (null, true) => clockOf(_length),
        (null, false) => '',
        (_, true) => '${clockOf(at)} / ${clockOf(_length)}',
        (_, false) => clockOf(at),
      };
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(spacing: 10, children: [
            IconButton(
              tooltip: playing ? 'Pause' : 'Play',
              onPressed: () => playing ? relay.pause() : relay.play(widget.recording),
              // Accent soft, not filled: *New note* stays the one filled control.
              style: IconButton.styleFrom(backgroundColor: brand.accentSoft, fixedSize: const Size.square(44)),
              icon: Icon(playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, color: brand.accentText, size: 20),
            ),
            Expanded(child: LayoutBuilder(builder: (context, box) => Semantics(
              slider: true,
              label: 'Recording',
              value: time,
              increasedValue: clockOf(_clamp(at + VoicePlayer.step)),
              decreasedValue: clockOf(_clamp(at - VoicePlayer.step)),
              onIncrease: known ? () => _seek(() => at + VoicePlayer.step) : null,
              onDecrease: known ? () => _seek(() => at - VoicePlayer.step) : null,
              child: GestureDetector(
                key: const ValueKey('waves'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (tap) => _seekAt(tap.localPosition.dx, box.maxWidth),
                onHorizontalDragUpdate: (drag) => _seekAt(drag.localPosition.dx, box.maxWidth),
                child: SizedBox(height: 36, child: FutureBuilder(future: _wave, builder: (context, wave) => CustomPaint(
                  size: Size.infinite,
                  painter: WavePainter(levels: wave.data ?? const [], done: done, played: brand.accentText,
                    rest: brand.muted.withValues(alpha: 0.35)),
                ))),
              ),
            ))),
            ExcludeSemantics(child: Text(time,
              style: TextStyle(fontSize: 13, color: brand.muted, fontFeatures: const [FontFeature.tabularFigures()]))),
          ]),
        ),
      );
    });
  }
}

/// The sound waves: one round bar per level, the part played, [done] of the way, in [played] and the rest in [rest].
/// No levels draws a plain line, which fills the same way.
class WavePainter extends CustomPainter {
  const WavePainter({required this.levels, required this.done, required this.played, required this.rest});

  final List<double> levels;
  /// From 0 to 1.
  final double done;
  final Color played;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    final middle = size.height / 2;
    if (levels.isEmpty) {
      paint.strokeWidth = 3;
      canvas.drawLine(Offset(0, middle), Offset(size.width, middle), paint..color = rest);
      if (done > 0) canvas.drawLine(Offset(0, middle), Offset(size.width * done, middle), paint..color = played);
      return;
    }
    final step = size.width / levels.length;
    paint.strokeWidth = step * 0.55;
    for (final (index, level) in levels.indexed) {
      final x = step * (index + 0.5);
      // The quietest bar keeps a dot's height, so silence still reads as a recording.
      final half = middle * (0.12 + 0.88 * level.clamp(0.0, 1.0));
      paint.color = x / size.width <= done ? played : rest;
      canvas.drawLine(Offset(x, middle - half), Offset(x, middle + half), paint);
    }
  }

  @override
  bool shouldRepaint(WavePainter old) => old.levels != levels || old.done != done || old.played != played || old.rest != rest;
}
