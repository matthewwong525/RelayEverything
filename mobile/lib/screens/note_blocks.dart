import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../brand.dart';
import '../relay.dart';
import 'back_to.dart';
import 'hold_to_talk.dart' show clockOf;
import 'round_button.dart';

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

/// A recording's player, at the top of its [RecordingCard]: play and pause, the recording's sound waves, which fill in the accent
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
      return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(spacing: 10, children: [
            IconButton(
              tooltip: playing ? 'Pause' : 'Play',
              onPressed: () => playing ? relay.pause() : relay.play(widget.recording),
              // Accent soft, not filled: *New note* stays the one filled control.
              style: IconButton.styleFrom(backgroundColor: brand.accentSoft, fixedSize: const Size.square(44)),
              icon: Icon(playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, color: brand.accentText, size: 20),
            ),
            // Its own node: inside the recording's card, it would merge with the transcript.
            Expanded(child: LayoutBuilder(builder: (context, box) => Semantics(
              container: true,
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

/// One recording in a note: its player, a hairline, then a *Transcript ›* row with none of the words. A tap on the row
/// opens the [RecordingPage], with all the words, as Apple Notes opens a recording. The row shows no splash: the page
/// opening shows the tap. While the words are written, failed or empty, the card says so and opens nothing. In the
/// browser and on the Mac, a recording whose sound has not come from the phone shows *Still on your phone* in place of
/// the player.
class RecordingCard extends StatelessWidget {
  const RecordingCard({super.key, required this.relay, required this.recording, this.editable = false, this.title = 'Note',
    this.when});

  final Relay relay;
  final EntryRecording recording;
  /// The phone's own note: its transcript can be corrected on the recording's page.
  final bool editable;
  /// The note's title, which the recording's page goes back to.
  final String title;
  /// The note's date, such as *Today at 11:24 PM*, which the recording's page shows with the length.
  final String? when;

  void _open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
    RecordingPage(relay: relay, recording: recording, editable: editable, back: title, when: when)));

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final muted = TextStyle(fontSize: 15, color: brand.muted);
    final words = recording.transcript != null && !recording.noWords && !recording.writing && !recording.failed;
    return Card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (recording.ready)
        VoicePlayer(relay: relay, recording: recording.recording, length: recording.length)
      else Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), child: Row(spacing: 10, children: [
        Icon(CupertinoIcons.mic, size: 18, color: brand.muted),
        Expanded(child: Text('Still on your phone', style: muted)),
        if (recording.length case final length?) Text(clockOf(length), style: TextStyle(fontSize: 13, color: brand.muted)),
      ])),
      if (recording.writing || recording.failed || recording.transcript != null) ...[
        Divider(height: 1, indent: 16, endIndent: 16, color: brand.muted.withValues(alpha: 0.15)),
        if (words)
          // Not an InkWell: its grey splash spread over the whole card.
          Semantics(button: true, child: GestureDetector(
            key: const ValueKey('transcript'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(context),
            child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Row(children: [
              Text('Transcript', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: brand.muted)),
              const Spacer(),
              Icon(CupertinoIcons.chevron_right, size: 15, color: brand.muted),
            ])),
          ))
        else Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), child: _status(brand, muted)),
      ],
    ]));
  }

  Widget _status(BrandColors brand, TextStyle muted) {
    if (recording.writing) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Text('Writing the words…', style: muted),
        const LinearProgressIndicator(),
      ]);
    }
    if (recording.failed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Text('The words did not come. Your recording is safe.', style: muted),
        // The reason, small and muted: the person sees it only on a recording that failed.
        if (recording.why case final why?) Text('Why: $why', style: TextStyle(fontSize: 13, color: brand.muted)),
        FilledButton(onPressed: relay.writeWordsAgain, child: const Text('Try again')),
      ]);
    }
    return Text('No words heard', style: muted);
  }
}

/// A recording's own page, as Apple Notes has it: back to the note, *Copy transcript*, the date and the length, all the
/// words as plain text, and the player at the bottom. With [editable], a tap on a word puts the cursor there, with no
/// box: the change is kept when the words lose the cursor, on *Done*, and when the page closes. Newer words from the
/// person's space fill in while the words do not have the cursor.
class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key, required this.relay, required this.recording, this.editable = false, this.back = 'Note',
    this.when});

  final Relay relay;
  final EntryRecording recording;
  /// The phone's own note: its transcript can be corrected here.
  final bool editable;
  /// The page under it, which *Back* names: the note's title.
  final String back;
  /// The note's date, shown with the recording's length.
  final String? when;

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  late EntryRecording _recording = widget.recording;
  late final _words = TextEditingController(text: _recording.transcript ?? '');
  final _focus = FocusNode();
  /// The words last sent, so a blur and then the page closing send them once.
  String? _sent;

  Relay get relay => widget.relay;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    relay.addListener(_synced);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _keep();
    if (mounted) setState(() {});
  }

  /// The recording as the phone has it now: by its file id, or by its file while it has none.
  EntryRecording? get _live {
    final id = _recording.id;
    return [...relay.entries, ...relay.deleted].expand((entry) => entry.recordings)
      .where((other) => id.isNotEmpty ? other.id == id : other.recording == _recording.recording).firstOrNull;
  }

  void _synced() {
    final live = _live;
    if (live == null || !mounted) return;
    final words = live.transcript ?? '';
    if (!_focus.hasFocus && words != _recording.transcript && words != _words.text) _words.text = words;
    setState(() => _recording = live);
  }

  @override
  void dispose() {
    relay.removeListener(_synced);
    _keep();
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _words.dispose();
    super.dispose();
  }

  /// Sends a corrected transcript; blank words are never kept, so the words written stay.
  void _keep() {
    final words = _words.text.trim();
    if (!widget.editable || words.isEmpty || words == _recording.transcript?.trim() || words == _sent) return;
    _sent = words;
    unawaited(relay.editTranscript(_recording.id, words));
  }

  /// Copies the words and shows nothing, as Apple's apps do.
  Future<void> _copy() => Clipboard.setData(ClipboardData(text: _words.text.trim()));

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final recording = _recording;
    final editing = _focus.hasFocus;
    final line = [?widget.when, if (recording.length case final length?) clockOf(length)].join(' · ');
    final words = TextStyle(fontSize: 17, height: 1.5, color: brand.ink);
    // Every border off: the theme's own would draw a rounded box around the words.
    const none = InputDecoration.collapsed(hintText: 'Transcript');
    return Scaffold(
      appBar: AppBar(leading: BackTo(widget.back), leadingWidth: BackTo.widthOf(widget.back), actions: [
        RoundIconButton(icon: CupertinoIcons.doc_on_doc, tooltip: 'Copy transcript', onPressed: _copy),
        if (editing) Padding(padding: const EdgeInsets.only(left: 8),
          child: RoundIconButton(icon: CupertinoIcons.checkmark_alt, tooltip: 'Done', onPressed: _focus.unfocus, accent: true)),
        const SizedBox(width: 12),
      ]),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (line.isNotEmpty) Text(line, style: TextStyle(fontSize: 13, color: brand.muted), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            if (widget.editable)
              TextField(controller: _words, focusNode: _focus, maxLines: null, style: words,
                decoration: none.copyWith(enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none, errorBorder: InputBorder.none, focusedErrorBorder: InputBorder.none))
            else
              SelectableText(_words.text, style: words),
          ]),
        )),
        // The keyboard takes the bottom while the words are fixed: the player comes back with *Done*.
        if (!editing) SafeArea(top: false, minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: Card(child: recording.ready
          ? VoicePlayer(relay: relay, recording: recording.recording, length: recording.length)
          : Padding(padding: const EdgeInsets.all(16), child: Row(spacing: 10, children: [
              Icon(CupertinoIcons.mic, size: 18, color: brand.muted),
              Expanded(child: Text('Still on your phone', style: TextStyle(fontSize: 15, color: brand.muted))),
            ])))),
      ]),
    );
  }
}
