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

/// The notes, newest first and grouped by day, as Apple Notes lists them: *‹ Home*, a large title with the count and,
/// only when notes wait or can't go, the sync state; the filters *All*, *Voice* and *Photos and files*; and at the
/// bottom *Search*, which finds notes in the picked filter only, and *New note*.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.relay, this.folder = NotesFolder.all, this.picker, this.sharer, this.opener,
    this.onOpen, this.onBack, this.onFilter});

  final Relay relay;
  /// The filter the list opens on.
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
  /// Tells the browser's layout the filter picked, so a note opened and closed comes back to it.
  final ValueChanged<NotesFolder>? onFilter;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  Relay get relay => widget.relay;
  static const _title = 'Notes';
  late NotesFolder _filter = widget.folder;

  /// Pulling the list down: sends what waits and takes notes from the person's other devices. No button does it.
  Future<void> _refresh() => relay.pullNotes();

  @override
  void didUpdateWidget(TimelineScreen old) {
    super.didUpdateWidget(old);
    if (widget.folder != old.folder) _filter = widget.folder;
  }

  void _pick(NotesFolder filter) {
    setState(() => _filter = filter);
    widget.onFilter?.call(filter);
  }

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
          final notes = [for (final entry in relay.entries) if (entryIn(_filter, entry)) entry];
          return Stack(children: [
            RefreshIndicator(
              onRefresh: _refresh,
              edgeOffset: 140,
              child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
                TitleBar(
                  title: _title,
                  relay: relay,
                  count: countOf(notes.length),
                  leading: BackTo('Home', onPressed: widget.onBack),
                  leadingWidth: BackTo.widthOf('Home'),
                ),
                if (modelShows(relay)) modelSliver(relay),
                SliverToBoxAdapter(child: NoteFilters(relay: relay, filter: _filter, onFilter: _pick)),
                if (notes.isEmpty)
                  SliverFillRemaining(hasScrollBody: false,
                    child: _Empty(folder: _filter, sending: relay.settings.sending, web: relay.web))
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

/// *All*, *Voice* and *Photos and files* above the notes, each with how many notes it holds: a tap shows only its notes.
/// The picked one is ink, not the accent, because the accent is for *New note*.
class NoteFilters extends StatelessWidget {
  const NoteFilters({super.key, required this.relay, required this.filter, required this.onFilter});

  final Relay relay;
  final NotesFolder filter;
  final ValueChanged<NotesFolder> onFilter;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(spacing: 8, children: [
        for (final each in NotesFolder.values)
          ChoiceChip(
            label: Text('${each.title} ${relay.entries.where((entry) => entryIn(each, entry)).length}'),
            selected: each == filter,
            showCheckmark: false,
            backgroundColor: brand.card,
            selectedColor: brand.ink,
            labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: each == filter ? brand.paper : brand.ink),
            onSelected: (_) => onFilter(each),
          ),
      ]),
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

/// The top of Home and of the notes list, as Apple Notes has it: a large title with the [SyncLine] under it, which go up
/// with the page and leave one row, the small title with a [_SmallLine] under it. No band stays under that row.
class TitleBar extends StatelessWidget {
  const TitleBar({super.key, required this.title, required this.relay, this.count, this.leading, this.leadingWidth,
    this.actions});

  final String title;
  final Relay relay;
  /// Such as *5 notes*; null on Home, which shows a line only when notes wait or can't go.
  final String? count;
  final Widget? leading;
  final double? leadingWidth;
  final List<Widget>? actions;

  /// The one row that stays: the way back, the small title and its line, and the actions.
  static const toolbar = 64.0;
  /// The open top: the row, the large title, and the [SyncLine].
  static const expanded = 140.0;
  /// The room under the large title when no line is there.
  static const _under = 8.0;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final line = count != null || SyncLine.stateOf(relay) != null;
    return SliverAppBar(
      pinned: true,
      leading: leading,
      leadingWidth: leadingWidth,
      actions: actions,
      toolbarHeight: toolbar,
      // With no line, Home is that much shorter, less the room kept under the title, so it does not float over a blank.
      expandedHeight: line ? expanded : expanded - SyncLine.height + _under,
      flexibleSpace: Builder(builder: (context) {
        final space = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()!;
        final room = space.maxExtent - space.minExtent;
        // 0 while open, 1 once only the row is left.
        final shut = room <= 0 ? 1.0 : (1 - (space.currentExtent - space.minExtent) / room).clamp(0.0, 1.0);
        final top = MediaQuery.paddingOf(context).top;
        final large = (1 - shut * 1.6).clamp(0.0, 1.0);
        final small = ((shut - 0.55) / 0.3).clamp(0.0, 1.0);
        // A title faded out is not built, so a screen reader reads each title once.
        return Stack(children: [
          if (large > 0) Positioned(left: 0, right: 0, top: top + toolbar, bottom: 0,
            child: ClipRect(child: OverflowBox(alignment: Alignment.bottomLeft, minHeight: 0, maxHeight: double.infinity,
              child: Opacity(opacity: large,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, line ? 0 : _under),
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: brand.ink, height: 1.25))),
                  if (line) SyncLine(relay: relay, count: count),
                ]))))),
          if (small > 0) Positioned(left: 0, right: 0, top: top, height: toolbar,
            child: IgnorePointer(
              child: Opacity(opacity: small,
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3,
                    color: brand.ink)),
                  _SmallLine(relay: relay, count: count),
                ]))))),
        ]);
      }),
    );
  }
}

/// The line under the small title: the count alone when all is well, or the state's dot and words, such as *○ 3
/// waiting*, in place of the count. Home, with no count, shows nothing when all is well. Words, not a button.
class _SmallLine extends StatelessWidget {
  const _SmallLine({required this.relay, this.count});

  final Relay relay;
  final String? count;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, height: 1.3, color: brandOf(context).muted);
    final state = SyncLine.stateOf(relay);
    if (state == null) return count == null ? const SizedBox.shrink() : Text(count!, style: muted);
    return Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
      Transform.scale(scale: 0.75, child: _SyncDot(state: state.$1)),
      Text(state.$2, style: muted),
    ]);
  }
}

/// *6 notes* under the list's title, and a state only when notes wait or can't go: *1 waiting* or *Key refused*. When
/// all is sent, or sending is off, it says no state, and Home shows no line, also when the phone is offline. It is words,
/// not a button: notes send by themselves, and a pull down on the page syncs now.
class SyncLine extends StatelessWidget {
  const SyncLine({super.key, required this.relay, this.count});

  final Relay relay;
  /// Such as *6 notes*; null on Home.
  final String? count;

  /// The line's height under a title.
  static const height = 36.0;

  /// The state's dot and words, or null when there is nothing the person can act on: all is sent, sending is off, or it
  /// syncs or is offline with nothing waiting. Offline with notes waiting says *N waiting* with the hollow ring. The dot
  /// pulses only while waiting notes send.
  static (SyncDot, String)? stateOf(Relay relay) {
    if (!relay.settings.sending) return null;
    final waiting = relay.waiting > 0 ? '${relay.waiting} waiting' : null;
    return switch (relay.status) {
      SyncStatus.refused => (SyncDot.refused, relay.web ? 'Not loaded' : 'Key refused'),
      SyncStatus.syncing => waiting == null ? null : (SyncDot.syncing, waiting),
      _ => waiting == null ? null : (SyncDot.waiting, waiting),
    };
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    final strong = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: brand.ink);
    final state = stateOf(relay);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: SizedBox(height: 32, child: Row(spacing: 6, children: [
        if (count case final count?) Text(state == null ? count : '$count ·', style: muted),
        if (state != null) ...[_SyncDot(state: state.$1), Text(state.$2, style: strong)],
      ])),
    );
  }
}

/// The sync state's dot: [syncing] while waiting notes send, [waiting] while they wait, [refused] for the key.
enum SyncDot { syncing, waiting, refused }

/// The sync state's dot: spark with a pulsing ring while waiting notes send, a hollow ring while they wait, danger when
/// the key is refused. It stays still when the phone asks for less motion.
class _SyncDot extends StatefulWidget {
  const _SyncDot({required this.state});

  final SyncDot state;

  @override
  State<_SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends State<_SyncDot> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  void _run() {
    final moves = widget.state == SyncDot.syncing && !MediaQuery.disableAnimationsOf(context);
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
      SyncDot.syncing => brand.spark,
      SyncDot.waiting => Colors.transparent,
      SyncDot.refused => brand.danger,
    };
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: widget.state == SyncDot.waiting ? Border.all(color: brand.muted, width: 2) : null,
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
  NotesFolder.files => ('No photos or files yet', 'A note with a photo or a file shows here.'),
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

/// One note in its day's card: the first line in bold; then the time, a microphone and the length for a voice note, where
/// a note from elsewhere came from, and the rest of the words. No tag: only a note that waits says so, *Waiting to send*.
/// A first picture shows small at the right. A tap opens it; a swipe to the left, or a screen reader's *Delete*, deletes
/// it with *Undo*.
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
    final send = sendState(entry);
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
              if (entry.voice) ...[
                const TextSpan(text: '  '),
                WidgetSpan(alignment: PlaceholderAlignment.middle,
                  child: Icon(CupertinoIcons.mic_fill, size: 14, color: brand.accentText, semanticLabel: 'Voice note')),
                if (entry.length case final length?) TextSpan(text: ' ${clockOf(length)}'),
              ],
              if (entry.from != null) TextSpan(text: ' · ${entry.from}'),
              TextSpan(text: '  ${_preview(entry)}'),
            ]), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: brand.muted)),
            if (entry.writing) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: LinearProgressIndicator()),
            if (send != null) Text(send, style: muted),
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
          // Quiet while typing: the card color, not the green of a form field.
          focusedBorder: border(),
        ),
      ),
    );
  }
}
