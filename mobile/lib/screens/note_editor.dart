import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoAlertDialog, CupertinoDialogAction, CupertinoIcons,
  CupertinoTextField, showCupertinoDialog;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_editor/super_editor.dart';

import '../brand.dart';
import '../data/client_id.dart';
import '../editor/attachments.dart';
import '../editor/links.dart';
import '../editor/markdown.dart';
import '../editor/note_commands.dart';
import '../editor/note_editing.dart';
import '../editor/note_style.dart';
import '../editor/paste.dart';
import '../editor/shortcuts.dart';
import '../editor/system_menu.dart';
import '../editor/table.dart';
import '../relay.dart';
import '../web/paste.dart';
import 'back_to.dart';
import 'days.dart';
import 'folder.dart' show Opener, askAlert, browserProblem, openInBrowser, showProblemOn;
import 'hold_to_talk.dart' show recordFromShortcut;
import 'more_menu.dart';
import 'note_bars.dart';
import 'note_blocks.dart';
import 'round_button.dart';
import 'timeline.dart' show askDeleteForever;

export '../editor/links.dart' show linkAddressOf, linkAt, linkAtPosition, linkRanges, linkRunAt, withLinks;

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

/// The room the floating tool bar or find bar takes over the keyboard, with a margin: the caret scrolls above it.
const barRoom = 64.0;

/// The room kept over the caret when the page scrolls up to it, as the editor keeps.
const _caretTopRoom = 8.0;

/// A key the browser's page takes, not the editor: new note, search and delete.
class PageKeyIntent extends Intent {
  const PageKeyIntent();
}

/// The page's keys, with Ctrl or ⌘. No action takes [PageKeyIntent], so each passes up to the page: Ctrl+F does not
/// open the editor's own find box, and Ctrl+Shift+Backspace deletes the note, not a word.
final pageKeys = <ShortcutActivator, Intent>{
  for (final mac in [false, true]) ...{
    SingleActivator(LogicalKeyboardKey.keyN, control: !mac, meta: mac, alt: true): const PageKeyIntent(),
    SingleActivator(LogicalKeyboardKey.keyF, control: !mac, meta: mac): const PageKeyIntent(),
    SingleActivator(LogicalKeyboardKey.backspace, control: !mac, meta: mac, shift: true): const PageKeyIntent(),
  },
};

/// The iPhone's own *Paste* hands the clipboard here (`ios/Runner/RelayPaste.swift`): `paste` with `html` and
/// `plain`, answered true when a note put the words in, else false, and the phone pastes the plain words itself.
const pasteChannel = MethodChannel('relay/paste');

/// One note's page, as Apple Notes has it: the note to read, and a tap in its words edits it in place. A new note
/// opens with the keyboard up and a Title first line. Each change is kept on a pause and on leave, with no *Save*.
class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.relay, this.entry, this.picker, this.sharer, this.opener, this.back = 'Notes',
    this.pane = false, this.onClose, this.onCompose, this.search});

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

  @override
  State<NoteEditor> createState() => NoteEditorState();
}

/// The app's own runners hand a paste the clipboard's HTML here: `html` answers it, or null. The Mac reads it in
/// `macos/Runner/MainFlutterWindow.swift`, the iPhone and iPad in `ios/Runner/RelayPaste.swift`, and Android in
/// `MainActivity.kt`. Where no one answers, such as on Windows, a paste reads the plain words.
const clipboardChannel = MethodChannel('relay/clipboard');

/// The clipboard's HTML where the app can read it, else null.
Future<String?> clipboardHtml() async {
  if (kIsWeb) return null;
  try {
    return await clipboardChannel.invokeMethod<String>('html');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Whether two lists of nodes hold the same nodes, line for line.
bool sameNodes(List<DocumentNode> a, List<DocumentNode> b) {
  if (a.length != b.length) return false;
  for (var at = 0; at < a.length; at++) {
    if (!identical(a[at], b[at]) && a[at] != b[at]) return false;
  }
  return true;
}

class NoteEditorState extends State<NoteEditor> {
  late final String _id = widget.entry?.id ?? newClientId();
  /// The phone keeps the note: set only once an add kept it, so a save after an add that kept nothing adds again.
  late bool _stored = widget.entry != null;
  /// Saves made before the phone kept the note that still wait in [_writing]: a save meanwhile goes after them, so
  /// words cleared meanwhile still delete the note on leave.
  int _adds = 0;
  /// The note's document, its selection and its Undo.
  late final NoteEditing _editing;
  /// The note's tables: the cell in use, and the cell changes still to write.
  late final NoteTables _tables;
  /// The nodes as last kept.
  late List<DocumentNode> _saved;
  /// The words as last kept: a file added to an unchanged note keeps them as they were.
  late String _savedText = _current?.text ?? '';
  /// A change that is no edit, such as a link found in the words: no save follows it.
  bool _quiet = false;
  final _focus = FocusNode();
  final _layout = GlobalKey();
  final _scroll = ScrollController();
  static var _pages = 0;
  final _inputRole = 'note ${_pages++}';
  late final SuperEditorIosControlsController _iosControls = SuperEditorIosControlsController(
    toolbarBuilder: noteIosToolbar(_menuActions, () => _iosControls));
  late final SuperEditorAndroidControlsController _androidControls = SuperEditorAndroidControlsController(
    toolbarBuilder: noteAndroidToolbar(_menuActions, () => _androidControls));
  late final _menuActions = NoteMenuActions(
    hasSelection: () => !(_editing.composer.selection?.isCollapsed ?? true),
    cut: _cut, copy: _copySelection, paste: () => unawaited(_pasteFromClipboard()), selectAll: _selectAll,
    selectionChanges: _editing.composer.selectionNotifier);
  final _contextMenu = ContextMenuController();
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
  /// Set with the keyboard, or at once when a button brings it up, so the edit that comes first waits for a pause.
  late bool _typing = widget.entry == null;
  double _keyboard = 300;
  /// The note held open before this page, such as the note page a voice note from Shortcuts opens over: leaving gives
  /// the hold back to it, so a pull does not change that note's words under its page.
  String? _heldBefore;
  /// *Find in Note* is open: its bar takes the tool bar's place, with its own field.
  bool _finding = false;
  final _find = TextEditingController();
  final _findFocus = FocusNode();
  /// Where each match of [_find] is in the words, and which one is selected.
  List<TextRange> _matches = const [];
  int _match = 0;
  /// A scroll to the caret waits for the frame: one is enough for each frame.
  bool _revealing = false;
  double _inset = 0;
  /// Stops the browser's paste events reaching this note.
  late final void Function() _stopPastes;

  /// Every file the page has placed in the words: one gone from them since was removed, and is not placed again.
  final _shown = <String>{};
  /// Where each file added on this page goes, by id: the node with the cursor then, or null for the end.
  final _placeAt = <String, String?>{};
  /// Saves still running: a file gone from the note leaves the words only after them, as *Undo* may bring it back.
  int _saving = 0;

  /// The note whose words have the cursor: the iPhone's own *Paste* goes there.
  static NoteEditorState? _pasteTarget;

  /// The words last copied in a note, with their styles, tables and files: a paste of the same plain words puts
  /// these back.
  static ({String plain, List<DocumentNode> nodes})? _copied;

  Relay get relay => widget.relay;
  /// The note's own id, made here for a new note.
  String get id => _id;

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

  /// The note's document, for a test.
  @visibleForTesting
  NoteEditing get editing => _editing;

  /// The layout of the note's words, for a test.
  @visibleForTesting
  DocumentLayout get documentLayout => _layout.currentState! as DocumentLayout;

  /// The note reads only, as a note in *Recently Deleted* does.
  bool get readOnly => _trash;

  @override
  void initState() {
    super.initState();
    // The list as it is now: a voice note's going can come between the tap that opens it and this.
    final entry = _current;
    _editing = NoteEditing(_nodesOf(entry))..keepFiles = () => _current?.from != null;
    _saved = _editing.nodes;
    _tables = NoteTables(_editing)..addListener(_tablesChanged);
    _editing.addListener(_edited);
    _trash = _inTrash;
    _focus.canRequestFocus = !_trash;
    _editing.composer.selectionNotifier.addListener(_caretMoved);
    _focus.addListener(_focusChanged);
    relay.addListener(_relayChanged);
    // The browser's layout holds one note at a time: the note before has closed, so nothing gets the hold back.
    _heldBefore = widget.onClose == null ? relay.openNote : null;
    relay.openNote = _id;
    relay.editorWords = _words;
    pasteChannel.setMethodCallHandler(_pasteCall);
    _stopPastes = listenPastes(({String? html, required String plain}) => _focus.hasFocus && _paste(html: html, plain: plain));
    if (_stored && _live == null) _gone();
  }

  /// A note's words with each file at its place. A file the text does not name, as in an older note, goes where the
  /// page showed it before: the recording a voice note started with first, and the rest after the words. A new note
  /// starts with an empty Title line.
  List<DocumentNode> _nodesOf(Entry? entry) {
    if (entry == null) return [lineNode(LineKind.header1, AttributedText())];
    final files = filesOf(entry);
    final words = withLinks(markdownToNodes(entry.text, title: true, files: {for (final file in files) file.file.id}));
    final placed = attachmentIdsIn(words);
    _shown.addAll([for (final file in files) file.file.id]);
    return withFilesPlaced(words,
      top: [for (final file in files) if (file.top && !placed.contains(file.file.id)) file.file],
      rest: [for (final file in files) if (!file.top && !placed.contains(file.file.id)) file.file]);
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

  /// Each change of the words saves, on a pause while typing; a change that is no edit does not.
  void _edited() {
    if (_quiet || !mounted) return;
    _changed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigator = Navigator.maybeOf(context, rootNavigator: true);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    _measureKeyboard(inset);
    // The keyboard coming up shrinks the page under the caret.
    if (inset != _inset && _focus.hasFocus) _revealCaret();
    _inset = inset;
  }

  /// The Format panel takes the keyboard's height. Only a keyboard up for the cursor counts: while it slides down for
  /// the panel, each frame's height is part of the way.
  void _measureKeyboard(double inset) {
    if (_focus.hasFocus && inset > 100) _keyboard = inset;
  }

  /// The words as they are now: the same as kept, or new ones not yet kept.
  ({String id, String text})? _words() {
    if (_deleted) return null;
    _tables.flush();
    final nodes = _editing.nodes;
    final text = sameNodes(nodes, _saved) ? _savedText : _markdownOf(nodes);
    return (id: _id, text: _kept(text));
  }

  @override
  void dispose() {
    _tables.flush();
    _save(sendNow: true, leaving: true);
    unawaited(_writing.then((_) => relay.closedNote(_id)));
    if (relay.openNote == _id) relay.openNote = _heldBefore;
    if (relay.editorWords == _words) relay.editorWords = null;
    relay.removeListener(_relayChanged);
    if (_pasteTarget == this) _pasteTarget = null;
    _stopPastes();
    _pause?.cancel();
    _contextMenu.remove();
    _editing.composer.selectionNotifier.removeListener(_caretMoved);
    _editing.removeListener(_edited);
    _tables.dispose();
    _focus.dispose();
    _find.dispose();
    _findFocus.dispose();
    _scroll.dispose();
    _iosControls.dispose();
    _androidControls.dispose();
    _editing.dispose();
    super.dispose();
  }

  /// The format panel lets go of the cursor, but the person is still editing; the cursor coming back closes it. When
  /// editing ends, an address typed meanwhile becomes a link.
  void _focusChanged() {
    if (_focus.hasFocus) {
      _pasteTarget = this;
    } else if (_pasteTarget == this) {
      _pasteTarget = null;
    }
    if (_focus.hasFocus) _formatting = false;
    // The note's words took the cursor from a table's cell.
    if (_focus.hasFocus) _tables.leave();
    // A tap in the words while finding edits them, as in Apple Notes: find mode ends, and the tool bar comes back.
    if (_focus.hasFocus && _finding) _endFind();
    if (_focus.hasFocus) _revealCaret();
    if (!_focus.hasFocus) _contextMenu.remove();
    _typing = _editing_;
    if (!_typing && mounted) _markLinks();
    if (mounted) setState(() {});
  }

  /// The person edits the note: its words or a table's cell have the cursor, or the Format sheet is open.
  bool get _editing_ => _focus.hasFocus || _formatting || _tables.active != null;

  /// A table's cell took the cursor, or gave it up: the page shows the keyboard's bar while a cell has it.
  void _tablesChanged() {
    _typing = _editing_;
    if (_tables.active != null && _finding) _endFind();
    if (mounted) setState(() {});
  }

  /// A recording made into a new note keeps it, so the next save edits it. A kept note gone from the list closes the
  /// page. A file new to the note takes its place in the words.
  void _relayChanged() {
    if (!_stored && !_deleted && _adds == 0 && relay.entries.any((entry) => entry.id == _id)) _stored = true;
    if (_stored && !_deleted && _live == null) return _gone();
    // Deleted or recovered, here or on another device: the words lock or open.
    if (_inTrash != _trash) {
      setState(() => _trash = _inTrash);
      _focus.canRequestFocus = !_trash;
      if (_trash) _focus.unfocus();
    }
    _placeFiles();
  }

  /// Puts each file new to the note in the words: one added on this page where it was asked for, as a change that
  /// saves, and one from elsewhere, such as a recording the phone kept, at the end, as no change. A file the note no
  /// longer has leaves the words, once every save is done.
  void _placeFiles() {
    final note = _current;
    if (note == null || _trash || _deleted) return;
    final files = filesOf(note);
    final held = {for (final file in files) file.file.id};
    if (_saving == 0 && sameNodes(_editing.nodes, _saved)) {
      // Undo steps keep the file: Undo of its removal on this page brings it back, and the save sends it again.
      _silently(undoSteps: false, (nodes) {
        final kept = [for (final node in nodes) if (node is! AttachmentNode || held.contains(node.file.id)) node];
        return kept.length == nodes.length ? null : kept;
      });
    }
    final placed = attachmentIdsIn(_editing.nodes);
    final missing = [for (final file in files) if (!placed.contains(file.file.id) && !_shown.contains(file.file.id)) file.file];
    if (missing.isEmpty) return;
    _shown.addAll(missing.map((file) => file.id));
    final asked = <String?, List<NoteAttachment>>{};
    for (final file in missing.where((file) => _placeAt.containsKey(file.id))) {
      (asked[_placeAt.remove(file.id)] ??= []).add(file);
    }
    for (final MapEntry(key: at, value: files) in asked.entries) {
      final place = placeFiles(_editing.nodes, files, at);
      final caret = place.nodes.firstWhere((node) => node.id == place.caret);
      _editing.breakTyping();
      // A place asked at the cursor moves the cursor under the files, also while a picker or the recording screen
      // has the keyboard: the words typed next go under them.
      _editing.setNodes(place.nodes, keepSelection: true, selection: at == null ? null
        : DocumentSelection.collapsed(position: DocumentPosition(nodeId: caret.id, nodePosition: caret.beginningPosition)));
    }
    final rest = [for (final file in missing) if (!asked.values.any((files) => files.contains(file))) file];
    if (rest.isNotEmpty) _silently((nodes) => placeFiles(nodes, rest, null).nodes);
  }

  /// Makes [change] with no Undo step and no save: a note kept as it was stays kept. Each Undo step takes it too,
  /// unless [undoSteps] is false.
  void _silently(List<DocumentNode>? Function(List<DocumentNode> nodes) change, {bool undoSteps = true}) {
    final kept = sameNodes(_editing.nodes, _saved);
    _quiet = true;
    try {
      _editing.changeEverywhere(change, undoSteps: undoSteps);
    } finally {
      _quiet = false;
    }
    if (kept) _saved = _editing.nodes;
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

  /// Typing saves on a pause. A change with the keyboard down, such as a ticked circle, is kept at once.
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
    if (_deleted || _trash) return;
    _tables.flush();
    final nodes = _editing.nodes;
    final same = sameNodes(nodes, _saved);
    final text = same ? _savedText : _markdownOf(nodes);
    // Blank words, such as only an empty Title line, are kept as none, so a note of files alone is not `#`.
    final empty = plainText(text).trim().isEmpty;
    final note = _current;
    final inWords = attachmentIdsIn(nodes);
    // A file gone from the words was removed: only the phone that made the note may remove one.
    final removed = note == null || note.from != null ? const <String>{}
      : {for (final file in filesOf(note)) if (_shown.contains(file.file.id) && !inWords.contains(file.file.id)) file.file.id};
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
    _saved = nodes;
    _savedText = text;
    if (!leaving) _markLinks();
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

  /// The Markdown of [nodes], with their links as [_markLinks] puts them, so an edited address that still has its old
  /// link is written as its words.
  String _markdownOf(List<DocumentNode> nodes) => documentToMarkdown(withLinks(nodes));

  /// Marks the links in the shown note again, as [withLinks] does when the note opens, so an address typed in this
  /// visit opens too, and an edited one opens what its words now say. The marks change no stored words: the Markdown
  /// codec writes an address with its own link as the bare address. A note kept as it is stays kept, so the marks
  /// alone never write it back.
  void _markLinks() => _silently((nodes) {
    final linked = withLinks(nodes);
    return identical(linked, nodes) ? null : linked;
  });

  /// The iPhone's own *Paste*: true when the note with the cursor put the words in.
  static Future<Object?> _pasteCall(MethodCall call) async {
    if (call.method != 'paste') throw MissingPluginException();
    final words = call.arguments is Map ? call.arguments as Map : const {};
    final target = _pasteTarget;
    if (target == null || !target.mounted || !target._focus.hasFocus) return false;
    return target._paste(html: words['html'] as String?, plain: words['plain'] as String? ?? '');
  }

  /// The note's own paste, from its menu or a keyboard's paste keys: the clipboard's HTML and plain words go through
  /// [_paste], so the note never pastes the page's colours and sizes.
  Future<void> _pasteFromClipboard() async {
    final html = await clipboardHtml();
    final plain = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (mounted) _paste(html: html, plain: plain);
  }

  /// Puts a paste at the cursor in one change, so one *Undo* takes it back. A copy from inside a note pastes back with
  /// its styles; anything else keeps only the styles the note can store ([pastedNodes]). Addresses in it show as
  /// links, as [withLinks] marks them. True when the paste is handled, even with no words.
  bool _paste({String? html, required String plain}) {
    final selection = _editing.composer.selection;
    if (selection == null) return false;
    final copied = _copied;
    final List<DocumentNode> pasted;
    if (plain.isNotEmpty && copied != null && plain == copied.plain && copied.nodes.isNotEmpty) {
      // A copied table pastes as a table of its own, so a change in one never goes into the other.
      pasted = [for (final node in copied.nodes) _fresh(node)];
    } else {
      final from = pastedNodes(html: html, plain: plain);
      pasted = from.isEmpty ? from : withLinks(from);
    }
    final paste = pasteInto(_editing.nodes, selection, pasted);
    if (paste == null) return true;
    _editing.breakTyping();
    _editing.setNodes(paste.nodes, selection: paste.caret);
    _editing.breakTyping();
    _revealCaret();
    return true;
  }

  /// [node] with a new id, and a new table id for a table.
  static DocumentNode _fresh(DocumentNode node) => switch (node) {
    final TextNode line => lineNode(kindOf(line), line.text, indent: indentOf(line)),
    NoteTableNode() => withNewTableId(node),
    AttachmentNode(:final file) => AttachmentNode(id: Editor.createNodeId(), file: file),
    _ => node,
  };

  /// *Copy*: the words picked go on the clipboard as plain words, and the note keeps them with their styles.
  void _copySelection() {
    final selection = _editing.composer.selection;
    if (selection == null || selection.isCollapsed) return;
    final nodes = copiedNodes(_editing.nodes, DocumentRange(start: selection.base, end: selection.extent));
    final plain = copiedText(nodes);
    _copied = (plain: plain, nodes: nodes);
    unawaited(Clipboard.setData(ClipboardData(text: plain)));
  }

  /// *Cut*: a copy, then the words picked go, as one change.
  void _cut() {
    final selection = _editing.composer.selection;
    if (selection == null || selection.isCollapsed || _trash) return;
    _copySelection();
    final (:nodes, :caret) = deleteRange(_editing.nodes, DocumentRange(start: selection.base, end: selection.extent));
    _editing.breakTyping();
    _editing.setNodes(nodes, selection: DocumentSelection.collapsed(position: caret));
  }

  /// *Select All*: every word of the note.
  void _selectAll() {
    final nodes = _editing.nodes;
    _editing.selectAt(DocumentSelection(
      base: DocumentPosition(nodeId: nodes.first.id, nodePosition: nodes.first.beginningPosition),
      extent: DocumentPosition(nodeId: nodes.last.id, nodePosition: nodes.last.endPosition)));
  }

  /// The note's own keys, before the editor's: paste, copy and cut keep the note's styles, Undo and Redo are the
  /// note's own, and Backspace under a file or a table takes it.
  ExecutionInstruction _noteKeys({required SuperEditorContext editContext, required KeyEvent keyEvent}) {
    if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) return ExecutionInstruction.continueExecution;
    final keys = HardwareKeyboard.instance;
    final command = keys.isMetaPressed || keys.isControlPressed;
    final key = keyEvent.logicalKey;
    if (command && !keys.isAltPressed) {
      if (key == LogicalKeyboardKey.keyV && !keys.isShiftPressed) {
        // The browser pastes on its own paste event, which [listenPastes] takes.
        if (kIsWeb) return ExecutionInstruction.blocked;
        unawaited(_pasteFromClipboard());
        return ExecutionInstruction.haltExecution;
      }
      if (key == LogicalKeyboardKey.keyC && !keys.isShiftPressed) {
        _copySelection();
        return ExecutionInstruction.haltExecution;
      }
      if (key == LogicalKeyboardKey.keyX && !keys.isShiftPressed) {
        _cut();
        return ExecutionInstruction.haltExecution;
      }
      if (key == LogicalKeyboardKey.keyZ) {
        _tables.flush();
        keys.isShiftPressed ? _editing.redo() : _editing.undo();
        return ExecutionInstruction.haltExecution;
      }
    }
    if (key == LogicalKeyboardKey.backspace && !command && !keys.isAltPressed && !keys.isShiftPressed &&
        _editing.backspaceTakesBlock()) {
      return ExecutionInstruction.haltExecution;
    }
    return ExecutionInstruction.continueExecution;
  }

  void _say(String message) => unawaited(showProblemOn(_navigator, message));

  void _done() {
    // A table's cell gives up the cursor too.
    if (_tables.active != null) FocusManager.instance.primaryFocus?.unfocus();
    _tables.leave();
    setState(() => _formatting = _typing = false);
    _focus.unfocus();
    _editing.selectAt(null);
    _save(sendNow: true);
  }

  /// *Aa*: the keyboard goes down and the panel takes its place. The note keeps the words picked while the panel
  /// styles them.
  void _styles() {
    setState(() => _formatting = true);
    _focus.unfocus();
  }

  void _closeStyles() => _focus.requestFocus();

  /// *Undo* and *Redo* change the words as typing does, so the save on a pause keeps them; the keyboard stays up.
  Widget _history() => ListenableBuilder(listenable: _editing, builder: (context, _) {
    if (!_editing.hasUndo && !_editing.hasRedo) return const SizedBox.shrink();
    // A cell's words still waiting go in first, so Undo takes back the last change.
    void undo() {
      _tables.flush();
      _editing.undo();
    }
    void redo() {
      _tables.flush();
      _editing.redo();
    }
    return Padding(padding: const EdgeInsets.only(right: 8), child: _editing.hasRedo
      ? ButtonPill(children: [
          PillIconButton(icon: CupertinoIcons.arrow_uturn_left, tooltip: 'Undo', onPressed: _editing.hasUndo ? undo : null),
          PillIconButton(icon: CupertinoIcons.arrow_uturn_right, tooltip: 'Redo', onPressed: redo),
        ])
      : RoundIconButton(icon: CupertinoIcons.arrow_uturn_left, tooltip: 'Undo', onPressed: _editing.hasUndo ? undo : null));
  });

  /// ⋯ → *Find in Note*: the find bar takes the keyboard from the words, so typing there changes nothing in the note.
  void _openFind() {
    setState(() => _finding = true);
    _findFocus.requestFocus();
  }

  /// Each match keeps its place in the words as they are: no lowercase copy, whose length can differ, as for *İ*. A
  /// match in a table's cell selects the table.
  void _findChanged() {
    final words = _find.text;
    final pattern = RegExp(RegExp.escape(words), caseSensitive: false);
    final tables = <(int, NoteTable)>[];
    var offset = 0;
    for (final node in _editing.nodes) {
      if (node is NoteTableNode) tables.add((offset, node.table));
      offset += (node is TextNode ? node.text.length : 1) + 1;
    }
    final matches = words.isEmpty ? <TextRange>[] : [
      for (final match in pattern.allMatches(_editing.text)) TextRange(start: match.start, end: match.end),
      for (final (offset, table) in tables)
        for (final cell in table.rows.expand((row) => row))
          for (final _ in pattern.allMatches(cell)) TextRange(start: offset, end: offset + 1),
    ]..sort((a, b) => a.start - b.start);
    setState(() {
      _matches = matches;
      _match = 0;
    });
    if (matches.isNotEmpty) _select(matches.first);
  }

  /// Down (1) or up (-1) to the next match, round from the last to the first.
  void _step(int step) {
    setState(() => _match = (_match + step) % _matches.length);
    _select(_matches[_match]);
  }

  /// Selects a match as a mark on the page, not a change: the keyboard stays with the find bar.
  void _select(TextRange match) {
    _editing.select(TextSelection(baseOffset: match.start, extentOffset: match.end));
    _revealCaret();
  }

  /// While editing or finding, each move of the caret scrolls the page so the caret shows above the floating bar.
  void _caretMoved() {
    if (_focus.hasFocus || _finding) _revealCaret();
  }

  /// Scrolls the page, after the frame, so the caret's line shows under the top edge and above the bar. The editor
  /// scrolls the caret only to the page's bottom edge, under the bar: this runs after its own scroll in the same frame.
  void _revealCaret() {
    if (_revealing) return;
    _revealing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealing = false;
      final layout = _layout.currentState;
      final sliver = _layout.currentContext?.findRenderObject();
      final selection = _editing.composer.selection;
      if (!mounted || layout is! DocumentLayout || sliver == null || !sliver.attached || !_scroll.hasClients ||
          selection == null) {
        return;
      }
      final words = layout as DocumentLayout;
      final caret = words.getRectForPosition(selection.extent);
      final viewport = RenderAbstractViewport.of(sliver);
      if (caret == null || viewport is! RenderBox) return;
      final position = _scroll.position;
      // The caret's place in the whole page, from the page's top.
      final top = (viewport as RenderBox).globalToLocal(words.getGlobalOffsetFromDocumentOffset(caret.topLeft)).dy +
        position.pixels;
      final above = top - _caretTopRoom, below = top + caret.height + barRoom;
      final to = above < position.pixels ? above
        : below > position.pixels + position.viewportDimension ? below - position.viewportDimension : null;
      if (to != null) _scroll.jumpTo(to.clamp(position.minScrollExtent, position.maxScrollExtent));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// ✓ on the find bar: the match stays as the caret, with the keyboard down.
  void _closeFind() {
    final end = _editing.selection.end;
    _endFind();
    if (end >= 0) _editing.select(TextSelection.collapsed(offset: end));
  }

  void _endFind() {
    _find.clear();
    _findFocus.unfocus();
    setState(() {
      _finding = false;
      _matches = const [];
    });
  }

  /// ⋯ → *Pin Note* or *Unpin Note*; a new note not kept yet has nothing to pin.
  void _pin() {
    final note = _current;
    if (note != null) unawaited(relay.pinNote(_id, !note.pinned));
  }

  /// *Checklist*: the cursor's line becomes a checklist item, or stops being one. With the keyboard down it adds an
  /// item at the end and brings the keyboard up.
  void _checklist() {
    if (!_focus.hasFocus) {
      _typing = true;
      final nodes = _editing.nodes;
      final last = nodes.last;
      if (last is TextNode && last.text.isEmpty) {
        _editing.selectAt(DocumentSelection.collapsed(
          position: DocumentPosition(nodeId: last.id, nodePosition: last.endPosition)));
      } else {
        final line = lineNode(LineKind.paragraph, AttributedText());
        _editing.breakTyping();
        _editing.setNodes([...nodes, line], selection: DocumentSelection.collapsed(
          position: DocumentPosition(nodeId: line.id, nodePosition: const TextNodePosition(offset: 0))));
      }
      _focus.requestFocus();
    }
    NoteCommands(_editing).checklist();
  }

  /// A tap on a checklist circle ticks its line, or takes the tick off.
  void _tick(String nodeId, bool ticked) {
    if (_trash) return;
    final nodes = _editing.nodes;
    _editing.breakTyping();
    _editing.setNodes([
      for (final node in nodes)
        node is TextNode && node.id == nodeId
          ? lineNode(ticked ? LineKind.checked : LineKind.unchecked, node.text, indent: indentOf(node), id: node.id)
          : node,
    ], keepSelection: true);
  }

  /// *Attach* → *Photos* or *Files*. The browser has one picker for every kind of file.
  Future<void> _attach({required bool photos}) async {
    // The cursor's place before the picker: the phone's picker takes the keyboard while it is open. The files go
    // there once the note keeps them.
    final editing = _focus.hasFocus;
    final at = editing ? _editing.composer.selection?.extent.nodeId : null;
    final List<NewFile> picked;
    try {
      picked = await (widget.picker ?? pickWithPhone)(photos: photos);
    } on Exception {
      return _say('The ${relay.web ? 'browser' : relay.desktop ? 'Mac' : 'phone'} did not give the file. Try again.');
    }
    if (!mounted || picked.isEmpty) return;
    _save(sendNow: !editing && !_focus.hasFocus, files: _placed(picked, at));
  }

  /// [files], each with the id the note will keep it by, and asked to go under the line [at], or at the end.
  List<NewFile> _placed(List<NewFile> files, String? at) {
    final placed = [for (final file in files) file.withId(newClientId())];
    for (final file in placed) {
      _placeAt[file.id!] = at;
    }
    return placed;
  }

  String get _plain => plainText(documentToMarkdown(_editing.nodes));

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

  /// Files dropped on the note in the browser: they join it as the paperclip's do. A note from elsewhere takes none.
  void addFiles(List<NewFile> files) {
    if (files.isEmpty || _trash) return;
    if (_attachOrNull == null) return _say('You can add files only to a note you wrote here or on your phone.');
    _save(sendNow: true, files: _placed(files, null));
  }

  /// A format item from the computer's keys, its *Text styles* menu or right-click menu, or the Mac's *Format* menu: on
  /// the words picked or the cursor's line, as Notes does. A table's cell holds plain words, so only *Table* acts
  /// there.
  void format(FormatAction action) {
    if (_trash) return;
    if (action == FormatAction.table) return _addTable();
    if (_tables.active != null) return;
    if (action == FormatAction.link) return unawaited(_linkBox());
    NoteCommands(_editing).run(action, colour: relay.settings.highlightColour);
  }

  /// *Table*: a table of 2 columns and 2 rows at the cursor, with the cursor in its first cell.
  void _addTable() {
    if (_trash) return;
    _typing = true;
    _tables.insert();
  }

  /// *Table* → *Convert to text* or *Delete table*: the cursor goes where the table was.
  void _tableGone(String? nodeId) {
    if (nodeId == null || !mounted) return;
    _focus.requestFocus();
  }

  /// The link on every letter of [range] in the words, or null when they have none or more than one.
  String? _linkOn(List<DocumentNode> nodes, TextRange range) {
    final links = {for (var at = range.start; at < range.end; at++) linkAt(nodes, at)};
    return links.length == 1 ? links.single : null;
  }

  /// Puts [address] as the link on [range] of the words, or takes the link off with null.
  void _setLink(TextRange range, String? address) {
    final nodes = _editing.nodes;
    final picked = documentSelectionOf(nodes, TextSelection(baseOffset: range.start, extentOffset: range.end));
    final span = DocumentRange(start: picked.base, end: picked.extent);
    final now = {for (var at = range.start; at < range.end; at++) ?linkAt(nodes, at)};
    _editing.breakTyping();
    _editing.editor.execute([
      if (now.isNotEmpty) RemoveTextAttributionsRequest(documentRange: span,
        attributions: {for (final link in now) LinkAttribution(link)}),
      if (address != null) AddTextAttributionsRequest(documentRange: span, attributions: {LinkAttribution(address)}),
    ]);
  }

  /// *Link*: a box for the address of the words picked, filled from a copied web address. On a link it changes the
  /// address or takes the link away. With no words picked, the address goes in as its own words.
  Future<void> _linkBox() async {
    final selection = _editing.selection;
    if (_trash || _tables.active != null || selection.start < 0) return;
    final nodes = _editing.nodes;
    final run = selection.isCollapsed ? linkRunAt(nodes, selection.start) : null;
    final now = run != null ? linkAt(nodes, run.start) : selection.isCollapsed ? null
      : _linkOn(nodes, TextRange(start: selection.start, end: selection.end));
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
    if (answer == null || !mounted) return;
    final whole = run ?? TextRange(start: selection.start, end: selection.end);
    if (answer.trim().isEmpty) {
      if (now != null) _setLink(whole, null);
      return;
    }
    final address = linkAddressOf(answer);
    if (address == null) return _say('That is not a web address. Try again.');
    if (run != null || !selection.isCollapsed) return _setLink(whole, address);
    _editing.select(TextSelection.collapsed(offset: selection.start));
    _editing.breakTyping();
    _editing.type(address);
    _setLink(TextRange(start: selection.start, end: selection.start + address.length), address);
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

  /// A tap in the words. In *Recently Deleted* it asks to recover the note. A tap on a table, a file or a checklist
  /// circle is theirs. While reading, a tap on a link opens it, and the keyboard stays down. Any other tap places the
  /// cursor. True when the page took the tap.
  bool _tapped(Offset global, DocumentPosition? position) {
    final reading = !_focus.hasFocus && !_formatting;
    // A mouse's tap asks for the keyboard before the page sees it: a tap the page takes while reading gives it back.
    void keepReading() {
      if (reading) scheduleMicrotask(() => _focus.unfocus());
    }
    if (_trash) {
      if (!isOnAttachment(context, global)) unawaited(_askRecover());
      return true;
    }
    if (isOnTable(context, global)) return true;
    if (isOnAttachment(context, global) || isOnCircle(context, global)) {
      keepReading();
      return true;
    }
    // On an iPhone a touch outside the system menu closes it at touch down: the tap up on the cursor opens nothing.
    final caret = _editing.composer.selection;
    if (NoteSystemMenu.closedJustNow() && position != null && caret != null && caret.isCollapsed &&
        offsetAt(_editing.nodes, position) == offsetAt(_editing.nodes, caret.extent)) {
      return true;
    }
    if (!reading || position == null) return false;
    final link = linkAtDocumentPosition(_editing.nodes, position);
    if (link == null) return false;
    keepReading();
    _openLink(link);
    return true;
  }

  /// The computer's right-click menu, at [at] on the screen.
  void _showMenu(Offset at) {
    if (_trash) return;
    _contextMenu.show(context: context, contextMenuBuilder: (context) => noteContextMenu(context, anchor: at,
      actions: _menuActions, close: _contextMenu.remove, format: _pick));
  }

  Future<void> _openLink(String link) async {
    // A mail link or another with its own scheme opens as it is; `www.…` opens on the web.
    final address = Uri.tryParse(linkScheme.hasMatch(link) ? link : 'https://$link');
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
    _placeAt[id] = _focus.hasFocus ? _editing.composer.selection?.extent.nodeId : null;
    _focus.unfocus();
    _save(sendNow: false);
    await _writing;
    if (mounted) await recordFromShortcut(context, relay, into: _id, id: id);
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final editing = _editing_;
    _measureKeyboard(MediaQuery.viewInsetsOf(context).bottom);
    return Scaffold(
      appBar: widget.pane ? _paneBar(brand) : AppBar(leading: BackTo(widget.back, onPressed: widget.onClose),
        leadingWidth: BackTo.widthOf(widget.back), actions: [
        if (editing && !_finding) _history(),
        ButtonPill(children: [
          PillIconButton(icon: CupertinoIcons.square_arrow_up, tooltip: 'Share', onPressed: _share),
          _more(),
        ]),
        if (editing && !_finding) Padding(padding: const EdgeInsets.only(left: 8),
          child: RoundIconButton(icon: CupertinoIcons.checkmark_alt, tooltip: 'Done', onPressed: _done, accent: true)),
        const SizedBox(width: 12),
      ]),
      // A table cell's keys come up to here, past the editor's own keys.
      body: Focus(focusNode: _tables.keys, child: Column(children: [
        Expanded(child: Stack(children: [
          Positioned.fill(child: ListenableBuilder(listenable: relay, builder: (context, _) => widget.pane
            ? Align(alignment: Alignment.topCenter,
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: _page(context, brand)))
            : _page(context, brand))),
          if (!widget.pane && !_formatting && !_trash) Positioned(left: 16, right: 16, bottom: 0, child: SafeArea(
            top: false,
            minimum: EdgeInsets.only(bottom: editing || _finding ? 6 : 12),
            child: _finding
              ? FindBar(controller: _find, focus: _findFocus, onChanged: _findChanged, onDone: _closeFind,
                  found: _find.text.isEmpty ? null : _matches.isEmpty ? 'No matches' : '${_match + 1} of ${_matches.length}',
                  onStep: _matches.isEmpty ? null : _step)
              : editing
              ? _keyboardBar()
              : ReadingBar(onChecklist: _checklist, onAttach: _attachOrNull, onCompose: _compose, attachMenu: !relay.desktop,
                  onRecord: _recordOrNull),
          )),
        ])),
        if (!widget.pane && _formatting) FormatSheet(editing: _editing, height: _keyboard, onClose: _closeStyles,
          colour: relay.settings.highlightColour, onColour: relay.setHighlightColour),
      ])),
    );
  }

  /// Over the keyboard: the style tools while words are picked, else the scrolling tool bar. In a table's cell only
  /// *Table*, *Attach* and *Hide keyboard* act: a cell holds plain words.
  Widget _keyboardBar() => ListenableBuilder(listenable: _editing.looks, builder: (context, _) {
    if (_focus.hasFocus && !(_editing.composer.selection?.isCollapsed ?? true)) {
      return SelectionToolBar(editing: _editing, colour: relay.settings.highlightColour,
        onLink: () => unawaited(_linkBox()));
    }
    final words = _tables.active == null;
    final commands = NoteCommands(_editing);
    return FloatingToolBar(
      onStyles: words ? _styles : null,
      onChecklist: words ? _checklist : null,
      table: _tableButton(),
      onAttach: _attachOrNull,
      attachMenu: !relay.desktop,
      onList: words ? commands.listOf : null,
      onLink: words ? () => unawaited(_linkBox()) : null,
      onIndent: words ? commands.indent : null,
      onHideKeyboard: _done,
      onRecord: _recordOrNull,
    );
  });

  Widget _tableButton() => TableButton(onAdd: _trash ? null : _addTable, inTable: _tables.active != null,
    onConvert: () => _tableGone(_tables.convertActive()), onDelete: () => _tableGone(_tables.deleteActive()));

  /// A pick in the computer's *Text styles* menu: the note keeps the cursor.
  void _pick(FormatAction action) {
    format(action);
    if (action != FormatAction.table && action != FormatAction.link) _focus.requestFocus();
  }

  /// The wide layout's one bar: *New note*, then *Aa*, *Checklist*, *Table* and *Attach*, then *Share* and ⋯, then
  /// search.
  PreferredSizeWidget _paneBar(BrandColors brand) => PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(spacing: 10, children: [
        ButtonPill(children: [PillIconButton(icon: CupertinoIcons.square_pencil, tooltip: 'New note', onPressed: _compose)]),
        ButtonPill(children: [
          FormatMenu(editing: _editing, onPick: _pick, colour: relay.settings.highlightColour,
            onColour: relay.setHighlightColour, enabled: !_trash && _tables.active == null),
          PillIconButton(icon: CupertinoIcons.checkmark_circle, tooltip: 'Checklist',
            onPressed: _trash || _tables.active != null ? null : _checklist),
          _tableButton(),
          AttachButton(onPick: _attachOrNull, menu: false),
        ]),
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

  /// A recording's card, with what its page needs to go back to the note: the note's first typed line and its date.
  Widget _card(Entry? note, EntryRecording recording) {
    // The recording's page goes back to the note by its first typed line.
    final first = _editing.text.split('\n').map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty && line != blockLetter, orElse: () => '');
    // Cut by characters, not code units: half an emoji is not a string Flutter can draw.
    final letters = first.characters;
    final title = first.isEmpty ? 'Note' : letters.length > 18 ? '${letters.take(17).toString().trimRight()}…' : first;
    // A note in *Recently Deleted* reads only: its transcripts too.
    return RecordingCard(key: ValueKey(recording.id.isEmpty ? recording.recording : recording.id), relay: relay,
      recording: recording, editable: !relay.desktop && note?.from == null && !_trash, title: title,
      when: _when(context, note?.at ?? DateTime.now(), note?.from));
  }

  /// What a file's place in the words shows: its picture, its row, or its recording's card. Under the recording a voice
  /// note started with, blank words show *Add notes…*, as the empty words of a note show what to type.
  Widget? _blockOf(NoteAttachment file) {
    final note = _current;
    if (note == null) return null;
    if (note.recordings.where((recording) => recording.id == file.id).firstOrNull case final recording?) {
      final card = _card(note, recording);
      if (!recording.top || _editing.text.replaceAll(blockLetter, '').trim().isNotEmpty) return card;
      return Stack(clipBehavior: Clip.none, children: [
        card,
        // Over the empty line under the card, 7 below it, as tall as a line of words.
        Positioned(left: 0, right: 0, bottom: -32, child: IgnorePointer(child: Text('Add notes…',
          style: TextStyle(fontFamily: brandFont, fontSize: 17, height: 1.5, color: brandOf(context).muted)))),
      ]);
    }
    final kept = note.files.where((other) => other.id == file.id).firstOrNull;
    return kept == null ? null : _fileBlock(kept);
  }

  Widget _fileBlock(EntryFile file) =>
    file.picture && file.ready ? NotePicture(file: file, relay: relay) : NoteFileRow(file: file, relay: relay);

  /// The note's page: the date, then the words with each picture, file and recording at its place in them.
  Widget _page(BuildContext context, BrandColors brand) {
    final note = _current;
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    // A file with no id, such as a ring note's recording in the browser, has no place in the words.
    final recordings = [for (final recording in note?.recordings ?? const <EntryRecording>[]) if (!NoteAttachment.placeable(recording.id)) recording];
    final above = [for (final recording in recordings) if (recording.top) recording];
    final when = _when(context, note?.at ?? DateTime.now(), note?.from);
    final page = CustomScrollView(controller: _scroll, slivers: [
      SliverPadding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 0), sliver: SliverToBoxAdapter(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The date alone: nothing about sending, and no tag.
          Text(when, style: muted, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          for (final recording in above) Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(note, recording)),
        ],
      ))),
      SuperEditorIosControlsScope(controller: _iosControls, child: SuperEditorAndroidControlsScope(
        controller: _androidControls, child: SuperEditor(
        editor: _editing.editor,
        focusNode: _focus,
        // A note page opened over another has its own role: each owns the keyboard in turn.
        inputRole: _inputRole,
        autofocus: widget.entry == null,
        documentLayoutKey: _layout,
        stylesheet: noteStylesheet(context, padding: const EdgeInsets.symmetric(horizontal: 20)),
        selectionStyle: SelectionStyles(
          selectionColor: Theme.of(context).textSelectionTheme.selectionColor ?? brand.accentSoft),
        componentBuilders: [
          NoteLineComponentBuilder(onTick: _trash ? null : _tick,
            hint: above.isNotEmpty ? 'Add notes…' : 'What do you want to keep?'),
          NoteTableComponentBuilder(_tables, readOnly: _trash, style: noteBodyStyle(brand)),
          AttachmentComponentBuilder(_blockOf),
        ],
        selectionPolicies: const SuperEditorSelectionPolicies(clearSelectionWhenEditorLosesFocus: false,
          clearSelectionWhenImeConnectionCloses: false),
        imePolicies: const SuperEditorImePolicies(openKeyboardOnSelectionChange: false),
        keyboardActions: [
          // The format keys only on a computer: a phone's keyboard has no ⌘.
          if (relay.desktop) formatKeyAction(format, passUp: pageKeys),
          _noteKeys,
          ...defaultImeKeyboardActions,
        ],
        contentTapDelegateFactories: [
          (_) => NoteTapDelegate(_tapped),
          (editContext) => LineTapDelegate(editContext.editor),
        ],
      ))),
      SliverPadding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 120), sliver: SliverToBoxAdapter(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final recording in recordings) if (!recording.top)
            Padding(padding: const EdgeInsets.only(top: 14), child: _card(note, recording)),
          for (final file in note?.files ?? const <EntryFile>[]) if (!NoteAttachment.placeable(file.id))
            Padding(padding: const EdgeInsets.only(top: 14), child: _fileBlock(file)),
        ],
      ))),
    ]);
    if (!relay.desktop) return page;
    return GestureDetector(onSecondaryTapUp: (details) => _showMenu(details.globalPosition), child: page);
  }
}
