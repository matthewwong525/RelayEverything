import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import 'connect.dart' show Scanner;
import 'days.dart';
import 'folder.dart';
import 'hold_to_talk.dart';
import 'note_editor.dart';
import 'settings.dart';
import 'timeline.dart';

export 'folder.dart' show Opener;

/// The first screen, as Apple Notes' *Folders*: the notes folders, *On this phone*, the Settings gear, and at the bottom
/// *Search*, which finds notes in every folder, and *New note*. It also holds what each page needs once:
/// the notices, the listening card and *Start a voice note* from Shortcuts.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.relay, this.scanner, this.opener, this.picker, this.sharer,
    this.voiceRequests});

  final Relay relay;
  /// The QR scanner the connect screen uses; a test passes its own.
  final Scanner? scanner;
  /// Opens the Relay Everything page; a test passes its own.
  final Opener? opener;
  /// The paperclip's picker; a test passes its own.
  final FilesPicker? picker;
  /// A note's *Share*; a test passes its own.
  final Sharer? sharer;
  /// *Start a voice note* from Shortcuts: each event starts one in the listening card.
  final Stream<void>? voiceRequests;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final StreamSubscription<String> _notices;
  StreamSubscription<void>? _voice;
  OverlayEntry? _listening;
  bool _recording = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  Relay get relay => widget.relay;

  @override
  void initState() {
    super.initState();
    // Such as *No speech heard*, which comes after the words are written.
    _notices = relay.notices.listen((message) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    _voice = widget.voiceRequests?.listen((_) => _record());
    relay.addListener(_showListening);
    // The account's email and names, for Settings' Account row and the Account page.
    relay.refreshConnections();
  }

  /// Starts one voice note, or asks for the model once, however many times the shortcut ran.
  Future<void> _record() async {
    if (!mounted || _recording || relay.listening != null) return;
    _recording = true;
    try {
      await recordFromShortcut(context, relay);
    } finally {
      _recording = false;
    }
  }

  /// The listening card goes in the root overlay, so it covers any page a shortcut finds open.
  void _showListening() {
    if (!mounted) return;
    if (relay.listening != null && _listening == null) {
      _listening = OverlayEntry(builder: (_) => ListeningOverlay(relay: relay));
      Overlay.of(context, rootOverlay: true).insert(_listening!);
    } else if (relay.listening == null && _listening != null) {
      _listening!.remove();
      _listening = null;
    }
  }

  @override
  void dispose() {
    relay.removeListener(_showListening);
    _listening?.remove();
    _voice?.cancel();
    _notices.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _open(Widget page) => openPage(context, page);

  /// What pulling Home down does, and *Sync now* too.
  /// Pull to refresh and *Sync now* do the same: send what waits and take notes from the person's other devices.
  Future<void> _refresh() => relay.pullNotes();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([relay, _search, _searchFocus]),
        builder: (context, _) => Stack(children: [
          RefreshIndicator(
            onRefresh: _refresh,
            edgeOffset: 140,
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              _bar(),
              if (modelShows(relay)) modelSliver(relay),
              if (_search.text.trim().isNotEmpty)
                noteSliver(context, relay, relay.entries, _search.text, back: 'Home', picker: widget.picker, sharer: widget.sharer,
                  opener: widget.opener)
              else
                SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: SliverList.list(children: _folders())),
              const SliverPadding(padding: EdgeInsets.only(bottom: 110)),
            ]),
          ),
          NotesDock(relay: relay, search: _search, focus: _searchFocus,
            onWrite: () => _open(NoteEditor(relay: relay, picker: widget.picker, sharer: widget.sharer, opener: widget.opener,
              back: 'Home'))),
        ]),
      ),
    );
  }

  Widget _bar() {
    final brand = brandOf(context);
    return SliverAppBar.large(
      leading: const Center(child: RelayMark(size: 24)),
      title: const Text('Home'),
      expandedHeight: 140,
      actions: [
        IconButton(
          tooltip: 'Settings',
          style: IconButton.styleFrom(backgroundColor: brand.card, foregroundColor: brand.ink),
          icon: const Icon(CupertinoIcons.gear),
          onPressed: () => _open(SettingsScreen(relay: relay, scanner: widget.scanner, opener: widget.opener)),
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(preferredSize: const Size.fromHeight(SyncLine.height),
        child: SyncLine(relay: relay, onSync: _refresh)),
    );
  }

  List<Widget> _folders() {
    final now = DateTime.now();
    final scanner = widget.scanner;
    int count(NotesFolder folder) => relay.entries.where((entry) => entryIn(folder, entry)).length;
    return [
      const SizedBox(height: 12),
      _Card(rows: [
        for (final (folder, icon) in const [(NotesFolder.all, CupertinoIcons.doc_text), (NotesFolder.voice, CupertinoIcons.mic),
          (NotesFolder.shares, CupertinoIcons.paperclip)])
          FolderRow(icon: icon, title: folder.title, count: count(folder),
            onTap: () => _open(TimelineScreen(relay: relay, folder: folder, picker: widget.picker, sharer: widget.sharer,
              opener: widget.opener))),
      ]),
      ..._section('On this phone', [
        FolderRow(icon: CupertinoIcons.location, title: 'Location', line: locationLine(relay, now),
          onTap: () => _open(LocationPage(relay: relay, scanner: scanner))),
        FolderRow(icon: CupertinoIcons.heart, title: 'Health', line: healthLine(relay, now),
          onTap: () => _open(HealthPage(relay: relay, scanner: scanner))),
        FolderRow(icon: CupertinoIcons.calendar, title: 'Calendar', line: calendarLine(relay, now),
          onTap: () => _open(CalendarPage(relay: relay, scanner: scanner))),
        FolderRow(icon: CupertinoIcons.photo, title: 'Photos', line: photosLine(relay),
          onTap: () => _open(PhotosPage(relay: relay, scanner: scanner, opener: widget.opener))),
      ]),
    ];
  }

  /// A folding header and, unless the person folded it, its card.
  List<Widget> _section(String name, List<Widget> rows) {
    final folded = relay.folded.contains(name);
    return [
      _FoldHeader(name: name, folded: folded, onTap: () => relay.setFolded(name, !folded)),
      if (!folded) _Card(rows: rows),
    ];
  }
}

/// A section name with a chevron that turns as it folds, as in Apple Notes: a tap shows no highlight.
class _FoldHeader extends StatelessWidget {
  const _FoldHeader({required this.name, required this.folded, required this.onTap});

  final String name;
  final bool folded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Semantics(
      button: true,
      expanded: !folded,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 6),
          child: Row(children: [
            Expanded(child: Text(name, style: Theme.of(context).textTheme.titleLarge)),
            AnimatedRotation(
              turns: folded ? -0.25 : 0,
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
              child: Icon(CupertinoIcons.chevron_down, color: brand.accentText),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One card of folder rows, with a line between rows.
class _Card extends StatelessWidget {
  const _Card({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const Divider(height: 1, thickness: 1, indent: 56),
          row,
        ],
      ]),
    );
  }
}
