import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../relay.dart';
import 'compose.dart';
import 'connect.dart' show Scanner;
import 'hold_to_talk.dart';
import 'settings.dart';

String _time(BuildContext context, DateTime at) {
  final now = DateTime.now();
  final time = TimeOfDay.fromDateTime(at).format(context);
  final today = at.year == now.year && at.month == now.month && at.day == now.day;
  return today ? time : '${MaterialLocalizations.of(context).formatShortMonthDay(at)}, $time';
}

/// Opens an address in the phone's own browser, and says if it did.
typedef Opener = Future<bool> Function(Uri address);

Future<bool> _openInBrowser(Uri address) async {
  try {
    return await launchUrl(address, mode: LaunchMode.externalApplication);
  } on Exception {
    return false;
  }
}

/// This phone's notes, newest first, with the one primary action, a new note, and *Hold to talk* beside it.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.relay, this.scanner, this.opener, this.picker, this.voiceRequests});

  final Relay relay;
  /// The QR scanner the connect screen uses; a test passes its own.
  final Scanner? scanner;
  /// Opens the Relay page; a test passes its own.
  final Opener? opener;
  /// The paperclip's picker; a test passes its own.
  final FilesPicker? picker;
  /// *Start a voice note* from Shortcuts: each event opens the recording sheet.
  final Stream<void>? voiceRequests;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late final StreamSubscription<String> _notices;
  StreamSubscription<void>? _voice;
  bool _recording = false;

  Relay get relay => widget.relay;
  Scanner? get scanner => widget.scanner;

  @override
  void initState() {
    super.initState();
    // Such as *No speech heard*, which comes after the words are written.
    _notices = relay.notices.listen((message) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    _voice = widget.voiceRequests?.listen((_) => _record());
  }

  /// Opens the recording sheet once, however many times the shortcut ran.
  Future<void> _record() async {
    if (!mounted || _recording) return;
    _recording = true;
    try {
      await recordFromShortcut(context, relay);
    } finally {
      _recording = false;
    }
  }

  @override
  void dispose() {
    _voice?.cancel();
    _notices.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: relay,
      builder: (context, _) {
        final entries = relay.entries;
        final model = relay.speechModel == ModelState.downloading || relay.speechModel == ModelState.failed;
        final server = relay.server;
        final top = <Widget>[
          // Ring notes and recordings are on the Relay page: a device key can not read them.
          if (relay.settings.sending && server != null) _PageCard(server: server, opener: widget.opener ?? _openInBrowser),
          if (model) ModelCard(relay: relay),
        ];
        final listening = relay.listening;
        return Scaffold(
          appBar: AppBar(titleSpacing: 12, title: const Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            RelayMark(size: 24),
            Flexible(child: Text('Relay Everything', overflow: TextOverflow.ellipsis)),
          ]), actions: [
            relay.settings.sending ? _SyncChip(relay: relay) : const _LocalChip(),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(relay: relay, scanner: scanner))),
            ),
          ]),
          floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
            if (listening != null) ListeningCard(since: listening),
            Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
              HoldToTalkButton(relay: relay),
              AccentGlow(child: FloatingActionButton.extended(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ComposeScreen(relay: relay, picker: widget.picker))),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('New note'),
              )),
            ]),
          ]),
          body: RefreshIndicator(
            onRefresh: relay.sync,
            child: entries.isEmpty
              ? ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
                  ...top,
                  const Padding(padding: EdgeInsets.all(32),
                    child: Text('No notes yet. Tap New note, or hold to talk.', textAlign: TextAlign.center)),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 160),
                  itemCount: top.length + entries.length,
                  itemBuilder: (context, index) => index < top.length
                    ? top[index]
                    : _NoteCard(entry: entries[index - top.length], relay: relay),
                ),
          ),
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.entry, required this.relay});

  final Entry entry;
  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final line = [_time(context, entry.at), if (entry.length != null) clockOf(entry.length!), entry.place,
      if (entry.sent) 'Sent' else if (entry.waiting) 'Waiting to send'].whereType<String>().join(' · ');
    final recording = entry.recording;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          Row(spacing: 8, children: [
            _KindChip(voice: entry.voice),
            if (recording != null) ...[
              const Spacer(),
              TextButton.icon(onPressed: () => relay.play(recording), icon: const Icon(Icons.play_arrow), label: const Text('Play')),
            ],
          ]),
          if (entry.writing) ...[
            Text('Writing the words…', style: muted),
            const LinearProgressIndicator(),
          ] else if (entry.text.isNotEmpty || entry.files.isEmpty)
            Text(entry.text.isEmpty ? 'No words, only the recording.' : entry.text, style: theme.textTheme.bodyLarge),
          if (entry.files.any((file) => file.picture))
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final file in entry.files) if (file.picture) _Thumbnail(file: file, relay: relay),
            ]),
          for (final file in entry.files) if (!file.picture) _FileRow(file: file, relay: relay),
          Text(line, style: muted),
        ]),
      ),
    );
  }
}

/// A note's kind: *Voice* in the spark color, a small live moment; *Typed* in accent text on accent soft.
class _KindChip extends StatelessWidget {
  const _KindChip({required this.voice});

  final bool voice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = brandOf(context);
    return Chip(
      label: Text(voice ? 'Voice' : 'Typed'),
      visualDensity: VisualDensity.compact,
      backgroundColor: voice ? theme.colorScheme.tertiary : brand.accentSoft,
      labelStyle: theme.chipTheme.labelStyle?.copyWith(color: voice ? theme.colorScheme.onTertiary : brand.accentText),
    );
  }
}

/// A picture on a note, small; a tap opens it.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.file, required this.relay});

  final EntryFile file;
  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: file.name,
      child: InkWell(
        onTap: () => relay.openFile(file),
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(file.path), width: 72, height: 72, fit: BoxFit.cover, cacheWidth: 216,
            errorBuilder: (context, _, _) => Container(width: 72, height: 72, color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.image_outlined))),
        ),
      ),
    );
  }
}

/// Any other file on a note: its name and size; a tap opens it.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.relay});

  final EntryFile file;
  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => relay.openFile(file),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(spacing: 8, children: [
          const Icon(Icons.insert_drive_file_outlined, size: 20),
          Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
          Text(sizeLabel(file.size), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// A quiet card on top of the list while sending is on: the Relay page has the ring notes and recordings.
class _PageCard extends StatelessWidget {
  const _PageCard({required this.server, required this.opener});

  final String server;
  final Opener opener;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await opener(Uri.parse('$server/apps/relay/'))) {
      messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ring notes and recordings are on your Relay Everything page.'),
          Align(alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => _open(context), child: const Text('Open your Relay Everything page'))),
        ]),
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (relay.status) {
      SyncStatus.syncing => (Icons.sync, 'Syncing'),
      SyncStatus.refused => (Icons.key_off_outlined, 'Key refused'),
      SyncStatus.offline => (Icons.cloud_off_outlined, relay.waiting > 0 ? '${relay.waiting} waiting' : 'Offline'),
      _ => (Icons.cloud_done_outlined, relay.waiting > 0 ? '${relay.waiting} waiting' : 'Synced'),
    };
    return ActionChip(avatar: Icon(icon, size: 18), label: Text(label), tooltip: 'Sync now', onPressed: relay.sync);
  }
}

/// With sending off, the header says where notes are, in place of the sync mark.
class _LocalChip extends StatelessWidget {
  const _LocalChip();

  @override
  Widget build(BuildContext context) {
    return const Chip(avatar: Icon(Icons.phone_android, size: 18), label: Text('On this phone'));
  }
}
