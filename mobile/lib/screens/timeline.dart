import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../relay.dart';
import 'compose.dart';
import 'connect.dart' show Scanner;
import 'days.dart';
import 'hold_to_talk.dart';
import 'note.dart';
import 'settings.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A row's time: the clock today and yesterday, the weekday this week, else the short date.
String rowTime(BuildContext context, DateTime at, DateTime now) {
  final days = daysAgo(at, now);
  final local = MaterialLocalizations.of(context);
  if (days <= 1) return TimeOfDay.fromDateTime(at).format(context);
  if (days < 7) return _weekdays[at.weekday - 1];
  return at.year == now.year ? local.formatShortMonthDay(at) : local.formatShortDate(at);
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

/// This phone's notes, newest first and grouped by day, as Apple Notes lists them: a large *Notes* title with the count
/// and the sync state, the ⋯ menu, and at the bottom *Search* and the one main action, *New note*.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.relay, this.scanner, this.opener, this.picker, this.voiceRequests});

  final Relay relay;
  /// The QR scanner the connect screen uses; a test passes its own.
  final Scanner? scanner;
  /// Opens the Relay Everything page; a test passes its own.
  final Opener? opener;
  /// The paperclip's picker; a test passes its own.
  final FilesPicker? picker;
  /// *Start a voice note* from Shortcuts: each event starts one in the listening card.
  final Stream<void>? voiceRequests;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
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

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  void _write() => _open(ComposeScreen(relay: relay, picker: widget.picker));

  void _settings() => _open(SettingsScreen(relay: relay, scanner: widget.scanner));

  Future<void> _openPage(String server) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await (widget.opener ?? _openInBrowser)(Uri.parse('$server/apps/relay/'))) {
      messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
    }
  }

  void _endSearch() {
    _search.clear();
    _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([relay, _search, _searchFocus]),
        builder: (context, _) {
          final searching = _searchFocus.hasFocus || _search.text.isNotEmpty;
          return Stack(children: [
            RefreshIndicator(
              onRefresh: relay.sync,
              edgeOffset: 140,
              child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
                _bar(context),
                ..._body(context),
                const SliverPadding(padding: EdgeInsets.only(bottom: 110)),
              ]),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _Dock(
              search: _SearchField(controller: _search, focus: _searchFocus),
              action: searching
                ? TextButton(onPressed: _endSearch, child: const Text('Cancel', style: TextStyle(fontSize: 16)))
                : NewNoteButton(relay: relay, onWrite: _write),
            )),
          ]);
        },
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final settings = relay.settings;
    final server = relay.server;
    return SliverAppBar.large(
      leading: const Center(child: RelayMark(size: 24)),
      title: const Text('Notes'),
      expandedHeight: 140,
      actions: [
        _MoreMenu(items: [
          ('Settings', Icons.settings_outlined, _settings),
          if (settings.sending) ('Sync now', Icons.sync, relay.sync),
          // Ring notes and recordings are on the Relay Everything page; nothing of this phone's goes there while it
          // sends to the person's own webhook.
          if (settings.sending && settings.place == SendPlace.server && server != null)
            ('Open your Relay Everything page', Icons.open_in_new, () => _openPage(server)),
        ]),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(preferredSize: const Size.fromHeight(28), child: _CountLine(relay: relay)),
    );
  }

  List<Widget> _body(BuildContext context) {
    final model = relay.speechModel == ModelState.downloading || relay.speechModel == ModelState.failed;
    final entries = relay.entries;
    final shown = [for (final entry in entries) if (entryMatches(entry, _search.text)) entry];
    return [
      if (model) SliverPadding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), sliver: SliverToBoxAdapter(child: ModelCard(relay: relay))),
      if (entries.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: _Empty(sending: relay.settings.sending))
      else if (shown.isEmpty)
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(32), child: Text('No notes with "${_search.text.trim()}"',
          textAlign: TextAlign.center, style: TextStyle(color: brandOf(context).muted))))
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(children: [
            for (final (name, notes) in groupByDay(shown, DateTime.now()))
              _DayGroup(name: name, children: [
                for (final entry in notes)
                  _NoteRow(entry: entry, relay: relay, onTap: () => _open(NoteScreen(entry: entry, relay: relay))),
              ]),
          ]),
        ),
    ];
  }
}

/// The ⋯ button and its menu: each item a word, an icon and what it does.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.items});

  final List<(String, IconData, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return MenuAnchor(
      menuChildren: [
        for (final (label, icon, act) in items)
          MenuItemButton(leadingIcon: Icon(icon, size: 20, color: brand.muted), onPressed: act,
            child: Padding(padding: const EdgeInsets.only(right: 16), child: Text(label, style: const TextStyle(fontSize: 16)))),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: 'More',
        style: IconButton.styleFrom(backgroundColor: brand.card, foregroundColor: brand.ink),
        icon: const Icon(Icons.more_horiz),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

/// *5 notes · ● Synced* under the title. While sending, the state is a button that syncs now.
class _CountLine extends StatelessWidget {
  const _CountLine({required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    final strong = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: brand.ink);
    final count = switch (relay.entries.length) { 0 => 'No notes', 1 => '1 note', final n => '$n notes' };
    final (state, label) = switch (relay.status) {
      SyncStatus.syncing => (_Dot.syncing, 'Syncing'),
      SyncStatus.refused => (_Dot.refused, 'Key refused'),
      SyncStatus.offline => (_Dot.waiting, relay.waiting > 0 ? '${relay.waiting} waiting' : 'Offline'),
      _ => relay.waiting > 0 ? (_Dot.waiting, '${relay.waiting} waiting') : (_Dot.synced, 'Synced'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(spacing: 6, children: [
        Text('$count ·', style: muted),
        if (!relay.settings.sending)
          Text('On this phone', style: strong)
        else
          Tooltip(message: 'Sync now', child: InkWell(
            onTap: relay.sync,
            borderRadius: BorderRadius.circular(8),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [_SyncDot(state: state), Text(label, style: strong)]),
          )),
      ]),
    );
  }
}

enum _Dot { synced, syncing, waiting, refused }

/// The sync state's dot: accent and still when synced, spark with a pulsing ring while syncing, a hollow ring while
/// notes wait, danger when the key is refused. It stays still when the phone asks for less motion.
class _SyncDot extends StatefulWidget {
  const _SyncDot({required this.state});

  final _Dot state;

  @override
  State<_SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends State<_SyncDot> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  void _run() {
    final moves = widget.state == _Dot.syncing && !MediaQuery.disableAnimationsOf(context);
    if (moves && !_pulse.isAnimating) _pulse.repeat();
    if (!moves) _pulse.reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  @override
  void didUpdateWidget(_SyncDot old) {
    super.didUpdateWidget(old);
    _run();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final fill = switch (widget.state) {
      _Dot.synced => brand.accent,
      _Dot.syncing => brand.spark,
      _Dot.waiting => Colors.transparent,
      _Dot.refused => brand.danger,
    };
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: widget.state == _Dot.waiting ? Border.all(color: brand.muted, width: 2) : null,
          boxShadow: _pulse.isAnimating
            ? [BoxShadow(color: brand.spark.withValues(alpha: 1 - _pulse.value), spreadRadius: 7 * _pulse.value)]
            : null,
        ),
      ),
    );
  }
}

/// The first open: what to do, above the button that does it.
class _Empty extends StatelessWidget {
  const _Empty({required this.sending});

  final bool sending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: brandOf(context).muted, height: 1.45);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 110),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 10, children: [
        const RelayMark(size: 56),
        Text('No notes yet', style: theme.textTheme.titleLarge),
        Text('Tap New note to write one, or hold it to talk.', style: muted, textAlign: TextAlign.center),
        if (!sending) Text('Notes stay on this phone until you turn on sending in Settings.', style: muted,
          textAlign: TextAlign.center),
      ]),
    );
  }
}

/// One day group: its heading, and one card with a row per note.
class _DayGroup extends StatelessWidget {
  const _DayGroup({required this.name, required this.children});

  final String name;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(2, 12, 2, 6), child: Text(name, style: Theme.of(context).textTheme.titleLarge)),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (index, row) in children.indexed) ...[
            if (index > 0) const Divider(height: 1, thickness: 1, indent: 16),
            row,
          ],
        ]),
      ),
    ]);
  }
}

/// A note's first line: its words' first line, or what stands for it while it has no words.
String noteTitle(Entry entry) {
  final first = entry.text.trim().split('\n').first.trim();
  if (first.isNotEmpty) return first;
  if (entry.writing) return 'Writing the words…';
  if (entry.files.isNotEmpty) return entry.files.first.name;
  return entry.voice ? 'Voice note' : '';
}

/// What follows the time on a row: the rest of the words, or else the file names the title does not show.
String _preview(Entry entry) {
  final rest = entry.text.trim().split('\n').skip(1).map((line) => line.trim()).where((line) => line.isNotEmpty).join(' ');
  if (rest.isNotEmpty || entry.text.trim().isNotEmpty) return rest;
  return entry.files.skip(1).map((file) => file.name).join(', ');
}

/// One note in its day's card: the first line in bold; the time and the rest of the words; then its kind, length,
/// place and send state. A first picture shows small at the right. A tap opens the note.
class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.entry, required this.relay, required this.onTap});

  final Entry entry;
  final Relay relay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    final meta = [if (entry.length != null) clockOf(entry.length!), entry.place, sendState(entry)].whereType<String>();
    final picture = entry.files.where((file) => file.picture).firstOrNull;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(spacing: 12, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(noteTitle(entry), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight(650))),
            Text.rich(TextSpan(children: [
              TextSpan(text: rowTime(context, entry.at, DateTime.now()), style: TextStyle(fontWeight: FontWeight.w500, color: brand.ink)),
              TextSpan(text: '  ${_preview(entry)}'),
            ]), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: brand.muted)),
            if (entry.writing) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: LinearProgressIndicator()),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(spacing: 6, children: [
                BrandTag(entry.voice ? 'Voice' : 'Typed', spark: entry.voice),
                if (meta.isNotEmpty) Flexible(child: Text(meta.join(' · '), style: muted, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ])),
          if (picture != null) _Thumbnail(file: picture),
        ]),
      ),
    );
  }
}

/// A note's first picture, small, at the right of its row.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.file});

  final EntryFile file;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Tooltip(
      message: file.name,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(File(file.path), width: 48, height: 48, fit: BoxFit.cover, cacheWidth: 144,
          errorBuilder: (context, _, _) => Container(width: 48, height: 48, color: brand.accentSoft,
            child: Icon(Icons.image_outlined, color: brand.muted))),
      ),
    );
  }
}

/// The bottom of the notes list, over a fade to paper: *Search*, and beside it *New note* or, while searching, *Cancel*.
class _Dock extends StatelessWidget {
  const _Dock({required this.search, required this.action});

  final Widget search;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final paper = brandOf(context).paper;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [paper.withValues(alpha: 0), paper], stops: const [0, 0.3])),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(spacing: 10, children: [Expanded(child: search), action]),
        ),
      ),
    );
  }
}

/// *Search*: it filters the list as the person types, on this phone only.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focus});

  final TextEditingController controller;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    OutlineInputBorder border([BorderSide side = BorderSide.none]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: side);
    return SizedBox(
      height: 48,
      child: TextField(
        controller: controller,
        focusNode: focus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search',
          filled: true,
          fillColor: brand.card,
          contentPadding: EdgeInsets.zero,
          prefixIcon: Icon(Icons.search, size: 20, color: brand.muted),
          suffixIcon: controller.text.isEmpty ? null : IconButton(tooltip: 'Clear', onPressed: controller.clear,
            icon: Icon(Icons.cancel, size: 18, color: brand.muted)),
          enabledBorder: border(),
          focusedBorder: border(BorderSide(color: brand.accentText, width: 2)),
        ),
      ),
    );
  }
}
