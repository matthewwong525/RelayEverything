import 'dart:async';

import 'package:flutter/material.dart';

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

/// Every note, newest first, with the one primary action, a new note, and *Hold to talk* beside it.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.relay, this.scanner});

  final Relay relay;
  /// The QR scanner the connect screen uses; a test passes its own.
  final Scanner? scanner;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late final StreamSubscription<String> _notices;

  Relay get relay => widget.relay;
  Scanner? get scanner => widget.scanner;

  @override
  void initState() {
    super.initState();
    // Such as *No speech heard*, which comes after the words are written.
    _notices = relay.notices.listen((message) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
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
        final top = model ? 1 : 0;
        final listening = relay.listening;
        return Scaffold(
          appBar: AppBar(title: const Text('Relay'), actions: [
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
              FloatingActionButton.extended(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ComposeScreen(relay: relay))),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('New note'),
              ),
            ]),
          ]),
          body: RefreshIndicator(
            onRefresh: relay.sync,
            child: entries.isEmpty
              ? ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
                  if (model) ModelCard(relay: relay),
                  Padding(padding: const EdgeInsets.all(32),
                    child: Text(relay.settings.sending ? 'No notes yet. Hold the ring and talk, or tap New note.' : 'No notes yet. Tap New note, or hold to talk.',
                      textAlign: TextAlign.center)),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 160),
                  itemCount: top + entries.length + (relay.hasMore ? 1 : 0),
                  itemBuilder: (context, index) => index < top
                    ? ModelCard(relay: relay)
                    : index - top == entries.length
                      ? Center(child: TextButton(onPressed: relay.more, child: const Text('Show older notes')))
                      : _NoteCard(entry: entries[index - top], relay: relay),
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
    final line = [_time(context, entry.at), if (entry.length != null) clockOf(entry.length!), entry.place, entry.device]
      .whereType<String>().join(' · ');
    final recording = entry.recording;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          Row(spacing: 8, children: [
            Chip(label: Text(entry.ring ? 'Ring' : entry.voice ? 'Voice' : 'Typed'), visualDensity: VisualDensity.compact),
            if (entry.waiting) Chip(avatar: const Icon(Icons.schedule, size: 16), label: const Text('Waiting'), visualDensity: VisualDensity.compact),
            if (entry.audio) const Icon(Icons.mic_none, size: 18, semanticLabel: 'Has a recording'),
            if (recording != null) ...[
              const Spacer(),
              TextButton.icon(onPressed: () => relay.play(recording), icon: const Icon(Icons.play_arrow), label: const Text('Play')),
            ],
          ]),
          if (entry.writing) ...[
            Text('Writing the words…', style: muted),
            const LinearProgressIndicator(),
          ] else
            Text(entry.text.isEmpty ? 'No words, only the recording.' : entry.text, style: theme.textTheme.bodyLarge),
          Text(line, style: muted),
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
