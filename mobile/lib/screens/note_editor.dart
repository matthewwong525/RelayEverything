import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoAlertDialog, CupertinoDialogAction, CupertinoIcons,
  CupertinoTextField, showCupertinoDialog;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../brand.dart';
import '../data/client_id.dart';
import '../editor/attachments.dart';
import '../editor/links.dart';
import '../editor/markdown.dart';
import '../editor/note_commands.dart';
import '../editor/paste.dart';
import '../editor/shortcuts.dart';
import '../editor/web_note/cover.dart';
import '../editor/web_note/pictures.dart';
import '../editor/web_note/web_note.dart';
import '../editor/web_note/web_note_pool.dart';
import '../relay.dart';
import 'back_to.dart';
import 'days.dart';
import 'folder.dart' show Opener, askAlert, browserProblem, openInBrowser, showProblemOn;
import 'hold_to_talk.dart' show recordFromShortcut;
import 'more_menu.dart';
import 'note_bars.dart';
import 'note_blocks.dart';
import 'round_button.dart';
import 'timeline.dart' show askDeleteForever;

export '../editor/links.dart' show linkAddressOf, linkRanges, linkUri;

/// Picks photos ([photos] true) or files from the phone. The app's is `file_picker`; a test passes its own.
typedef FilesPicker = Future<List<NewFile>> Function({required bool photos});

/// The phone's own picker: Photos for pictures and videos, Files for any file. The browser's gives each file's bytes.
Future<List<NewFile>> pickWithPhone({required bool photos}) async {
  final picked = await FilePicker.pickFiles(type: photos ? FileType.media : FileType.any);
  if (kIsWeb) {
    return [for (final file in picked) _withBytes(file.name, await file.readAsBytes())];
  }
  return [
    for (final file in picked)
      if (file.path != null) NewFile(path: file.path!, name: file.name, size: await file.length() ?? 0),
  ];
}

NewFile _withBytes(String name, List<int> bytes) => NewFile(name: name, size: bytes.length, bytes: bytes);

/// Gives a note's words to the phone's share sheet. The app's is `share_plus`; a test passes its own.
typedef Sharer = Future<void> Function(String text);

Future<void> shareWithPhone(String text) => SharePlus.instance.share(ShareParams(text: text));

/// How long typing pauses before the change is kept: under the two seconds the person may wait.
const savePause = Duration(milliseconds: 1500);

/// The room the floating tool bar or find bar takes over the keyboard, with a margin: the caret stays above it.
const barRoom = 64.0;

/// The page's keys that the editor page sends up, as the browser's page and the Mac's menu bar know them: `new-note`,
/// `find` and `delete-note`.
typedef PageKeys = void Function(String shortcut);

/// The CSS colour of [colour], as the editor page reads it.
String cssColour(Color colour) {
  int part(double value) => (value * 255).round().clamp(0, 255);
  return 'rgba(${part(colour.r)}, ${part(colour.g)}, ${part(colour.b)}, ${colour.a.toStringAsFixed(3)})';
}

/// The editor page's colours from the app's theme: the page draws the note in the same colours as the screens around
/// it, light or dark.
Map<String, String> editorThemeOf(BuildContext context) {
  final brand = brandOf(context);
  final theme = Theme.of(context);
  final brightness = theme.brightness;
  return {
    'paper': cssColour(brand.paper),
    'card': cssColour(brand.card),
    'line': cssColour(brand.line),
    'ink': cssColour(brand.ink),
    'muted': cssColour(brand.muted),
    'accent': cssColour(brand.accent),
    'accentText': cssColour(brand.accentText),
    'accentSoft': cssColour(brand.accentSoft),
    'spark': cssColour(brand.spark),
    'danger': cssColour(brand.danger),
    'select': cssColour(theme.textSelectionTheme.selectionColor ?? brand.accentSoft),
    for (final colour in highlightColours) 'hl-$colour': cssColour(highlightColourOf(colour, brightness)),
    'scheme': brightness == Brightness.dark ? 'dark' : 'light',
  };
}

/// Files dropped on the editor page: the browser keeps their bytes; the Mac and the phone keep each as a file of their
/// own first, which the note then moves into the app.
Future<List<NewFile>> pageDroppedFiles(Object? files) async {
  final kept = <NewFile>[];
  for (final file in files is List ? files : const []) {
    if (file is! Map) continue;
    final name = '${file['name'] ?? 'File'}';
    final List<int> bytes;
    try {
      bytes = base64Decode('${file['data'] ?? ''}');
    } on FormatException {
      continue;
    }
    if (kIsWeb) {
      kept.add(_withBytes(name, bytes));
      continue;
    }
    final folder = await Directory.systemTemp.createTemp('relay-drop-');
    final safe = name.replaceAll(RegExp(r'[/\\:]'), '_');
    final path = '${folder.path}/${safe.isEmpty ? 'File' : safe}';
    await File(path).writeAsBytes(bytes);
    kept.add(NewFile(path: path, name: name, size: bytes.length, move: true));
  }
  return kept;
}

/// One note's page, as Apple Notes has it: the note to read, and a tap in its words edits it in place. A new note
/// opens with the keyboard up and a Title first line. Each change is kept on a pause and on leave, with no *Save*. The
/// words are edited in the editor page ([WebNote]); this page keeps the note, its bars and its files.
class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.relay, this.entry, this.picker, this.sharer, this.opener, this.back = 'Notes',
    this.pane = false, this.onClose, this.onCompose, this.search, this.onKeys});

  final Relay relay;
  /// The note to open, or null for a new one.
  final Entry? entry;
  final FilesPicker? picker;
  final Sharer? sharer;
  /// Opens a link in the note in the phone's browser; a test passes its own.
  final Opener? opener;
  /// The page it opened from, *Home* or a folder, which its back button names.
  final String back;
  /// In the browser's wide layout: one bar of tools along the top, [search] at its right, and nothing at the bottom.
  final bool pane;
  /// Closes the note where the browser's layout holds it, in place of going back a page.
  final VoidCallback? onClose;
  /// Opens a new note where the browser's layout holds it, in place of a new page.
  final VoidCallback? onCompose;
  /// The search field at the right of the wide layout's top bar.
  final Widget? search;
  /// The page's keys pressed in the words, which the browser's page and the Mac do: new note, find and delete.
  final PageKeys? onKeys;

  @override
  State<NoteEditor> createState() => NoteEditorState();
}

class NoteEditorState extends State<NoteEditor> {
  late final String _id = widget.entry?.id ?? newClientId();
  /// The phone keeps the note: set only once an add kept it, so a save after an add that kept nothing adds again.
  late bool _stored = widget.entry != null;
  /// Saves made before the phone kept the note that still wait in [_writing]: a save meanwhile goes after them, so
  /// words cleared meanwhile still delete the note on leave.
  int _adds = 0;
  /// The editor page that shows the words.
  late final WebNote _page;
  /// The page got its document.
  bool _loaded = false;
  /// The Markdown of the words now, from the page's last change.
  String _markdown = '';
  /// The Markdown of the words as last kept: the words are unchanged while [_markdown] is the same.
  String _savedMarkdown = '';
  /// The words as last kept: a file added to an unchanged note keeps them as they were.
  late String _savedText = _current?.text ?? '';
  Timer? _pause;
  Future<void> _writing = Future.value();
  /// The app's navigator, taken while the page is open: a problem that comes after it closes still shows.
  NavigatorState? _navigator;
  /// Kept with no send yet, as typing saves: leaving sends it.
  bool _unsent = false;
  /// Set by ⋯ → *Delete*: no save runs after it, so leaving keeps nothing.
  bool _deleted = false;
  /// The note is in *Recently Deleted*: it opens to read only, and a tap in its words asks to recover it.
  bool _trash = false;
  bool _formatting = false;
  /// Set while editing, or at once when a button brings the keyboard up, so the edit that comes first waits for a pause.
  late bool _typing = widget.entry == null;
  double _keyboard = 300;
  /// The note held open before this page, such as the note page a voice note from Shortcuts opens over: leaving gives
  /// the hold back to it, so a pull does not change that note's words under its page.
  String? _heldBefore;
  /// *Find in Note* is open: its bar takes the tool bar's place, with its own field.
  bool _finding = false;
  final _find = TextEditingController();
  final _findFocus = FocusNode();

  /// Every file the page has placed in the words: one gone from them since was removed, and is not placed again.
  final _shown = <String>{};
  /// Files sent to the page that its words do not hold yet: a save meanwhile does not remove them.
  final _coming = <String>{};
  /// Where each file added on this page goes, by id: at the cursor, `cursor`, or at the `end`.
  final _placeAt = <String, String>{};
  /// Saves still running: a file gone from the note leaves the words only after them, as *Undo* may bring it back.
  int _saving = 0;

  /// What the page was last sent, so only a change goes again.
  Map<String, String>? _theme;
  double? _bottom;
  /// The highlight pen's colour the page has: its format key highlights in it.
  String? _pen;
  String? _head;
  String? _placeholder;
  String? _appKeys;
  final _sentViews = <String, String>{};
  /// The file or recording each key of the page's files names: an attachment's id, or `head:N` above or under the words.
  final _items = <String, Object>{};
  /// Each picture's `data:` address, once read; null when the phone could not read it.
  final _pictures = <String, String?>{};
  /// Each recording's sound waves, once read.
  final _waves = <String, List<double>>{};

  Relay get relay => widget.relay;
  /// The note's own id, made here for a new note.
  String get id => _id;

  /// The note's editor page, for a test.
  @visibleForTesting
  WebNote get page => _page;

  /// The kept note has no file and no recording, so blank words leave nothing in it.
  bool get _bare {
    final note = _current;
    return note != null && note.files.isEmpty && note.recordings.isEmpty;
  }

  /// The note as the list has it now, so a recording's words still being written fill in here too.
  Entry? get _current => _stored ? _live ?? widget.entry : null;

  /// The note in the list or in *Recently Deleted* now, or null when the phone no longer has it.
  Entry? get _live {
    final opened = widget.entry;
    return [...relay.entries, ...relay.deleted].where((other) => other.id == _id &&
      (_id.isNotEmpty || (other.at == opened?.at && other.recordings.isEmpty == opened?.recordings.isEmpty))).firstOrNull;
  }

  bool get _inTrash => _stored && relay.deleted.any((entry) => entry.id == _id);

  /// The note reads only, as a note in *Recently Deleted* does.
  bool get readOnly => _trash;

  NoteState get _state => _page.state;

  /// The person edits the note: its words took a tap, or the Format sheet is open.
  bool get _editing => _state.editing || _formatting;

  @override
  void initState() {
    super.initState();
    _page = WebNotePool.shared.take()
      ..onMessage = _fromPage
      ..addListener(_pageChanged);
    _trash = _inTrash;
    relay.addListener(_relayChanged);
    relay.playback.addListener(_playbackChanged);
    // The browser's layout holds one note at a time: the note before has closed, so nothing gets the hold back.
    _heldBefore = widget.onClose == null ? relay.openNote : null;
    relay.openNote = _id;
    relay.editorWords = _words;
    if (_stored && _live == null) _gone();
  }

  /// A note's words with each file at its place, as the editor page's document. A file the text does not name, as in
  /// an older note, goes where the page showed it before: the recording a voice note started with first, and the rest
  /// after the words. A new note starts with an empty Title line.
  Json _docOf(Entry? entry) {
    if (entry == null) return blocksToDoc([NoteLine(LineKind.header1, const [])]);
    final files = filesOf(entry);
    final ids = {for (final file in files) file.file.id};
    final words = markdownToBlocks(entry.text, title: true, files: ids);
    final placed = attachmentIdsIn(words);
    _shown.addAll(ids);
    return blocksToDoc(withFilesPlaced(words,
      top: [for (final file in files) if (file.top && !placed.contains(file.file.id)) file.file],
      rest: [for (final file in files) if (!file.top && !placed.contains(file.file.id)) file.file]));
  }

  /// Each of [note]'s files that can have a place in its words, in the order added; [top] marks the recording a
  /// voice note started with. A file with no id that can make a line, such as a ring note's recording in the browser,
  /// has no place: the page shows it above or under the words.
  static List<({NoteAttachment file, bool top})> filesOf(Entry note) {
    final below = note.recordings.where((recording) => !recording.top && NoteAttachment.placeable(recording.id));
    ({NoteAttachment file, bool top}) of(EntryRecording recording) =>
      (file: NoteAttachment(recording.id, recording.name), top: recording.top);
    return [
      for (final recording in note.recordings) if (recording.top && NoteAttachment.placeable(recording.id)) of(recording),
      for (final (index, file) in note.files.indexed) ...[
        for (final recording in below.where((recording) => recording.filesBefore == index)) of(recording),
        if (NoteAttachment.placeable(file.id)) (file: NoteAttachment(file.id, file.name), top: false),
      ],
      for (final recording in below.where((recording) => recording.filesBefore >= note.files.length)) of(recording),
    ];
  }

  /// [text] as kept: blank words keep only the lines that place the files, so a note of files alone is not `#`.
  static String _kept(String text) => plainText(text).trim().isNotEmpty ? text
    : text.split('\n').where((line) => NoteAttachment.read(line) != null).join('\n');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigator = Navigator.maybeOf(context, rootNavigator: true);
    _measureKeyboard(MediaQuery.viewInsetsOf(context).bottom);
    if (!_loaded) _load();
  }

  /// Opens the note in the editor page: a new note with the keyboard up.
  void _load() {
    final doc = _docOf(_current);
    _markdown = _savedMarkdown = docToMarkdown(doc);
    _loaded = true;
    final views = _views();
    _sentViews
      ..clear()
      ..addAll({for (final MapEntry(:key, :value) in views.entries) key: jsonEncode(value)});
    final head = _headOf(context);
    _head = jsonEncode(head);
    _page.load(
      doc: doc,
      theme: _theme = editorThemeOf(context),
      editable: !_trash,
      fromElsewhere: _current?.from != null,
      focus: widget.entry == null && !_trash,
      bottom: _bottom = _bottomRoom(context),
      // The browser does the format keys in the page; the Mac's menu bar does them, and a phone has none.
      keys: relay.web,
      appKeys: _appKeysNow(),
      mac: commandKeys,
      placeholder: _placeholder = _placeholderOf(_current),
      highlight: _pen = relay.settings.highlightColour,
      head: head,
      files: views,
    );
  }

  /// The app's keys the page passes up, by the keys it would take for itself. The browser's page does new note, delete
  /// and, in its wide layout, find; in its narrow one the browser's own find runs. The Mac's menu bar takes every key
  /// but delete; a phone has none.
  List<String> _appKeysNow() {
    final keys = relay.web ? ['new-note', if (widget.pane) 'find', 'delete-note'] : relay.desktop ? ['delete-note']
      : <String>[];
    _appKeys = jsonEncode(keys);
    return keys;
  }

  /// The Format panel takes the keyboard's height. Only a keyboard up for the words counts: while it slides down for
  /// the panel, each frame's height is part of the way.
  void _measureKeyboard(double inset) {
    if (_state.focus && !_formatting && inset > 100) _keyboard = inset;
  }

  /// The room under the words that the bars and the keyboard cover: the page keeps the cursor above it.
  double _bottomRoom(BuildContext context) {
    if (widget.pane) return 40;
    if (_formatting) return 24;
    final media = MediaQuery.of(context);
    return media.viewInsets.bottom + media.padding.bottom + barRoom + 16;
  }

  /// What the empty words show: *Add notes…* under the recording a voice note started with.
  static String _placeholderOf(Entry? note) =>
    note != null && note.recordings.any((recording) => recording.top) ? 'Add notes…' : 'What do you want to keep?';

  /// The date line, and the cards of files with no place in the words: above them, the recording a ring note started
  /// with in the browser; under them, the rest.
  Json _headOf(BuildContext context) {
    final note = _current;
    final above = <String>[], below = <String>[];
    for (final key in _items.keys.where((key) => key.startsWith('head:'))) {
      final item = _items[key];
      (item is EntryRecording && item.top ? above : below).add(key);
    }
    return {'date': _when(context, note?.at ?? DateTime.now(), note?.from), 'above': above, 'below': below};
  }

  /// What the page draws for each file: its picture, its row, or its recording's card, by the key the page knows it by.
  Json _views() {
    _items.clear();
    final note = _current;
    final views = <String, Object?>{};
    if (note == null) return views;
    var head = 0;
    for (final recording in note.recordings) {
      final key = NoteAttachment.placeable(recording.id) ? recording.id : 'head:${head++}';
      _items[key] = recording;
      views[key] = _recordingView(recording);
    }
    for (final file in note.files) {
      final key = NoteAttachment.placeable(file.id) ? file.id : 'head:${head++}';
      _items[key] = file;
      views[key] = _fileView(file);
    }
    return views;
  }

  Json _fileView(EntryFile file) {
    if (file.picture && file.ready) {
      return {'kind': 'picture', 'name': file.name, 'src': _pictureOf(file), 'ready': true};
    }
    return {'kind': 'file', 'name': file.name, 'size': file.size > 0 ? sizeLabel(file.size) : '', 'ready': file.ready};
  }

  /// A picture's address for the page: the person's space's file route in the browser; on the phone and the Mac, the
  /// picture itself, read once.
  String? _pictureOf(EntryFile file) {
    if (!file.onPhone) return file.url;
    if (_pictures.containsKey(file.id)) return _pictures[file.id];
    _pictures[file.id] = null;
    unawaited(pictureSource(file.path, file.type).then((source) {
      _pictures[file.id] = source;
      if (mounted) _sync();
    }));
    return null;
  }

  /// This recording's playback, or null while another plays or none does.
  Playback? _playing(EntryRecording recording) => switch (relay.playback.value) {
    final now? when now.recording == recording.recording => now,
    _ => null,
  };

  Json _recordingView(EntryRecording recording) {
    final now = _playing(recording);
    final levels = _waves[recording.recording];
    if (levels == null && recording.ready) {
      _waves[recording.recording] = const [];
      unawaited(relay.waveOf(recording.recording).then((wave) {
        _waves[recording.recording] = wave;
        if (mounted) _sync();
      }));
    }
    final status = recording.writing ? 'writing'
      : recording.failed ? 'failed'
      : recording.transcript == null ? 'empty'
      : recording.noWords ? 'none'
      : 'words';
    return {
      'kind': 'recording', 'name': recording.name, 'ready': recording.ready,
      'length': (recording.length ?? now?.length)?.inMilliseconds, 'levels': levels ?? const <double>[],
      'playing': now?.playing ?? false, 'position': now?.at.inMilliseconds, 'status': status, 'why': recording.why,
    };
  }

  /// Sends the page what changed since it was last sent: the colours, the room under the words, the pen's colour, the
  /// date line, the placeholder and each file's look.
  void _sync() {
    if (!_loaded || !mounted) return;
    final theme = editorThemeOf(context);
    if (!_sameTheme(theme, _theme)) _page.send({'do': 'theme', 'theme': _theme = theme});
    final bottom = _bottomRoom(context);
    if (bottom != _bottom) _page.send({'do': 'bottom', 'bottom': _bottom = bottom});
    final pen = relay.settings.highlightColour;
    if (pen != _pen) _page.send({'do': 'highlight', 'colour': _pen = pen});
    final views = _views();
    final changed = <String, Object?>{
      for (final MapEntry(:key, :value) in views.entries)
        if (_sentViews[key] != jsonEncode(value)) key: value,
    };
    for (final MapEntry(:key, :value) in changed.entries) {
      _sentViews[key] = jsonEncode(value);
    }
    if (changed.isNotEmpty) _page.send({'do': 'files', 'files': changed});
    final head = _headOf(context);
    final headText = jsonEncode(head);
    if (headText != _head) {
      _head = headText;
      _page.send({'do': 'head', 'head': head});
    }
    final placeholder = _placeholderOf(_current);
    if (placeholder != _placeholder) _page.run('placeholder', _placeholder = placeholder);
    final keysBefore = _appKeys;
    final keys = _appKeysNow();
    if (_appKeys != keysBefore) _page.send({'do': 'appKeys', 'appKeys': keys});
  }

  static bool _sameTheme(Map<String, String> a, Map<String, String>? b) =>
    b != null && a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

  /// The words as they are now: the same as kept, or new ones not yet kept.
  ({String id, String text})? _words() {
    if (_deleted) return null;
    final text = _markdown == _savedMarkdown ? _savedText : _markdown;
    return (id: _id, text: _kept(text));
  }

  @override
  void dispose() {
    _save(sendNow: true, leaving: true);
    unawaited(_writing.then((_) => relay.closedNote(_id)));
    if (relay.openNote == _id) relay.openNote = _heldBefore;
    if (relay.editorWords == _words) relay.editorWords = null;
    relay.removeListener(_relayChanged);
    relay.playback.removeListener(_playbackChanged);
    _pause?.cancel();
    _page
      ..removeListener(_pageChanged)
      ..onMessage = null;
    WebNotePool.shared.giveBack(_page);
    _find.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  /// The page's cursor or mode changed: the bars light, and the Format sheet closes when the words take the keyboard
  /// back. A tap in the words while finding edits them, as in Apple Notes: find mode ends.
  void _pageChanged() {
    if (!mounted) return;
    if (_finding && _state.focus) _endFind(clearPage: true);
    _typing = _editing;
    setState(() {});
  }

  /// A message from the editor page.
  void _fromPage(Json message) {
    if (!mounted) return;
    switch (message['is']) {
      case 'changed':
        final doc = message['doc'];
        if (doc is! Map) return;
        final markdown = docToMarkdown(doc.cast());
        final kept = _markdown == _savedMarkdown;
        _markdown = markdown;
        _coming.removeAll(attachmentIdsInDoc(doc.cast()));
        if (message['quiet'] == true) {
          // A change that is no edit, such as a file from elsewhere placed in the words: a kept note stays kept.
          if (kept) _savedMarkdown = markdown;
        } else {
          _changed();
        }
      case 'paste':
        _paste(message);
      case 'tap':
        _tapped('${message['id'] ?? ''}', '${message['action'] ?? ''}', message['value']);
      case 'open':
        if (message['address'] case final String address) unawaited(_openLink(address));
      case 'keys':
        _key('${message['shortcut'] ?? ''}');
      case 'drop':
        unawaited(pageDroppedFiles(message['files']).then(addFiles));
    }
  }

  /// A recording made into a new note keeps it, so the next save edits it. A kept note gone from the list closes the
  /// page. A file new to the note takes its place in the words.
  void _relayChanged() {
    _giveKeyboardBack();
    if (!_stored && !_deleted && _adds == 0 && relay.entries.any((entry) => entry.id == _id)) _stored = true;
    if (_stored && !_deleted && _live == null) return _gone();
    // Deleted or recovered, here or on another device: the words lock or open.
    if (_inTrash != _trash) {
      setState(() => _trash = _inTrash);
      _page.run('editable', !_trash);
      if (_trash) _page.run('blur');
    }
    _placeFiles();
    _sync();
  }

  /// The recording that plays moved: its card shows where.
  void _playbackChanged() => _sync();

  /// Puts each file new to the note in the words: one added on this page where it was asked for, as a change that
  /// saves, and one from elsewhere, such as a recording the phone kept, at the end, as no change. A file the note no
  /// longer has leaves the words, once every save is done.
  void _placeFiles() {
    final note = _current;
    final doc = _page.doc;
    if (note == null || doc == null || _trash || _deleted || !_loaded) return;
    final files = filesOf(note);
    final held = {for (final file in files) file.file.id};
    final placed = attachmentIdsInDoc(doc);
    if (_saving == 0 && _markdown == _savedMarkdown) {
      // Not an Undo step: Undo of its removal on this page brings it back, and the save sends it again.
      final gone = placed.where((id) => !held.contains(id)).toList();
      if (gone.isNotEmpty) _page.run('detach', {'ids': gone, 'quiet': true});
    }
    final missing = [
      for (final file in files) if (!placed.contains(file.file.id) && !_shown.contains(file.file.id)) file.file,
    ];
    if (missing.isEmpty) return;
    _shown.addAll(missing.map((file) => file.id));
    _coming.addAll(missing.map((file) => file.id));
    Json of(NoteAttachment file) => {'id': file.id, 'name': file.name};
    final asked = <String, List<NoteAttachment>>{};
    for (final file in missing.where((file) => _placeAt.containsKey(file.id))) {
      (asked[_placeAt.remove(file.id)!] ??= []).add(file);
    }
    // A place asked at the cursor moves the cursor under the files, also while a picker or the recording screen has
    // the keyboard: the words typed next go under them.
    for (final MapEntry(key: at, value: files) in asked.entries) {
      _page.run('attach', {'files': [for (final file in files) of(file)], 'at': at, 'quiet': false});
    }
    final rest = [for (final file in missing) if (!asked.values.any((files) => files.contains(file))) of(file)];
    if (rest.isNotEmpty) _page.run('attach', {'files': rest, 'at': 'end', 'quiet': true});
  }

  /// The note left the phone, such as a voice note with no speech or one deleted on another phone: leaving keeps
  /// nothing, and the page closes once, after the frame, so the page under it shows. A page opened over it, such as
  /// the attach sheet, is not the one that goes.
  void _gone() {
    _pause?.cancel();
    _deleted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.onClose case final close?) return close();
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      if (route.isCurrent) {
        Navigator.of(context).maybePop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Typing saves on a pause. A change while reading, such as a ticked circle, is kept at once.
  void _changed() {
    _pause?.cancel();
    if (!_typing) return _save(sendNow: true);
    _pause = Timer(savePause, () => _save(sendNow: false));
  }

  /// Keeps the note when it changed: an empty new note is never kept, and an unchanged one never written back, so an
  /// old note's own marks stay as they were. A note with no words and no files is deleted on [leaving], as Apple Notes
  /// does; until then its blank words are never written, so never sent. Saves run one at a time, in order, and a send
  /// on leave goes after them.
  void _save({required bool sendNow, List<NewFile> files = const [], bool leaving = false}) {
    _pause?.cancel();
    if (_deleted || _trash || !_loaded) return;
    final markdown = _markdown;
    final same = markdown == _savedMarkdown;
    final text = same ? _savedText : markdown;
    // Blank words, such as only an empty Title line, are kept as none, so a note of files alone is not `#`.
    final empty = plainText(text).trim().isEmpty;
    final note = _current;
    final inWords = attachmentIdsInDoc(_page.doc ?? const {});
    // A file gone from the words was removed: only the phone that made the note may remove one.
    final removed = note == null || note.from != null ? const <String>{} : {
      for (final file in filesOf(note))
        if (_shown.contains(file.file.id) && !inWords.contains(file.file.id) && !_coming.contains(file.file.id))
          file.file.id,
    };
    final changed = !same || files.isNotEmpty;
    final dropping = leaving && empty && files.isEmpty && (_stored || _adds > 0);
    // Left with blank words and its last file just removed, the note is as bare as one that had none.
    final clearing = dropping && note != null && removed.isNotEmpty &&
      removed.length == note.files.length + note.recordings.length;
    if (!changed && !dropping) {
      if (sendNow && _unsent) {
        _unsent = false;
        _writing = _writing.then((_) => relay.sync());
      }
      return;
    }
    if (!_stored && _adds == 0 && empty && files.isEmpty) return;
    _savedMarkdown = markdown;
    _savedText = text;
    final unsent = _unsent;
    _unsent = !sendNow;
    final adding = !_stored;
    if (adding) _adds++;
    _saving++;
    _writing = _writing.then((_) async {
      String? problem;
      if (_stored && empty && files.isEmpty && (_bare || clearing)) {
        // The removal is kept first, so a note that still stays, such as a voice note, has it.
        final removing = !_bare;
        if (removing) problem = await relay.editNote(_id, _kept(text), removed: removed, sendNow: false);
        final emptied = leaving ? await relay.dropEmptyNote(_id) : Emptied.kept;
        if (emptied != Emptied.kept) {
          _stored = false;
        } else if (removing && sendNow) {
          await relay.sync();
        }
      } else if (_stored && !changed) {
        // Left unchanged with blank words, yet a file or a recording keeps it: only what waits still goes.
        if (unsent) await relay.sync();
      } else if (_stored) {
        problem = await relay.editNote(_id, _kept(text), files: files, removed: removed, sendNow: sendNow);
      } else if (!empty || files.isNotEmpty) {
        problem = await relay.addNote(_kept(text), files: files, id: _id, sendNow: sendNow);
        // An add of only files the phone could not keep keeps nothing, so the next save adds the note again.
        _stored = relay.entries.any((entry) => entry.id == _id);
        if (mounted) setState(() {});
      }
      if (adding) _adds--;
      _saving--;
      if (mounted) _placeFiles();
      if (problem != null) await showProblemOn(_navigator, problem);
    });
  }

  /// A paste in the words from outside the note: the page asks, and gets back only the styles the note can store
  /// ([pastedBlocks]), which it puts in as one change, so one *Undo* takes it back.
  void _paste(Json message) {
    // A file's line is a file only for a file this note keeps: one copied from another note stays words.
    final note = _current;
    final blocks = _trash ? const <NoteBlock>[] : pastedBlocks(html: message['html'] as String?,
      plain: message['text'] as String? ?? '', files: {if (note != null) for (final file in filesOf(note)) file.file.id});
    // Nothing the note can keep, such as only spaces: the words and the selection stay as they are.
    if (blocks.isEmpty) return;
    _page.send({'do': 'paste', 'id': message['id'], 'blocks': blocksToDoc(blocks)['content'] ?? const []});
  }

  /// A tap on a file's part in the page: a picture or a file opens, a recording plays, pauses, goes to a place or opens
  /// its transcript, and *Try again* writes its words again. In *Recently Deleted* a tap in the words asks to recover
  /// the note.
  void _tapped(String key, String action, Object? value) {
    if (action == 'words') {
      if (_trash) unawaited(_askRecover());
      return;
    }
    final item = _items[key];
    switch ((item, action)) {
      case (final EntryFile file, 'open'):
        unawaited(relay.openFile(file));
      case (final EntryRecording recording, 'play'):
        unawaited(relay.play(recording.recording));
      case (EntryRecording(), 'pause'):
        unawaited(relay.pause());
      case (final EntryRecording recording, 'seek'):
        if (value is num) unawaited(_seek(recording, value.toDouble().clamp(0.0, 1.0)));
      case (final EntryRecording recording, 'transcript'):
        _openTranscript(recording);
      case (EntryRecording(), 'retry'):
        unawaited(relay.writeWordsAgain());
    }
  }

  /// Goes to [part] of [recording]'s length, and starts it first when it is stopped: the browser's player knows the
  /// length only then.
  Future<void> _seek(EntryRecording recording, double part) async {
    if (_playing(recording) == null) await relay.play(recording.recording);
    final length = recording.length ?? _playing(recording)?.length ?? Duration.zero;
    if (length > Duration.zero) await relay.seek(length * part);
  }

  /// The recording's own page, with all its words, which goes back to the note by its first typed line.
  void _openTranscript(EntryRecording recording) {
    final note = _current;
    final first = plainText(_markdown).split('\n').map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    // Cut by characters, not code units: half an emoji is not a string Flutter can draw.
    final letters = first.characters;
    final title = first.isEmpty ? 'Note' : letters.length > 18 ? '${letters.take(17).toString().trimRight()}…' : first;
    // A note in *Recently Deleted* reads only: its transcripts too.
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordingPage(relay: relay,
      recording: recording, editable: !relay.desktop && note?.from == null && !_trash, back: title,
      when: _when(context, note?.at ?? DateTime.now(), note?.from)))));
  }

  /// A key pressed in the words that the page passes up: *Link* and *Table* here; new note, find and delete go to the
  /// browser's page or the Mac's, else this page does them.
  void _key(String shortcut) {
    switch (shortcut) {
      case 'link':
        unawaited(_linkBox());
      case 'table':
        format(FormatAction.table);
      case 'new-note' || 'find' || 'delete-note' when widget.onKeys != null:
        widget.onKeys!(shortcut);
      case 'new-note':
        _compose();
      case 'find':
        if (!relay.web) _openFind();
      case 'delete-note':
        delete();
    }
  }

  void _say(String message) => unawaited(showProblemOn(_navigator, message));

  /// ✓: the keyboard goes down, the words stop editing, and the note is kept at once.
  void _done() {
    _page.run('blur');
    setState(() => _formatting = _typing = false);
    _save(sendNow: true);
  }

  /// *Aa*: the keyboard goes down and the panel takes its place. The words keep the cursor and the words picked while
  /// the panel styles them.
  void _styles() {
    setState(() => _formatting = true);
    _page.run('keyboard', false);
  }

  void _closeStyles() {
    setState(() => _formatting = false);
    _page
      ..run('keyboard', true)
      ..run('focus');
  }

  /// *Undo* and *Redo* change the words as typing does, so the save on a pause keeps them; the keyboard stays up.
  Widget _history() {
    final state = _state;
    if (!state.canUndo && !state.canRedo) return const SizedBox.shrink();
    void undo() => _page.run('undo');
    void redo() => _page.run('redo');
    return Padding(padding: const EdgeInsets.only(right: 8), child: state.canRedo
      ? ButtonPill(children: [
          PillIconButton(icon: CupertinoIcons.arrow_uturn_left, tooltip: 'Undo', onPressed: state.canUndo ? undo : null),
          PillIconButton(icon: CupertinoIcons.arrow_uturn_right, tooltip: 'Redo', onPressed: redo),
        ])
      : RoundIconButton(icon: CupertinoIcons.arrow_uturn_left, tooltip: 'Undo', onPressed: state.canUndo ? undo : null));
  }

  /// ⋯ → *Find in Note*: the find bar takes the keyboard from the words, so typing there changes nothing in the note.
  void _openFind() {
    setState(() => _finding = true);
    _findFocus.requestFocus();
  }

  /// The page marks each match, in the words and in tables' cells, and selects the first.
  void _findChanged() => _page.run('find', _find.text);

  /// Down (1) or up (-1) to the next match, round from the last to the first.
  void _step(int step) => _page.run('find-step', step);

  /// ✓ on the find bar: the match stays as the caret, with the keyboard down.
  void _closeFind() {
    _page.run('find-close');
    _endFind();
  }

  void _endFind({bool clearPage = false}) {
    if (clearPage) _page.run('find', '');
    _find.clear();
    _findFocus.unfocus();
    setState(() => _finding = false);
  }

  /// *2 of 14* or *No matches*; null while the field is empty.
  String? get _found {
    if (_find.text.isEmpty) return null;
    final found = _state.found;
    if (found == null || found.count == 0) return 'No matches';
    return '${found.index + 1} of ${found.count}';
  }

  /// ⋯ → *Pin Note* or *Unpin Note*; a new note not kept yet has nothing to pin.
  void _pin() {
    final note = _current;
    if (note != null) unawaited(relay.pinNote(_id, !note.pinned));
  }

  /// *Checklist*: the cursor's line becomes a checklist item, or stops being one. While reading it adds an item at the
  /// end and brings the keyboard up.
  void _checklist() {
    if (!_state.editing) {
      _typing = true;
      _page.run('focus', 'new-line');
    }
    _page.run('checklist');
  }

  /// *Attach* → *Photos* or *Files*. The browser has one picker for every kind of file.
  Future<void> _attach({required bool photos}) async {
    // The cursor's place before the picker: the phone's picker takes the keyboard while it is open. The files go
    // there once the note keeps them.
    final editing = _state.editing;
    final List<NewFile> picked;
    try {
      picked = await (widget.picker ?? pickWithPhone)(photos: photos);
    } on Exception {
      return _say('The ${relay.web ? 'browser' : relay.desktop ? 'Mac' : 'phone'} did not give the file. Try again.');
    }
    if (!mounted || picked.isEmpty) return;
    _save(sendNow: !editing && !_state.editing, files: _placed(picked, editing ? 'cursor' : 'end'));
  }

  /// [files], each with the id the note will keep it by, and asked to go [at] the cursor or the end.
  List<NewFile> _placed(List<NewFile> files, String at) {
    final placed = [for (final file in files) file.withId(newClientId())];
    for (final file in placed) {
      _placeAt[file.id!] = at;
    }
    return placed;
  }

  String get _plain => plainText(_markdown);

  Future<void> _share() => (widget.sharer ?? shareWithPhone)(_plain);

  /// Copies the words, with no message: the person knows what they copied.
  Future<void> _copy() => Clipboard.setData(ClipboardData(text: _plain));

  /// ⋯ → *Delete*: the page closes, and the note moves to *Recently Deleted* after any save still running, with no
  /// message. A new note not kept yet keeps nothing.
  void _delete() {
    _pause?.cancel();
    _deleted = true;
    _writing = _writing.then((_) async {
      if (!_stored) return;
      await relay.deleteNote(_id);
    });
    _leave();
  }

  /// ⋯ → *Recover* on a note in *Recently Deleted*: it goes back to the notes, and its words open to edit.
  Future<void> _recover() => relay.recover(_id);

  /// ⋯ → *Delete* on a note in *Recently Deleted*: it asks first, then the note goes for good and the page closes.
  Future<void> _deleteForever() async {
    if (!await askDeleteForever(context) || !mounted) return;
    _deleted = true;
    unawaited(relay.deleteForever(_id));
    _leave();
  }

  /// A tap in the words of a note in *Recently Deleted*, as Apple Notes asks.
  Future<void> _askRecover() async {
    if (await askAlert(context, title: "Recently deleted notes can't be edited.",
      message: "To edit this note, you'll need to recover it.", action: 'Recover')) {
      await _recover();
    }
  }

  /// ⋯ → *Delete*, or the browser's delete key: the note moves to *Recently Deleted*, or, from there, goes for good.
  void delete() => _trash ? unawaited(_deleteForever()) : _delete();

  void _leave() {
    if (widget.onClose case final close?) return close();
    Navigator.of(context).maybePop();
  }

  /// Files dropped on the note: they join it as the paperclip's do, at the end. A note from elsewhere takes none.
  void addFiles(List<NewFile> files) {
    if (!mounted || files.isEmpty || _trash) return;
    if (_attachOrNull == null) return _say('You can add files only to a note you wrote here or on your phone.');
    _save(sendNow: true, files: _placed(files, 'end'));
  }

  /// A format item from the computer's *Text styles* menu or the Mac's *Format* menu: on the words picked or the
  /// cursor's line, as Notes does. A table's cell holds plain words, so only *Table* acts there.
  void format(FormatAction action) {
    if (_trash) return;
    if (action == FormatAction.table) return _addTable();
    if (_state.inTable) return;
    if (action == FormatAction.link) return unawaited(_linkBox());
    NoteCommands(_page).run(action, colour: relay.settings.highlightColour);
  }

  /// *Table*: a table of 2 columns and 2 rows at the cursor, with the cursor in its first cell.
  void _addTable() {
    if (_trash) return;
    _typing = true;
    if (!_state.editing) _page.run('focus', 'end');
    _page.run('table');
  }

  /// *Link*: a box for the address of the words picked, filled from a copied web address. On a link it changes the
  /// address or takes the link away. With no words picked, the address goes in as its own words.
  Future<void> _linkBox() async {
    if (_trash || _state.inTable) return;
    final now = _state.link;
    var copied = '';
    if (now == null) {
      final clipboard = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
      if (RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(clipboard)) copied = clipboard;
    }
    if (!mounted) return;
    final field = TextEditingController(text: now ?? copied);
    final answer = await showCupertinoDialog<String>(context: context, barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: Text(now == null ? 'Add Link' : 'Change Link'),
        content: Padding(padding: const EdgeInsets.only(top: 12), child: CupertinoTextField(controller: field,
          placeholder: 'Address', autofocus: true, autocorrect: false, keyboardType: TextInputType.url,
          onSubmitted: (words) => Navigator.pop(context, words))),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (now != null) CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, ''),
            child: const Text('Remove Link')),
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Done')),
        ],
      ));
    field.dispose();
    if (answer == null || !mounted) return;
    if (answer.trim().isEmpty) {
      // Null takes the link off.
      if (now != null) _page.send({'do': 'run', 'action': 'link', 'value': null});
      return _page.run('focus');
    }
    final address = linkAddressOf(answer);
    if (address == null) return _say('That is not a web address. Try again.');
    _page
      ..run('link', address)
      ..run('focus');
  }

  /// The new page takes this one's place, so this page gives the hold back first: the new page then gives it, on
  /// leave, to the note under both, not to this closed one.
  void _compose() {
    if (relay.openNote == _id) relay.openNote = _heldBefore;
    if (widget.onCompose case final compose?) return compose();
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => NoteEditor(relay: relay, picker: widget.picker, sharer: widget.sharer, opener: widget.opener,
        back: widget.back)));
  }

  Future<void> _openLink(String link) async {
    // A mail link or another with its own scheme opens as it is; `www.…` opens on the web.
    final address = linkUri(link);
    if (address == null || !await (widget.opener ?? openInBrowser)(address)) _say(browserProblem);
  }

  /// *Yesterday at 18:05*, and *From Email* for a note from elsewhere.
  String _when(BuildContext context, DateTime at, String? from) {
    final days = daysAgo(at, DateTime.now());
    final day = days <= 0 ? 'Today' : days == 1 ? 'Yesterday' : MaterialLocalizations.of(context).formatMediumDate(at);
    return ['$day at ${TimeOfDay.fromDateTime(at).format(context)}', if (from != null) 'From $from']
      .whereType<String>().join(' · ');
  }

  /// The server takes new files only from the phone that made the note, so a note from elsewhere offers none, and
  /// nor does a note in *Recently Deleted*.
  AttachPick? get _attachOrNull => _current?.from == null && !_trash ? _attach : null;

  /// *Record* shows only on a phone, and for a note made here and not in *Recently Deleted*, as *Attach* does.
  VoidCallback? get _recordOrNull => !relay.desktop && _current?.from == null && !_trash ? _record : null;

  /// *Record*: the recording screen opens over the note, and the recording joins it at the cursor, or at the end. The
  /// words typed so far are kept first, so a new note with words is kept before the recording joins it.
  Future<void> _record() async {
    final id = newClientId();
    final editing = _state.editing;
    _placeAt[id] = editing ? 'cursor' : 'end';
    // The keyboard goes down for the recording screen; the words keep the cursor, where the recording goes.
    if (editing) _page.run('keyboard', false);
    _save(sendNow: false);
    await _writing;
    _keyboardAfterRecording = editing;
    if (mounted) await recordFromShortcut(context, relay, into: _id, id: id);
    _giveKeyboardBack();
  }

  /// The keyboard went down for the recording screen: it comes back once the phone stops listening.
  bool _keyboardAfterRecording = false;

  void _giveKeyboardBack() {
    if (!_keyboardAfterRecording || relay.listening != null || !mounted) return;
    _keyboardAfterRecording = false;
    _page.run('keyboard', true);
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final editing = _editing;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    _measureKeyboard(inset);
    _sync();
    // Hidden until the page has drawn the note: a page still starting shows nothing, never a blank or white frame. The
    // browser's frame hides itself: a view the app does not draw never joins the browser's page.
    final view = kIsWeb ? _page.view() : Opacity(opacity: _page.ready ? 1 : 0, child: _page.view());
    return Scaffold(
      // The editor page keeps the cursor above the keyboard itself: the page does not shrink for it.
      resizeToAvoidBottomInset: false,
      appBar: widget.pane ? _paneBar(brand) : AppBar(leading: BackTo(widget.back, onPressed: widget.onClose),
        leadingWidth: BackTo.widthOf(widget.back), actions: [
        if (editing && !_finding) ExcludeFocus(child: _history()),
        ExcludeFocus(child: ButtonPill(children: [
          PillIconButton(icon: CupertinoIcons.square_arrow_up, tooltip: 'Share', onPressed: _share),
          _more(),
        ])),
        if (editing && !_finding) Padding(padding: const EdgeInsets.only(left: 8),
          child: ExcludeFocus(child: RoundIconButton(icon: CupertinoIcons.checkmark_alt, tooltip: 'Done', onPressed: _done,
            accent: true))),
        const SizedBox(width: 12),
      ]),
      body: Column(children: [
        Expanded(child: Stack(children: [
          // The same widgets in the wide layout and the narrow one, with only the width changing: a web view moved to
          // another place in the tree starts again, and the browser's frame loads its page again.
          Positioned.fill(child: Align(alignment: Alignment.topCenter,
            child: SizedBox(width: widget.pane ? 760 : double.infinity, height: double.infinity, child: view))),
          // The iPhone's swipe back from the left edge: the web view would take the touch first.
          if (!widget.pane && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
            const Positioned(left: 0, top: 0, bottom: 0, width: 20,
              child: Listener(behavior: HitTestBehavior.opaque, child: SizedBox.expand())),
          if (!widget.pane && !_formatting && !_trash) Positioned(left: 16, right: 16, bottom: inset, child: overNote(SafeArea(
            top: false,
            minimum: EdgeInsets.only(bottom: editing || _finding ? 6 : 12),
            child: _finding
              ? FindBar(controller: _find, focus: _findFocus, onChanged: _findChanged, onDone: _closeFind,
                  found: _found, onStep: (_state.found?.count ?? 0) == 0 ? null : _step)
              // The bars take no focus: a tap on one keeps the keyboard with the words.
              : ExcludeFocus(child: editing
                ? _keyboardBar()
                : ReadingBar(onChecklist: _checklist, onAttach: _attachOrNull, onCompose: _compose,
                    attachMenu: !relay.desktop, onRecord: _recordOrNull)),
          ))),
        ])),
        if (!widget.pane && _formatting) ExcludeFocus(child: FormatSheet(page: _page, height: _keyboard,
          onClose: _closeStyles, colour: relay.settings.highlightColour, onColour: relay.setHighlightColour)),
      ]),
    );
  }

  /// Over the keyboard: the style tools while words are picked, else the scrolling tool bar. In a table's cell only
  /// *Table*, *Attach* and *Hide keyboard* act: a cell holds plain words.
  Widget _keyboardBar() {
    final state = _state;
    if (state.editing && !state.empty && !state.inTable) {
      return SelectionToolBar(page: _page, colour: relay.settings.highlightColour, onLink: () => unawaited(_linkBox()));
    }
    final words = !state.inTable;
    final commands = NoteCommands(_page);
    return FloatingToolBar(
      onStyles: words ? _styles : null,
      onChecklist: words ? _checklist : null,
      table: _tableButton(),
      onAttach: _attachOrNull,
      attachMenu: !relay.desktop,
      onList: words ? (kind) => commands.run(kind == LineKind.numbered ? FormatAction.numbered : FormatAction.bulleted)
        : null,
      onLink: words ? () => unawaited(_linkBox()) : null,
      onIndent: words ? (more) => commands.run(more ? FormatAction.indentMore : FormatAction.indentLess) : null,
      onHideKeyboard: _done,
      onRecord: _recordOrNull,
    );
  }

  Widget _tableButton() => TableButton(onAdd: _trash ? null : _addTable, inTable: _state.inTable,
    onConvert: () => _page.run('table-convert'), onDelete: () => _page.run('table-delete'));

  /// A pick in the computer's *Text styles* menu: the words keep the cursor.
  void _pick(FormatAction action) {
    format(action);
    if (action != FormatAction.table && action != FormatAction.link) _page.run('focus');
  }

  /// The wide layout's one bar: *New note*, then *Aa*, *Checklist*, *Table* and *Attach*, then *Share* and ⋯, then
  /// search.
  PreferredSizeWidget _paneBar(BrandColors brand) => PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(spacing: 10, children: [
        ButtonPill(children: [PillIconButton(icon: CupertinoIcons.square_pencil, tooltip: 'New note', onPressed: _compose)]),
        ExcludeFocus(child: ButtonPill(children: [
          FormatMenu(page: _page, onPick: _pick, colour: relay.settings.highlightColour,
            onColour: relay.setHighlightColour, enabled: !_trash && !_state.inTable),
          PillIconButton(icon: CupertinoIcons.checkmark_circle, tooltip: 'Checklist',
            onPressed: _trash || _state.inTable ? null : _checklist),
          _tableButton(),
          AttachButton(onPick: _attachOrNull, menu: false),
        ])),
        // Search gives up width first, so a narrow pane keeps every tool.
        Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
          ButtonPill(children: [
            PillIconButton(icon: CupertinoIcons.square_arrow_up, tooltip: 'Share', onPressed: _share),
            _more(),
          ]),
          if (widget.search case final search?) Flexible(child: search),
        ])),
      ]),
    )),
  );

  /// Built with the list, so a pin from another device changes *Pin Note* to *Unpin Note* while the page is open.
  Widget _more() => ListenableBuilder(listenable: relay, builder: (context, _) => _trash
    ? MoreMenu(
        items: [('Recover', CupertinoIcons.arrow_uturn_left, () => unawaited(_recover())), ('Copy', CupertinoIcons.doc_on_doc, _copy)],
        destructive: ('Delete', CupertinoIcons.trash, () => unawaited(_deleteForever())),
        builder: (context, toggle) => PillIconButton(icon: CupertinoIcons.ellipsis, tooltip: 'More', onPressed: toggle),
      )
    : MoreMenu(
    items: [
      if (_current case final note?)
        note.pinned ? ('Unpin Note', CupertinoIcons.pin_slash, _pin) : ('Pin Note', CupertinoIcons.pin, _pin),
      // The browser has its own find, Ctrl+F; the Mac's ⌘F goes to the notes search, so the Mac keeps this one.
      if (!relay.web) ('Find in Note', CupertinoIcons.search, _openFind),
      ('Copy', CupertinoIcons.doc_on_doc, _copy),
    ],
    destructive: ('Delete', CupertinoIcons.trash, _delete),
    builder: (context, toggle) => PillIconButton(icon: CupertinoIcons.ellipsis, tooltip: 'More', onPressed: toggle),
  ));
}
