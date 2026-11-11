import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../brand.dart';
import '../editor/markdown.dart' show plainText;
import '../relay.dart';
import 'back_to.dart';
import 'days.dart';
import 'folder.dart' show Opener;
import 'hold_to_talk.dart';
import 'note_blocks.dart' show EntryImage;
import 'note_editor.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A row's time: the clock today and yesterday, the weekday this week, else the short date.
String rowTime(BuildContext context, DateTime at, DateTime now) {
  final days = daysAgo(at, now);
  final local = MaterialLocalizations.of(context);
  if (days <= 1) return TimeOfDay.fromDateTime(at).format(context);
  if (days < 7) return _weekdays[at.weekday - 1];
  return at.year == now.year ? local.formatShortMonthDay(at) : local.formatShortDate(at);
}

/// One notes folder's notes, newest first and grouped by day, as Apple Notes lists them: *‹ Home*, a large title with the
/// count and the sync state, and at the bottom *Search*, which finds notes in this folder only, and *New note*.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.relay, this.folder = NotesFolder.all, this.picker, this.sharer, this.opener,
    this.onOpen, this.onBack});

  final Relay relay;
  final NotesFolder folder;
  /// The paperclip's picker; a test passes its own.
  final FilesPicker? picker;
  /// A note's *Share*; a test passes its own.
  final Sharer? sharer;
  /// Opens a link in a note; a test passes its own.
  final Opener? opener;
  /// Opens a note, or a new one for null, where the browser's layout holds it, in place of a new page.
  final NoteOpener? onOpen;
  /// Goes back to Home where the browser's layout holds it.
  final VoidCallback? onBack;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  Relay get relay => widget.relay;
  String get _title => widget.folder.title;

  /// What pulling the list down does, and *Sync now* too.
  /// Pull to refresh and *Sync now* do the same: send what waits and take notes from the person's other devices.
  Future<void> _refresh() => relay.pullNotes();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([relay, _search, _searchFocus]),
        builder: (context, _) {
          final notes = [for (final entry in relay.entries) if (entryIn(widget.folder, entry)) entry];
          return Stack(children: [
            RefreshIndicator(
              onRefresh: _refresh,
              edgeOffset: 140,
              child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
                SliverAppBar.large(
                  leading: BackTo('Home', onPressed: widget.onBack),
                  leadingWidth: BackTo.widthOf('Home'),
                  title: Text(_title),
                  expandedHeight: 140,
                  bottom: PreferredSize(preferredSize: const Size.fromHeight(SyncLine.height),
                    child: SyncLine(relay: relay, count: countOf(notes.length), onSync: _refresh)),
                ),
                if (modelShows(relay)) modelSliver(relay),
                if (notes.isEmpty)
                  SliverFillRemaining(hasScrollBody: false,
                    child: _Empty(folder: widget.folder, sending: relay.settings.sending, web: relay.web))
                else
                  noteSliver(context, relay, notes, _search.text, back: _title, picker: widget.picker, sharer: widget.sharer,
                    opener: widget.opener, onOpen: widget.onOpen),
                const SliverPadding(padding: EdgeInsets.only(bottom: 110)),
              ]),
            ),
            NotesDock(relay: relay, search: _search, focus: _searchFocus,
              onWrite: () => widget.onOpen != null ? widget.onOpen!(null) : openPage(context, NoteEditor(relay: relay,
                picker: widget.picker, sharer: widget.sharer, opener: widget.opener, back: _title))),
          ]);
        },
      ),
    );
  }
}

/// Opens [entry], or a new note for null, where the browser's layout holds it.
typedef NoteOpener = void Function(Entry? entry);

/// Pushes [page] over the one open now.
void openPage(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// *5 notes*, for the line under a folder's title.
String countOf(int notes) => switch (notes) { 0 => 'No notes', 1 => '1 note', final n => '$n notes' };

/// True while the speech model's download runs or failed: its card then shows above the notes.
bool modelShows(Relay relay) => relay.speechModel == ModelState.downloading || relay.speechModel == ModelState.failed;

Widget modelSliver(Relay relay) =>
  SliverPadding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), sliver: SliverToBoxAdapter(child: ModelCard(relay: relay)));

/// [notes] that hold [query], grouped by day, or a line that says none does. A tap opens a note, whose back button
/// says [back], or calls [onOpen]. The [selected] note's row shows it is open.
Widget noteSliver(BuildContext context, Relay relay, List<Entry> notes, String query,
  {required String back, FilesPicker? picker, Sharer? sharer, Opener? opener, NoteOpener? onOpen, String? selected}) {
  final shown = [for (final entry in notes) if (entryMatches(entry, query)) entry];
  if (shown.isEmpty) {
    return SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(32), child: Text('No notes with "${query.trim()}"',
      textAlign: TextAlign.center, style: TextStyle(color: brandOf(context).muted))));
  }
  return SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverList.list(children: [
      for (final (name, group) in groupByDay(shown, DateTime.now()))
        _DayGroup(name: name, children: [
          for (final entry in group)
            _NoteRow(entry: entry, relay: relay, selected: selected != null && entry.id == selected,
              onTap: () => onOpen != null ? onOpen(entry) : openPage(context,
                NoteEditor(entry: entry, relay: relay, picker: picker, sharer: sharer, opener: opener, back: back))),
        ]),
    ]),
  );
}

/// *5 notes · ● Synced ↻* under a title, or the state alone on Home. While sending, *Sync now* follows the state, and a
/// tap on the state syncs too.
class SyncLine extends StatelessWidget {
  const SyncLine({super.key, required this.relay, required this.onSync, this.count});

  final Relay relay;
  /// What *Sync now* and a tap on the state do: the same as the page's pull to refresh.
  final Future<void> Function() onSync;
  /// Such as *5 notes*; null on Home.
  final String? count;

  /// The line's height under an app bar: room for *Sync now*'s 32-point tap target.
  static const height = 36.0;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    final strong = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: brand.ink);
    final (state, label) = switch (relay.status) {
      SyncStatus.syncing => (_Dot.syncing, 'Syncing'),
      SyncStatus.refused => (_Dot.refused, relay.web ? 'Not loaded' : 'Key refused'),
      SyncStatus.offline => (_Dot.waiting, relay.waiting > 0 ? '${relay.waiting} waiting' : 'Offline'),
      _ => relay.waiting > 0 ? (_Dot.waiting, '${relay.waiting} waiting') : (_Dot.synced, 'Synced'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: SizedBox(height: 32, child: Row(spacing: 6, children: [
        if (count != null) Text('$count ·', style: muted),
        if (!relay.settings.sending)
          Text('On this phone', style: strong)
        else ...[
          InkWell(
            onTap: onSync,
            borderRadius: BorderRadius.circular(8),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [_SyncDot(state: state), Text(label, style: strong)]),
          ),
          _SyncNow(syncing: relay.status == SyncStatus.syncing, onSync: onSync),
        ],
      ])),
    );
  }
}

/// *Sync now*: small muted arrows after the state, which turn while the phone syncs, and stay still when the phone asks
/// for less motion.
class _SyncNow extends StatefulWidget {
  const _SyncNow({required this.syncing, required this.onSync});

  final bool syncing;
  final Future<void> Function() onSync;

  @override
  State<_SyncNow> createState() => _SyncNowState();
}

class _SyncNowState extends State<_SyncNow> with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  void _run() {
    final moves = widget.syncing && !MediaQuery.disableAnimationsOf(context);
    if (moves && !_turn.isAnimating) _turn.repeat();
    if (!moves) _turn.reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  @override
  void didUpdateWidget(_SyncNow old) {
    super.didUpdateWidget(old);
    _run();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Sync now',
      onPressed: widget.onSync,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      icon: RotationTransition(turns: _turn,
        child: Icon(CupertinoIcons.arrow_2_circlepath, size: 16, color: brandOf(context).muted)),
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

/// What an empty [folder] says: its title, then how a note gets in it. In the browser no hold talks.
(String, String) emptyFolderText(NotesFolder folder, {bool web = false}) => switch (folder) {
  NotesFolder.all when web => ('No notes yet', 'Click New note to write one.'),
  NotesFolder.voice when web => ('No voice notes yet', 'Voice notes you say into your phone show here.'),
  NotesFolder.all => ('No notes yet', 'Tap New note to write one, or hold it to talk.'),
  NotesFolder.voice => ('No voice notes yet', 'Hold New note to talk.'),
  NotesFolder.shares => ('No shares yet', 'A note with a photo, a file or a link shows here.'),
};

/// An empty folder: what goes in it, above the button that makes it.
class _Empty extends StatelessWidget {
  const _Empty({required this.folder, required this.sending, this.web = false});

  final NotesFolder folder;
  final bool sending;
  /// In the browser no hold talks, and voice notes come from the phone.
  final bool web;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: brandOf(context).muted, height: 1.45);
    final (title, how) = emptyFolderText(folder, web: web);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 110),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 10, children: [
        const RelayMark(size: 56),
        Text(title, style: theme.textTheme.titleLarge),
        Text(how, style: muted, textAlign: TextAlign.center),
        if (!sending) Text('Notes stay on this phone until you sign in, in Settings.', style: muted, textAlign: TextAlign.center),
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
  final first = plainText(entry.text).trim().split('\n').first.trim();
  if (first.isNotEmpty) return first;
  if (entry.writing) return 'Writing the words…';
  if (entry.failed) return 'The words did not come';
  if (entry.files.isNotEmpty) return entry.files.first.name;
  return entry.voice ? 'Voice note' : '';
}

/// What follows the time on a row: the rest of the words, or else the file names the title does not show.
String _preview(Entry entry) {
  final rest = plainText(entry.text).trim().split('\n').skip(1).map((line) => line.trim()).where((line) => line.isNotEmpty).join(' ');
  if (rest.isNotEmpty || entry.text.trim().isNotEmpty) return rest;
  return entry.files.skip(1).map((file) => file.name).join(', ');
}

/// *Note deleted* with *Undo* for [undoTime], after a swipe or ⋯ → *Delete*. It takes the messenger, as the note page
/// that deletes may be gone when it shows. The delete runs when the bar closes with no *Undo*, never while it shows:
/// the bar's own time starts only once it is in.
void showDeleted(ScaffoldMessengerState? messenger, Relay relay, String id) {
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  final bar = messenger.showSnackBar(SnackBar(content: const Text('Note deleted'), duration: undoTime, persist: false,
    action: SnackBarAction(label: 'Undo', onPressed: () => unawaited(relay.undoDelete(id)))));
  unawaited(bar.closed.then((reason) {
    if (reason != SnackBarClosedReason.action) unawaited(relay.endUndo(id));
  }));
}

/// One note in its day's card: the first line in bold; the time, where a note from elsewhere came from, and the rest of
/// the words; then its kind, *No words heard* for a watch note with none, length, place and send state. A first picture
/// shows small at the right. A tap opens it; a swipe to the left, or a screen reader's *Delete*, deletes it with *Undo*.
class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.entry, required this.relay, required this.onTap, this.selected = false});

  final Entry entry;
  final Relay relay;
  /// The note open beside the list in the browser's wide layout.
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    final meta = [if (entry.noWords) 'No words heard', if (entry.length != null) clockOf(entry.length!), sendState(entry)]
      .whereType<String>();
    final picture = entry.files.where((file) => file.picture && file.ready).firstOrNull;
    final row = Material(color: selected ? brand.accentSoft : Colors.transparent, child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(spacing: 12, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(noteTitle(entry), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight(650))),
            Text.rich(TextSpan(children: [
              TextSpan(text: rowTime(context, entry.at, DateTime.now()), style: TextStyle(fontWeight: FontWeight.w500, color: brand.ink)),
              if (entry.from != null) TextSpan(text: ' · ${entry.from}'),
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
    ));
    if (entry.id.isEmpty) return row;
    // A node of its own, so a screen reader's *Delete* is on this row, not on the whole card.
    return Semantics(
      container: true,
      customSemanticsActions: {const CustomSemanticsAction(label: 'Delete'): () => _delete(context)},
      child: Dismissible(
        key: ValueKey('note:${entry.id}'),
        direction: DismissDirection.endToStart,
        background: ColoredBox(color: brand.danger, child: Align(alignment: Alignment.centerRight,
          child: Padding(padding: const EdgeInsets.only(right: 24), child: Icon(CupertinoIcons.trash, color: brand.onDanger)))),
        onDismissed: (_) => _delete(context),
        child: row,
      ),
    );
  }

  void _delete(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    unawaited(relay.deleteNote(entry.id));
    showDeleted(messenger, relay, entry.id);
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
        child: EntryImage(file: file, width: 48, height: 48, cacheWidth: 144,
          fallback: Container(width: 48, height: 48, color: brand.accentSoft, child: Icon(CupertinoIcons.photo, color: brand.muted))),
      ),
    );
  }
}

/// The bottom of Home and of a notes list, over a fade to paper: *Search*, and beside it *New note* or, while searching,
/// *Cancel*.
class NotesDock extends StatelessWidget {
  const NotesDock({super.key, required this.relay, required this.search, required this.focus, required this.onWrite});

  final Relay relay;
  final TextEditingController search;
  final FocusNode focus;
  final VoidCallback onWrite;

  void _endSearch() {
    search.clear();
    focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final paper = brandOf(context).paper;
    final searching = focus.hasFocus || search.text.isNotEmpty;
    return Positioned(left: 0, right: 0, bottom: 0, child: DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [paper.withValues(alpha: 0), paper], stops: const [0, 0.3])),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(spacing: 10, children: [
            Expanded(child: _SearchField(controller: search, focus: focus)),
            if (searching)
              TextButton(onPressed: _endSearch, child: const Text('Cancel', style: TextStyle(fontSize: 16)))
            else
              NewNoteButton(relay: relay, onWrite: onWrite),
          ]),
        ),
      ),
    ));
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
          prefixIcon: Icon(CupertinoIcons.search, size: 20, color: brand.muted),
          suffixIcon: controller.text.isEmpty ? null : IconButton(tooltip: 'Clear', onPressed: controller.clear,
            icon: Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: brand.muted)),
          enabledBorder: border(),
          focusedBorder: border(BorderSide(color: brand.accentText, width: 2)),
        ),
      ),
    );
  }
}
