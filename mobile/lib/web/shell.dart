import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../data/client_id.dart';
import '../relay.dart';
import '../screens/back_to.dart';
import '../screens/days.dart';
import '../screens/folder.dart';
import '../screens/home.dart';
import '../screens/note_editor.dart';
import '../screens/round_button.dart';
import '../screens/timeline.dart';
import 'chats.dart';
import 'connection_page.dart';
import 'drops.dart';
import 'settings_dialog.dart';
import 'space.dart';

/// From this width the browser shows three panes: the left bar, the notes and the open note.
const threePanes = 1000.0;

/// From this width it shows two panes, with the left bar in a menu; below it, the phone's pages.
const twoPanes = 700.0;

/// What the left bar has open: a notes folder, one of *Other connections*, or the chats.
sealed class WebPlace {
  const WebPlace();
}

class FolderPlace extends WebPlace {
  const FolderPlace(this.folder);

  final NotesFolder folder;
}

class ConnectionPlace extends WebPlace {
  const ConnectionPlace(this.kind);

  final ConnectionKind kind;
}

class ChatsPlace extends WebPlace {
  const ChatsPlace();

  /// The page's part of the address that opens the chats: the phone's *Read them on the web* opens `/#chats`.
  static const part = 'chats';
}

/// The place an address's part names, such as `chats` or the app's own `/chats`; null for any other part.
WebPlace? placeOfPart(String part) => (part.startsWith('/') ? part.substring(1) : part) == ChatsPlace.part
  ? const ChatsPlace() : null;

/// The connections the left bar lists under *Other connections*, with their names and icons.
const _connections = [
  (ConnectionKind.location, 'Location', CupertinoIcons.location),
  (ConnectionKind.health, 'Health', CupertinoIcons.heart),
  (ConnectionKind.calendar, 'Calendar', CupertinoIcons.calendar),
  (ConnectionKind.photos, 'Photos', CupertinoIcons.photo),
];

const _folderIcons = {
  NotesFolder.all: CupertinoIcons.doc_text, NotesFolder.voice: CupertinoIcons.mic, NotesFolder.shares: CupertinoIcons.paperclip,
};

/// The Relay Everything page in the browser: three panes when wide, two from [twoPanes], and the phone's pages below
/// it. It holds the open note in one place, so a resize keeps the note and the words not yet saved.
class WebShell extends StatefulWidget {
  const WebShell({super.key, required this.relay, required this.client, this.opener, this.picker, this.sharer, this.drops,
    this.settingsAt, this.placeAt});

  final Relay relay;
  final SpaceClient client;
  /// Opens a link; a test passes its own.
  final Opener? opener;
  final FilesPicker? picker;
  final Sharer? sharer;
  /// Files dropped on the page; the browser's own events when null.
  final Stream<List<NewFile>>? drops;
  /// The Settings page the page's address named, such as `#webhooks`: Settings opens on it once the notes show.
  final SettingsPage? settingsAt;
  /// The place the page's address named, such as `#chats`: the page opens on it in place of the notes.
  final WebPlace? placeAt;

  @override
  State<WebShell> createState() => WebShellState();
}

class WebShellState extends State<WebShell> {
  late WebPlace _place = widget.placeAt ?? const FolderPlace(NotesFolder.all);
  /// On the phone's pages: Home shows, not a folder.
  late bool _home = widget.placeAt == null;
  /// The note open now, or null with [_open] for a new one.
  Entry? _entry;
  bool _open = false;
  /// The wide layouts open the newest note once, at the start.
  bool _openedFirst = false;
  bool _homeShows = false;
  /// The phone's pages show: their own search field takes the person's taps, and Ctrl+F stays the browser's.
  bool _narrowNow = false;
  var _editor = GlobalKey<NoteEditorState>();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  StreamSubscription<List<NewFile>>? _drops;
  late final StreamSubscription<String> _notices;
  late final AppLifecycleListener _lifecycle;

  Relay get relay => widget.relay;
  NotesFolder get _folder => switch (_place) { FolderPlace(:final folder) => folder, _ => NotesFolder.all };

  @override
  void initState() {
    super.initState();
    _drops = (widget.drops ?? fileDrops()).listen(_dropped);
    // Back to the tab, or to the window: the notes changed elsewhere meanwhile show, as the phone reads them on resume.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(relay.sync()));
    // Home shows its own notices on the phone's pages.
    _notices = relay.notices.listen((message) {
      if (mounted && !_homeShows) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    if (widget.settingsAt case final page?) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _settings(page); });
    }
  }

  @override
  void dispose() {
    _drops?.cancel();
    _notices.cancel();
    _lifecycle.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Opens [entry], or a new note for null, with a new editor: the one before saves as it closes.
  void openNote(Entry? entry) => setState(() {
    _entry = entry;
    _open = true;
    _openedFirst = true;
    _editor = GlobalKey<NoteEditorState>();
  });

  void _close() => setState(() {
    _entry = null;
    _open = false;
    _openedFirst = true;
  });

  void _go(WebPlace place) {
    if (_scaffold.currentState?.isDrawerOpen ?? false) _scaffold.currentState!.closeDrawer();
    setState(() {
      _place = place;
      _home = false;
      if (place is! FolderPlace) _open = false;
    });
  }

  void _goHome() => setState(() => _home = true);

  Future<void> _settings([SettingsPage first = SettingsPage.account]) =>
    showSettingsDialog(context, relay: relay, client: widget.client, opener: widget.opener, first: first);

  /// Files dropped on the page join the open note, or start a new one.
  Future<void> _dropped(List<NewFile> files) async {
    if (files.isEmpty || !mounted) return;
    final editor = _editor.currentState;
    if (_open && editor != null) return editor.addFiles(files);
    final id = newClientId();
    final problem = await relay.addNote('', files: files, id: id);
    if (!mounted) return;
    if (problem != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    final added = relay.entries.where((entry) => entry.id == id).firstOrNull;
    if (added != null) openNote(added);
  }

  /// New note, search and delete; bold and italic are the editor's own. The editor passes these keys up to here.
  KeyEventResult _key(FocusNode _, KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    if (event is! KeyDownEvent || !(keys.isControlPressed || keys.isMetaPressed)) return KeyEventResult.ignored;
    final key = event.physicalKey;
    if (key == PhysicalKeyboardKey.keyN && keys.isAltPressed) {
      openNote(null);
    } else if (key == PhysicalKeyboardKey.keyF && !keys.isAltPressed && !keys.isShiftPressed && !_narrowNow) {
      if (_place is FolderPlace) {
        _searchFocus.requestFocus();
      } else {
        _go(FolderPlace(_folder));
        WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
      }
    } else if (key == PhysicalKeyboardKey.backspace && keys.isShiftPressed && _open) {
      _editor.currentState?.delete();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: LayoutBuilder(builder: (context, size) {
        final width = size.maxWidth;
        _narrowNow = width < twoPanes;
        _homeShows = _narrowNow && !_open && _home;
        if (_narrowNow) return _narrow();
        return ListenableBuilder(listenable: relay, builder: (context, _) => _wide(width >= threePanes));
      }),
    );
  }

  /// Three panes, or two with the left bar in a menu.
  Widget _wide(bool three) {
    final brand = brandOf(context);
    final notes = [for (final entry in relay.entries) if (entryIn(_folder, entry)) entry];
    if (!_openedFirst && !_open && _place is FolderPlace && notes.isNotEmpty) {
      _openedFirst = true;
      _open = true;
      _entry = notes.first;
    }
    final sidebar = Sidebar(relay: relay, place: _place, onGo: _go, onSettings: _settings);
    final menu = three ? null : () => _scaffold.currentState?.openDrawer();
    return Scaffold(
      key: _scaffold,
      backgroundColor: brand.paper,
      drawer: three ? null : Drawer(backgroundColor: brand.paper, child: SafeArea(child: sidebar)),
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (three) ...[SizedBox(width: 250, child: SafeArea(right: false, child: sidebar)), VerticalDivider(width: 1, color: brand.line)],
        ...switch (_place) {
          FolderPlace() => [
            SizedBox(width: three ? 340 : 320,
              child: NotesPane(relay: relay, folder: _folder, notes: notes, search: _search, selected: _openId, onOpen: openNote,
                onMenu: menu, picker: widget.picker, sharer: widget.sharer, opener: widget.opener)),
            VerticalDivider(width: 1, color: brand.line),
            Expanded(child: _open ? _editorOf(pane: true) : _noNote()),
          ],
          ConnectionPlace(:final kind) => [Expanded(child: _withMenu(menu,
            ConnectionPage(kind: kind, client: widget.client, opener: widget.opener)))],
          ChatsPlace() => [Expanded(child: _withMenu(menu, ChatsView(client: widget.client, wide: true, opener: widget.opener)))],
        },
      ]),
    );
  }

  String? get _openId => _open ? _editor.currentState?.id ?? _entry?.id : null;

  /// A page of the two-pane layout, with the button that opens the left bar.
  Widget _withMenu(VoidCallback? menu, Widget page) => menu == null ? page : Stack(children: [
    Positioned.fill(child: page),
    Positioned(left: 8, top: 8, child: SafeArea(child: IconButton(tooltip: 'Folders', onPressed: menu,
      icon: const Icon(CupertinoIcons.sidebar_left)))),
  ]);

  Widget _editorOf({required bool pane, String back = 'Notes'}) => NoteEditor(key: _editor, relay: relay, entry: _entry,
    pane: pane, back: back, onClose: _close, onCompose: () => openNote(null), search: pane ? _searchField() : null,
    picker: widget.picker, sharer: widget.sharer, opener: widget.opener);

  Widget _searchField() => SearchField(controller: _search, focus: _searchFocus);

  /// The note pane with no note open: the top bar, and a line that says what to do.
  Widget _noNote() {
    final brand = brandOf(context);
    return Scaffold(
      backgroundColor: brand.paper,
      appBar: PreferredSize(preferredSize: const Size.fromHeight(64), child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(spacing: 10, children: [
          ButtonPill(children: [PillIconButton(icon: CupertinoIcons.square_pencil, tooltip: 'New note',
            onPressed: () => openNote(null))]),
          const Spacer(),
          _searchField(),
        ]),
      )),
      body: Center(child: Text('Pick a note, or start a new one.', style: TextStyle(color: brand.muted))),
    );
  }

  /// The phone's pages: Home, a folder, a note, a connection or the chats, one at a time.
  Widget _narrow() {
    if (_open) {
      return PopScope(canPop: false, onPopInvokedWithResult: (popped, _) { if (!popped) _close(); },
        child: _editorOf(pane: false, back: _home ? 'Home' : _folder.title));
    }
    if (_home) {
      return HomeScreen(relay: relay, opener: widget.opener, picker: widget.picker, sharer: widget.sharer, onOpen: openNote,
        onFolder: (folder) => _go(FolderPlace(folder)), onSettings: _settings, otherConnections: [
          for (final (kind, title, icon) in _connections)
            FolderRow(icon: icon, title: title, onTap: () => _go(ConnectionPlace(kind))),
          FolderRow(icon: CupertinoIcons.chat_bubble_2, title: 'AI chat transcripts', line: 'Claude Code and Codex',
            onTap: () => _go(const ChatsPlace())),
        ]);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (popped, _) { if (!popped) _goHome(); },
      child: switch (_place) {
        FolderPlace(:final folder) => TimelineScreen(relay: relay, folder: folder, picker: widget.picker, sharer: widget.sharer,
          opener: widget.opener, onOpen: openNote, onBack: _goHome),
        ConnectionPlace(:final kind) => _page(ConnectionPage(kind: kind, client: widget.client, opener: widget.opener)),
        ChatsPlace() => _page(ChatsView(client: widget.client, wide: false, opener: widget.opener)),
      },
    );
  }

  /// A connection or the chats on the phone's pages, under *‹ Home*.
  Widget _page(Widget body) => Scaffold(
    appBar: AppBar(leading: BackTo('Home', onPressed: _goHome), leadingWidth: BackTo.widthOf('Home')),
    body: body,
  );
}

/// The left bar: the notes folders with their counts, *Other connections*, and *Settings* at the bottom.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.relay, required this.place, required this.onGo, required this.onSettings});

  final Relay relay;
  final WebPlace place;
  final ValueChanged<WebPlace> onGo;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final text = Theme.of(context).textTheme;
    int count(NotesFolder folder) => relay.entries.where((entry) => entryIn(folder, entry)).length;
    bool on(WebPlace other) => switch ((place, other)) {
      (FolderPlace(folder: final a), FolderPlace(folder: final b)) => a == b,
      (ConnectionPlace(kind: final a), ConnectionPlace(kind: final b)) => a == b,
      (ChatsPlace(), ChatsPlace()) => true,
      _ => false,
    };
    Widget row(IconData icon, String title, WebPlace? to, {int? count, VoidCallback? onTap}) {
      final open = to != null && on(to);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Material(
          color: open ? brand.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap ?? () => onGo(to!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(spacing: 12, children: [
                Icon(icon, size: 19, color: open ? brand.accentText : brand.muted),
                Expanded(child: Text(title, style: text.bodyLarge?.copyWith(color: brand.ink,
                  fontWeight: open ? FontWeight.w600 : null))),
                if (count != null) Text('$count', style: text.bodyMedium?.copyWith(color: brand.muted)),
              ]),
            ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 16, 16), child: Row(spacing: 10, children: [
          const RelayMark(size: 26),
          Flexible(child: Text('Relay Everything', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
        ])),
        for (final folder in NotesFolder.values) row(_folderIcons[folder]!, folder.title, FolderPlace(folder), count: count(folder)),
        Padding(padding: const EdgeInsets.fromLTRB(22, 20, 16, 6),
          child: Text('Other connections', style: text.labelLarge?.copyWith(color: brand.muted))),
        for (final (kind, title, icon) in _connections) row(icon, title, ConnectionPlace(kind)),
        row(CupertinoIcons.chat_bubble_2, 'AI chat transcripts', const ChatsPlace()),
      ])),
      Divider(height: 1, color: brand.line),
      const SizedBox(height: 8),
      row(CupertinoIcons.gear, 'Settings', null, onTap: onSettings),
      const SizedBox(height: 12),
    ]);
  }
}

/// The middle pane: the folder's name, its count and the sync state, then its notes by day, filtered by the top bar's
/// search.
class NotesPane extends StatelessWidget {
  const NotesPane({super.key, required this.relay, required this.folder, required this.notes, required this.search,
    required this.onOpen, this.selected, this.onMenu, this.picker, this.sharer, this.opener});

  final Relay relay;
  final NotesFolder folder;
  final List<Entry> notes;
  final TextEditingController search;
  final NoteOpener onOpen;
  final String? selected;
  /// Opens the left bar in the two-pane layout.
  final VoidCallback? onMenu;
  final FilesPicker? picker;
  final Sharer? sharer;
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(listenable: search, builder: (context, _) => CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(8, 14, 12, 0), child: Row(children: [
        if (onMenu != null) IconButton(tooltip: 'Folders', onPressed: onMenu, icon: const Icon(CupertinoIcons.sidebar_left)),
        Expanded(child: Padding(padding: EdgeInsets.only(left: onMenu == null ? 12 : 4),
          child: Text(folder.title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)))),
      ]))),
      SliverToBoxAdapter(child: SyncLine(relay: relay, count: countOf(notes.length), onSync: relay.pullNotes)),
      if (notes.isEmpty && search.text.trim().isEmpty)
        SliverToBoxAdapter(child: _EmptyFolder(folder: folder))
      else
        noteSliver(context, relay, notes, search.text, back: folder.title, picker: picker, sharer: sharer, opener: opener,
          onOpen: onOpen, selected: selected),
      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
    ]));
  }
}

/// An empty folder in the middle pane: its title, then how a note gets in it.
class _EmptyFolder extends StatelessWidget {
  const _EmptyFolder({required this.folder});

  final NotesFolder folder;

  @override
  Widget build(BuildContext context) {
    final (title, how) = emptyFolderText(folder, web: true);
    final text = Theme.of(context).textTheme;
    return Padding(padding: const EdgeInsets.fromLTRB(24, 40, 24, 0), child: Column(spacing: 6, children: [
      Text(title, textAlign: TextAlign.center, style: text.titleMedium),
      Text(how, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: brandOf(context).muted)),
    ]));
  }
}

/// *Search* at the right of the top bar: it filters the notes list as the person types.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, required this.focus});

  final TextEditingController controller;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return SizedBox(width: 240, height: 40, child: ListenableBuilder(listenable: controller, builder: (context, _) => TextField(
      controller: controller,
      focusNode: focus,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search',
        isDense: true,
        filled: true,
        fillColor: brand.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        prefixIcon: Icon(CupertinoIcons.search, size: 18, color: brand.muted),
        suffixIcon: controller.text.isEmpty ? null : IconButton(tooltip: 'Clear', onPressed: controller.clear,
          icon: Icon(CupertinoIcons.xmark_circle_fill, size: 16, color: brand.muted)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
      ),
    )));
  }
}
