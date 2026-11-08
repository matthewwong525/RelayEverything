import 'dart:io';

import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import 'back_to_notes.dart';
import 'days.dart';
import 'hold_to_talk.dart' show clockOf;

/// One note, to read: when and where, all of its words, its pictures and files, *Play* for a recording, and its kind
/// and send state. It changes nothing, but *Try again* writes the words of a note whose words failed.
class NoteScreen extends StatelessWidget {
  const NoteScreen({super.key, required this.entry, required this.relay});

  final Entry entry;
  final Relay relay;

  /// The note as the list has it now, so words still being written fill in here too.
  Entry get _current =>
    relay.entries.where((other) => other.at == entry.at && other.voice == entry.voice).firstOrNull ?? entry;

  /// *Yesterday at 18:05 · Home*.
  String _when(BuildContext context, Entry note) {
    final days = daysAgo(note.at, DateTime.now());
    final day = days <= 0 ? 'Today' : days == 1 ? 'Yesterday' : MaterialLocalizations.of(context).formatMediumDate(note.at);
    return ['$day at ${TimeOfDay.fromDateTime(note.at).format(context)}', note.place].whereType<String>().join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    return Scaffold(
      appBar: AppBar(leading: const BackToNotes(), leadingWidth: backToNotesWidth),
      body: ListenableBuilder(
        listenable: relay,
        builder: (context, _) {
          final note = _current;
          final recording = note.recording;
          final state = sendState(note);
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 30), children: [
            Text(_when(context, note), style: muted, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            // Words typed with a recording, such as a shortcut's label, show while its own words are written.
            if (note.text.isNotEmpty && (note.writing || note.failed)) ...[
              _Words(text: note.text),
              const SizedBox(height: 14),
            ],
            if (note.writing) ...[
              Text('Writing the words…', style: TextStyle(color: brand.muted)),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ] else if (note.failed) ...[
              Text('The words did not come. Your recording is safe.', style: TextStyle(color: brand.muted)),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft,
                child: FilledButton(onPressed: relay.writeWordsAgain, child: const Text('Try again'))),
            ] else if (note.text.isNotEmpty)
              _Words(text: note.text)
            else if (recording != null)
              Text('No words, only the recording.', style: TextStyle(color: brand.muted)),
            for (final file in note.files)
              Padding(padding: const EdgeInsets.only(top: 14),
                child: file.picture ? _Picture(file: file, relay: relay) : _FileRow(file: file, relay: relay)),
            if (recording != null) Padding(padding: const EdgeInsets.only(top: 14),
              child: _Play(length: note.length, onPlay: () => relay.play(recording))),
            const SizedBox(height: 14),
            Row(spacing: 8, children: [
              BrandTag(note.voice ? 'Voice' : 'Typed', spark: note.voice, large: true),
              if (state != null) Text(state, style: muted),
            ]),
          ]);
        },
      ),
    );
  }
}

/// All of a note's words, to select and copy: the first line bold, as the list shows it.
class _Words extends StatelessWidget {
  const _Words({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final at = text.indexOf('\n');
    return SelectableText.rich(TextSpan(style: const TextStyle(fontSize: 17, height: 1.5), children: [
      TextSpan(text: at < 0 ? text : text.substring(0, at), style: const TextStyle(fontWeight: FontWeight.w700)),
      if (at >= 0) TextSpan(text: text.substring(at)),
    ]));
  }
}

/// A picture, full width; a tap opens it.
class _Picture extends StatelessWidget {
  const _Picture({required this.file, required this.relay});

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
            child: Image.file(File(file.path), width: double.infinity, fit: BoxFit.cover, cacheWidth: 1080,
            errorBuilder: (context, _, _) => Container(height: 180, color: brand.accentSoft,
              child: Icon(Icons.image_outlined, color: brand.muted))))),
        ),
      ),
    );
  }
}

/// Any other file: its name and size in a card row; a tap opens it.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.relay});

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
            Icon(Icons.insert_drive_file_outlined, size: 20, color: brand.muted),
            Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
            Text(sizeLabel(file.size), style: TextStyle(fontSize: 13, color: brand.muted)),
          ]),
        ),
      ),
    );
  }
}

/// *Play* for a voice note's recording, as a quiet card row with its length.
class _Play extends StatelessWidget {
  const _Play({required this.length, required this.onPlay});

  final Duration? length;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
          child: Row(spacing: 12, children: [
            DecoratedBox(decoration: BoxDecoration(color: brand.paper, shape: BoxShape.circle),
              child: SizedBox.square(dimension: 40, child: Icon(Icons.play_arrow, color: brand.ink))),
            const Expanded(child: Text('Play', style: TextStyle(fontWeight: FontWeight(650)))),
            if (length != null) Text(clockOf(length!), style: TextStyle(fontSize: 13, color: brand.muted)),
          ]),
        ),
      ),
    );
  }
}
