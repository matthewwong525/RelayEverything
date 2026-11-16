import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoAlertDialog, CupertinoDialogAction, CupertinoIcons,
  CupertinoTextField, showCupertinoDialog;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
// The editor's clipboard reader, for a paste's HTML: flutter_quill marks it experimental; pinned by pubspec.lock.
// ignore: experimental_member_use
import 'package:flutter_quill/internal.dart' show ClipboardServiceProvider;
import 'package:flutter_quill/quill_delta.dart';
import 'package:share_plus/share_plus.dart';

import '../brand.dart';
import '../data/client_id.dart';
import '../editor/magnifier.dart';
import '../editor/markdown.dart';
import '../editor/paste.dart';
import '../editor/shortcuts.dart';
import '../editor/system_menu.dart';
import '../editor/table.dart';
import '../relay.dart';
import '../web/paste.dart';
import 'back_to.dart';
import 'days.dart';
import 'folder.dart' show Opener, askAlert, browserProblem, openInBrowser, showProblemOn;
import 'more_menu.dart';
import 'note_bars.dart';
import 'note_blocks.dart';
import 'round_button.dart';
import 'timeline.dart' show askDeleteForever;

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

class NoteEditorState extends State<NoteEditor> {
  late final String _id = widget.entry?.id ?? newClientId();
  /// The phone keeps the note: set only once an add kept it, so a save after an add that kept nothing adds again.
  late bool _stored = widget.entry != null;
  /// Saves made before the phone kept the note that still wait in [_writing]: a save meanwhile goes after them, so
  /// words cleared meanwhile still delete the note on leave.
  int _adds = 0;
  late final QuillController _controller;
  /// The note's tables: the cell in use, and the cell changes still to write.
  late final NoteTables _tables;
  /// A space typed after Markdown marks is turning them into the line's style.
  bool _marking = false;
  late Delta _saved;
  /// The words as last kept: a file added to an unchanged note keeps them as they were.
  late String _savedText = _current?.text ?? '';
  StreamSubscription<DocChange>? _changes;
  final _focus = FocusNode();
  final _editor = GlobalKey<QuillEditorState>();
  final _scroll = ScrollController();
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
  /// A voice note still writing its words, or one whose words failed: the page shows that until the words come.
  late bool _waiting = _wordsMissing(_current);
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

  /// The note whose words have the cursor: the iPhone's own *Paste* goes there.
  static NoteEditorState? _pasteTarget;

  Relay get relay => widget.relay;
  /// The note's own id, made here for a new note.
  String get id => _id;

  static bool _wordsMissing(Entry? entry) => entry != null && (entry.writing || entry.failed);

  /// The kept note has no file and no recording, so blank words leave nothing in it.
  bool get _bare {
    final note = _current;
    return note != null && note.files.isEmpty && note.recording == null && !note.voice;
  }

  /// The note as the list has it now, so words still being written fill in here too.
  Entry? get _current => _stored ? _live ?? widget.entry : null;

  /// The note in the list or in *Recently Deleted* now, or null when the phone no longer has it.
  Entry? get _live {
    final opened = widget.entry;
    return [...relay.entries, ...relay.deleted].where((other) => other.id == _id &&
      (_id.isNotEmpty || (other.at == opened?.at && other.voice == opened?.voice))).firstOrNull;
  }

  bool get _inTrash => _stored && relay.deleted.any((entry) => entry.id == _id);

  @override
  void initState() {
    super.initState();
    // The list as it is now: a voice note's words, or its going, can come between the tap that opens it and this.
    final entry = _current;
    _controller = QuillController(document: _documentOf(entry), selection: const TextSelection.collapsed(offset: 0),
      // The only way to take the editor's own paste; experimental, pinned by pubspec.lock.
      // ignore: experimental_member_use
      config: QuillControllerConfig(clipboardConfig: QuillClipboardConfig(onClipboardPaste: _clipboardPaste)));
    _controller.onReplaceText = _typed;
    _tables = NoteTables(_controller)..addListener(_tablesChanged);
    _listen();
    _trash = _controller.readOnly = _inTrash;
    _controller.addListener(_caretMoved);
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

  static Document _documentOf(Entry? entry) => Document.fromDelta(entry == null
    ? (Delta()..insert('\n', Attribute.h1.toJson()))
    : withLinks(markdownToDelta(entry.text, title: true)));

  void _listen() {
    _saved = _controller.document.toDelta();
    _changes?.cancel();
    _changes = _controller.document.changes.listen((_) => _changed());
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
    final delta = _controller.document.toDelta();
    final text = delta == _saved ? _savedText : _markdownOf(delta);
    return (id: _id, text: plainText(text).trim().isEmpty ? '' : text);
  }

  @override
  void dispose() {
    _tables.flush();
    _save(sendNow: true, leaving: true);
    if (relay.openNote == _id) relay.openNote = _heldBefore;
    if (relay.editorWords == _words) relay.editorWords = null;
    relay.removeListener(_relayChanged);
    if (_pasteTarget == this) _pasteTarget = null;
    _stopPastes();
    _changes?.cancel();
    _pause?.cancel();
    _controller.removeListener(_caretMoved);
    _tables.dispose();
    _focus.dispose();
    _find.dispose();
    _findFocus.dispose();
    _scroll.dispose();
    _controller.dispose();
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
    _typing = _editing;
    if (!_typing && mounted) _markLinks();
    if (mounted) setState(() {});
  }

  /// The person edits the note: its words or a table's cell have the cursor, or the Format sheet is open.
  bool get _editing => _focus.hasFocus || _formatting || _tables.active != null;

  /// A table's cell took the cursor, or gave it up: the page shows the keyboard's bar while a cell has it.
  void _tablesChanged() {
    _typing = _editing;
    if (_tables.active != null && _finding) _endFind();
    if (mounted) setState(() {});
  }

  /// A space typed after `#`, `-`, `[]` or another Markdown mark at a line's start gives the line that style, with
  /// the marks taken away, as the iPhone's keyboard types it. The space goes in first as typed, so one Undo gives the
  /// marks back. A paste never comes here: it is one change of its own.
  bool _typed(int index, int length, Object? data) {
    if (_marking || data != ' ' || length != 0 || index <= 0) return true;
    final words = _controller.document.toPlainText();
    if (index >= words.length || !isLineMark(words.substring(words.lastIndexOf('\n', index - 1) + 1, index))) return true;
    _marking = true;
    try {
      _controller.replaceText(index, 0, ' ', TextSelection.collapsed(offset: index + 1));
      final change = lineMarkChange(_controller.document, index);
      if (change != null) {
        _controller.document.history.lastRecorded = 0;
        final start = change.first.length ?? 0;
        _controller.compose(change, TextSelection.collapsed(offset: change.first.isRetain ? start : 0),
          ChangeSource.local);
      }
    } finally {
      _marking = false;
    }
    return false;
  }

  /// Words that came for a voice note fill the page, once. A kept note gone from the list closes the page.
  void _relayChanged() {
    if (_stored && !_deleted && _live == null) return _gone();
    // Deleted or recovered, here or on another device: the words lock or open.
    if (_inTrash != _trash) {
      setState(() => _trash = _controller.readOnly = _inTrash);
      if (_trash) _focus.unfocus();
    }
    final note = _current;
    if (!_waiting || note == null || note.writing || note.failed) return;
    _controller.document = _documentOf(note);
    _savedText = note.text;
    _listen();
    setState(() => _waiting = false);
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
    final delta = _controller.document.toDelta();
    final text = delta == _saved ? _savedText : _markdownOf(delta);
    // Blank words, such as only an empty Title line, are kept as none, so a note of files alone is not `#`.
    final empty = plainText(text).trim().isEmpty;
    final changed = delta != _saved || files.isNotEmpty;
    final dropping = leaving && empty && files.isEmpty && (_stored || _adds > 0);
    if (!changed && !dropping) {
      if (sendNow && _unsent) {
        _unsent = false;
        _writing = _writing.then((_) => relay.sync());
      }
      return;
    }
    if (!_stored && _adds == 0 && empty && files.isEmpty) return;
    _saved = delta;
    _savedText = text;
    if (!leaving) _markLinks();
    final unsent = _unsent;
    _unsent = !sendNow;
    final adding = !_stored;
    if (adding) _adds++;
    _writing = _writing.then((_) async {
      String? problem;
      if (_stored && empty && files.isEmpty && _bare) {
        final emptied = leaving ? await relay.dropEmptyNote(_id) : Emptied.kept;
        if (emptied != Emptied.kept) _stored = false;
      } else if (_stored && !changed) {
        // Left unchanged with blank words, yet a file or a recording keeps it: only what waits still goes.
        if (unsent) await relay.sync();
      } else if (_stored) {
        problem = await relay.editNote(_id, empty ? '' : text, files: files, sendNow: sendNow);
      } else if (!empty || files.isNotEmpty) {
        problem = await relay.addNote(empty ? '' : text, files: files, id: _id, sendNow: sendNow);
        // An add of only files the phone could not keep keeps nothing, so the next save adds the note again.
        _stored = relay.entries.any((entry) => entry.id == _id);
        if (mounted) setState(() {});
      }
      if (adding) _adds--;
      if (problem != null) await showProblemOn(_navigator, problem);
    });
  }

  /// The Markdown of [delta], with its link marks as [_markLinks] puts them, so an edited address that still has its
  /// old mark is written as its words.
  String _markdownOf(Delta delta) => deltaToMarkdown(withLinks(delta));

  /// Marks the links in the shown note again, as [withLinks] does when the note opens, so an address typed in this
  /// visit opens too, and an edited one opens what its words now say. The marks change no stored words: the Markdown
  /// codec writes an address with its own link as the bare address. A note kept as it is stays kept, so the marks
  /// alone never write it back.
  void _markLinks() {
    final before = _controller.document.toDelta();
    if (withLinks(before) == before) return;
    // The marks change no words, so the editor must not bring the keyboard back for them.
    _controller.ignoreFocusOnTextChange = true;
    for (final (start, length, link) in linkFixes(_controller.document)) {
      _controller.formatText(start, length, LinkAttribute(link));
    }
    _controller.ignoreFocusOnTextChange = false;
    if (before == _saved) _saved = _controller.document.toDelta();
  }

  /// The iPhone's own *Paste*: true when the note with the cursor put the words in.
  static Future<Object?> _pasteCall(MethodCall call) async {
    if (call.method != 'paste') throw MissingPluginException();
    final words = call.arguments is Map ? call.arguments as Map : const {};
    final target = _pasteTarget;
    if (target == null || !target.mounted || !target._focus.hasFocus) return false;
    return target._paste(html: words['html'] as String?, plain: words['plain'] as String? ?? '');
  }

  /// The editor's own paste, from its drawn menu or a keyboard's paste keys: the clipboard's HTML and plain words go
  /// through [_paste]. It always answers true, so the editor never pastes the page's colours and sizes itself.
  Future<bool> _clipboardPaste() async {
    // ignore: experimental_member_use
    final clipboard = ClipboardServiceProvider.instance;
    String? html;
    try {
      html = await clipboard.getHtmlText() ?? await clipboard.getHtmlFile();
    } on Exception {
      html = null;
    }
    final plain = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (mounted) _paste(html: html, plain: plain);
    return true;
  }

  /// Puts a paste at the cursor in one change, so one *Undo* takes it back. A copy from inside the note pastes back with
  /// its styles; anything else keeps only the styles the note can store ([pastedDelta]). Addresses in it show as links,
  /// as [withLinks] marks them. True when the paste is handled, even with no words.
  bool _paste({String? html, required String plain}) {
    final selection = _controller.selection;
    if (!selection.isValid) return false;
    final copied = _controller.pasteDelta;
    final ({Delta change, int caret})? paste;
    if (plain.isNotEmpty && plain == _controller.pastePlainText && copied.isNotEmpty) {
      final change = Delta();
      if (selection.start > 0) change.retain(selection.start);
      if (!selection.isCollapsed) change.delete(selection.end - selection.start);
      // A copied table pastes as a table of its own, so a change in one never goes into the other.
      for (final op in copied.toList()) {
        change.push(withNewTableId(op));
      }
      paste = (change: change, caret: selection.start + copied.toList().fold(0, (sum, op) => sum + (op.length ?? 0)));
    } else {
      final pasted = pastedDelta(html: html, plain: plain);
      paste = pasteChange(_controller.document, selection, pasted.isEmpty ? pasted : withLinks(pasted));
    }
    if (paste == null) return true;
    _controller.compose(paste.change, TextSelection.collapsed(offset: paste.caret), ChangeSource.local);
    _controller.updateSelection(TextSelection.collapsed(offset: paste.caret), ChangeSource.local);
    _revealCaret();
    return true;
  }

  void _say(String message) => unawaited(showProblemOn(_navigator, message));

  void _done() {
    // A table's cell gives up the cursor too.
    if (_tables.active != null) FocusManager.instance.primaryFocus?.unfocus();
    _tables.leave();
    setState(() => _formatting = _typing = false);
    _focus.unfocus();
    _save(sendNow: true);
  }

  /// *Aa*: the keyboard goes down the normal way and the panel takes its place. Hiding the keyboard while the editor
  /// keeps the cursor makes the editor bring it back at once, so the two fight. The editor also asks for the keyboard
  /// when it loses the cursor while waiting to redraw, so that one request is skipped.
  void _styles() {
    setState(() => _formatting = true);
    _controller.skipRequestKeyboard = true;
    _focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.skipRequestKeyboard = false);
  }

  void _closeStyles() => _focus.requestFocus();

  /// *Undo* and *Redo* change the words as typing does, so the save on a pause keeps them; the keyboard stays up.
  Widget _history() => ListenableBuilder(listenable: _controller, builder: (context, _) {
    if (!_controller.hasUndo && !_controller.hasRedo) return const SizedBox.shrink();
    // A cell's words still waiting go in first, so Undo takes back the last change.
    void undo() {
      _tables.flush();
      _controller.undo();
    }
    void redo() {
      _tables.flush();
      _controller.redo();
    }
    return Padding(padding: const EdgeInsets.only(right: 8), child: _controller.hasRedo
      ? ButtonPill(children: [
          PillIconButton(icon: CupertinoIcons.arrow_uturn_left, tooltip: 'Undo', onPressed: _controller.hasUndo ? undo : null),
          PillIconButton(icon: CupertinoIcons.arrow_uturn_right, tooltip: 'Redo', onPressed: redo),
        ])
      : RoundIconButton(icon: CupertinoIcons.arrow_uturn_left, tooltip: 'Undo', onPressed: _controller.hasUndo ? undo : null));
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
    final matches = words.isEmpty ? <TextRange>[] : [
      for (final match in pattern.allMatches(_controller.document.toPlainText()))
        TextRange(start: match.start, end: match.end),
      for (final (offset, table) in tablesIn(_controller.document.toDelta()))
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

  /// Selects a match as a mark on the page, not a change: the editor must not take the keyboard back for it.
  void _select(TextRange match) {
    _controller.ignoreFocusOnTextChange = true;
    _controller.updateSelection(TextSelection(baseOffset: match.start, extentOffset: match.end), ChangeSource.silent);
    _controller.ignoreFocusOnTextChange = false;
    _revealCaret();
  }

  /// While editing or finding, each move of the caret scrolls the page so the caret shows above the floating bar.
  void _caretMoved() {
    if (_focus.hasFocus || _finding) _revealCaret();
  }

  /// Scrolls the page, after the frame, so the caret's line shows under the top edge and above the bar. The editor
  /// scrolls the caret only to the page's bottom edge, under the bar: this runs after its own scroll in the same frame,
  /// or stops it, as a jump ends a scroll that is still moving. The editor's `scrollBottomInset` would keep the bar's
  /// room over the caret too, so a caret that moves up would go under the top edge.
  void _revealCaret() {
    if (_revealing) return;
    _revealing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealing = false;
      final editor = _editor.currentState?.editableTextKey.currentState?.renderEditor;
      final selection = _controller.selection;
      if (!mounted || editor == null || !editor.attached || !_scroll.hasClients || !selection.isValid) return;
      final caret = editor.getLocalRectForCaret(selection.extent);
      final position = _scroll.position;
      final top = editor.localToGlobal(Offset.zero, ancestor: RenderAbstractViewport.of(editor)).dy + position.pixels;
      final above = top + caret.top - _caretTopRoom, below = top + caret.bottom + barRoom;
      final to = above < position.pixels ? above
        : below > position.pixels + position.viewportDimension ? below - position.viewportDimension : null;
      if (to != null) _scroll.jumpTo(to.clamp(position.minScrollExtent, position.maxScrollExtent));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// ✓ on the find bar: the match stays as the caret, with the keyboard down.
  void _closeFind() {
    final end = _controller.selection.end;
    _endFind();
    _controller.ignoreFocusOnTextChange = true;
    _controller.updateSelection(TextSelection.collapsed(offset: end), ChangeSource.silent);
    _controller.ignoreFocusOnTextChange = false;
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
      final end = _controller.document.length - 1;
      final words = _controller.document.toPlainText();
      final emptyLast = words == '\n' || words.endsWith('\n\n');
      _controller.replaceText(end, 0, emptyLast ? '' : '\n', TextSelection.collapsed(offset: emptyLast ? end : end + 1));
      _focus.requestFocus();
    }
    final list = _controller.getSelectionStyle().attributes[Attribute.list.key]?.value;
    _controller.formatSelection(list == 'checked' || list == 'unchecked' ? Attribute.clone(Attribute.list, null) : Attribute.unchecked);
  }

  /// *Attach* → *Photos* or *Files*. The browser has one picker for every kind of file.
  Future<void> _attach({required bool photos}) async {
    final List<NewFile> picked;
    try {
      picked = await (widget.picker ?? pickWithPhone)(photos: photos);
    } on Exception {
      return _say('The ${relay.web ? 'browser' : relay.desktop ? 'Mac' : 'phone'} did not give the file. Try again.');
    }
    if (mounted && picked.isNotEmpty) _save(sendNow: !_focus.hasFocus, files: picked);
  }

  String get _plain => plainText(deltaToMarkdown(_controller.document.toDelta()));

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
    _save(sendNow: true, files: files);
  }

  /// A format item from the computer's keys, its *Text styles* menu or right-click menu, or the Mac's *Format* menu: on
  /// the words picked or the cursor's line, as Notes does. A table's cell holds plain words, so only *Table* acts
  /// there.
  void format(FormatAction action) {
    if (_waiting || _trash) return;
    if (action == FormatAction.table) return _addTable();
    if (_tables.active != null) return;
    if (action == FormatAction.link) return unawaited(_linkBox());
    Formatter(_controller, keyboardDown: _formatting).run(action, colour: relay.settings.highlightColour);
  }

  /// *Table*: a table of 2 columns and 2 rows at the cursor, with the cursor in its first cell.
  void _addTable() {
    if (_waiting || _trash) return;
    _typing = true;
    _tables.insert();
  }

  /// *Table* → *Convert to text* or *Delete table*: the cursor goes where the table was.
  void _tableGone(int? at) {
    if (at == null || !mounted) return;
    _controller.updateSelection(TextSelection.collapsed(offset: at), ChangeSource.local);
    _focus.requestFocus();
  }

  /// *Link*: a box for the address of the words picked, filled from a copied web address. On a link it changes the
  /// address or takes the link away. With no words picked, the address goes in as its own words.
  Future<void> _linkBox() async {
    final selection = _controller.selection;
    if (_waiting || _trash || _tables.active != null || !selection.isValid) return;
    final now = _controller.getSelectionStyle().attributes[Attribute.link.key]?.value as String?;
    final run = now == null ? null : linkRunAt(_controller.document, selection.start);
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
    if (answer.trim().isEmpty) {
      if (run != null) _controller.formatText(run.start, run.end - run.start, const LinkAttribute(null));
      return;
    }
    final address = linkAddressOf(answer);
    if (address == null) return _say('That is not a web address. Try again.');
    if (run != null && selection.isCollapsed) {
      _controller.formatText(run.start, run.end - run.start, LinkAttribute(address));
    } else if (selection.isCollapsed) {
      _controller.replaceText(selection.start, 0, address, TextSelection.collapsed(offset: selection.start + address.length));
      _controller.formatText(selection.start, address.length, LinkAttribute(address));
    } else {
      _controller.formatText(selection.start, selection.end - selection.start, LinkAttribute(address));
    }
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

  /// A tap on a link while reading opens it, and the keyboard stays down. While editing, as in Apple Notes, a tap on
  /// the cursor opens or closes the text menu; any other tap returns false, so the editor places the cursor.
  bool _tapUp(TapUpDetails details, TextPosition Function(Offset) positionOf) {
    if (_trash) {
      unawaited(_askRecover());
      return true;
    }
    if (isOnTable(context, details.globalPosition)) return true;
    final at = positionOf(details.globalPosition);
    if (_focus.hasFocus || _formatting) return !_formatting && _toggleMenu(at);
    final link = linkAtPosition(_controller.document, at);
    if (link == null) return false;
    _openLink(link);
    return true;
  }

  /// The browser draws its own menu, so a tap there always places the cursor. The iPhone closes its menu at the touch
  /// down of a tap outside it, so a tap on the cursor just after that opens nothing: the tap closed the menu.
  bool _toggleMenu(TextPosition at) {
    final selection = _controller.selection;
    final editor = _editor.currentState?.editableTextKey.currentState;
    if (relay.desktop || editor == null || !selection.isCollapsed || at.offset != selection.baseOffset) return false;
    if (editor.selectionOverlay?.toolbar != null) {
      editor.hideToolbar();
    } else if (!QuillSystemMenu.closedJustNow(editor)) {
      editor.showToolbar();
    }
    return true;
  }

  Future<void> _openLink(String link) async {
    // A mail link or another with its own scheme opens as it is; `www.…` opens on the web.
    final address = Uri.tryParse(_scheme.hasMatch(link) ? link : 'https://$link');
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

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final editing = _editing;
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
          if (!widget.pane && !_waiting && !_formatting && !_trash) Positioned(left: 16, right: 16, bottom: 0, child: SafeArea(
            top: false,
            minimum: EdgeInsets.only(bottom: editing || _finding ? 6 : 12),
            child: _finding
              ? FindBar(controller: _find, focus: _findFocus, onChanged: _findChanged, onDone: _closeFind,
                  found: _find.text.isEmpty ? null : _matches.isEmpty ? 'No matches' : '${_match + 1} of ${_matches.length}',
                  onStep: _matches.isEmpty ? null : _step)
              : editing
              ? _keyboardBar()
              : ReadingBar(onChecklist: _checklist, onAttach: _attachOrNull, onCompose: _compose, attachMenu: !relay.desktop),
          )),
        ])),
        if (!widget.pane && _formatting) FormatSheet(controller: _controller, height: _keyboard, onClose: _closeStyles,
          colour: relay.settings.highlightColour, onColour: relay.setHighlightColour),
      ])),
    );
  }

  /// Over the keyboard: the style tools while words are picked, else the scrolling tool bar. In a table's cell only
  /// *Table*, *Attach* and *Hide keyboard* act: a cell holds plain words.
  Widget _keyboardBar() => ListenableBuilder(listenable: _controller, builder: (context, _) {
    if (_focus.hasFocus && !_controller.selection.isCollapsed) {
      return SelectionToolBar(controller: _controller, colour: relay.settings.highlightColour,
        onLink: () => unawaited(_linkBox()));
    }
    final words = _tables.active == null;
    return FloatingToolBar(
      onStyles: words ? _styles : null,
      onChecklist: words ? _checklist : null,
      table: _tableButton(),
      onAttach: _attachOrNull,
      attachMenu: !relay.desktop,
      onList: words ? Formatter(_controller).listOf : null,
      onLink: words ? () => unawaited(_linkBox()) : null,
      onIndent: words ? Formatter(_controller).indent : null,
      onHideKeyboard: _done,
    );
  });

  Widget _tableButton() => TableButton(onAdd: _waiting || _trash ? null : _addTable, inTable: _tables.active != null,
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
          FormatMenu(controller: _controller, onPick: _pick, colour: relay.settings.highlightColour,
            onColour: relay.setHighlightColour, enabled: !_waiting && !_trash && _tables.active == null),
          PillIconButton(icon: CupertinoIcons.checkmark_circle, tooltip: 'Checklist',
            onPressed: _waiting || _trash || _tables.active != null ? null : _checklist),
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
      if (!relay.web && !_waiting) ('Find in Note', CupertinoIcons.search, _openFind),
      ('Copy', CupertinoIcons.doc_on_doc, _copy),
    ],
    destructive: ('Delete', CupertinoIcons.trash, _delete),
    builder: (context, toggle) => PillIconButton(icon: CupertinoIcons.ellipsis, tooltip: 'More', onPressed: toggle),
  ));

  Widget _page(BuildContext context, BrandColors brand) {
    final note = _current;
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    final recording = note?.recording;
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The date alone: nothing about sending, and no tag.
        Text(_when(context, note?.at ?? DateTime.now(), note?.from), style: muted, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        if (recording != null) Padding(padding: const EdgeInsets.only(bottom: 14),
          child: VoicePlayer(relay: relay, recording: recording, length: note?.length)),
        // Words typed with a recording, such as a shortcut's label, show while its own words are written.
        if (note != null && note.text.isNotEmpty && (note.writing || note.failed)) ...[
          Text(plainText(note.text), style: const TextStyle(fontFamily: brandFont, fontSize: 17, height: 1.5)),
          const SizedBox(height: 14),
        ],
        if (note != null && note.writing) ...[
          Text('Writing the words…', style: TextStyle(color: brand.muted)),
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ] else if (note != null && note.failed) ...[
          Text('The words did not come. Your recording is safe.', style: TextStyle(color: brand.muted)),
          // The reason, small and muted: the person sees it only on a note that failed.
          if (note.why != null) ...[
            const SizedBox(height: 4),
            Text('Why: ${note.why}', style: muted),
          ],
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft,
            child: FilledButton(onPressed: relay.writeWordsAgain, child: const Text('Try again'))),
        ] else
          QuillEditor(
            key: _editor,
            controller: _controller,
            focusNode: _focus,
            scrollController: _scroll,
            config: QuillEditorConfig(
              scrollable: false,
              autoFocus: widget.entry == null,
              placeholder: recording != null ? 'No words, only the recording.' : 'What do you want to keep?',
              customStyles: noteStyles(context),
              // The format keys only on a computer: a phone's keyboard has no ⌘.
              customShortcuts: relay.desktop ? {...formatShortcuts(), ...pageKeys} : null,
              customActions: relay.desktop
                ? {FormatIntent: CallbackAction<FormatIntent>(onInvoke: (intent) => format(intent.action))}
                : null,
              embedBuilders: [TableEmbedBuilder(_tables)],
              onTapUp: _tapUp,
              contextMenuBuilder: (context, editor) => noteContextMenu(context, editor,
                format: relay.desktop ? _pick : null),
              quillMagnifierBuilder: relay.desktop ? null : noteMagnifier,
              // A long press on a link offers Open; it goes to the same browser.
              onLaunchUrl: _openLink,
              // The only way to draw Apple's round checklist circles and dashed lists; pinned by pubspec.lock.
              // ignore: experimental_member_use
              customLeadingBlockBuilder: (_, config) => _leading(config, brand),
            ),
          ),
        for (final file in note?.files ?? const <EntryFile>[])
          Padding(padding: const EdgeInsets.only(top: 14),
            child: file.picture && file.ready ? NotePicture(file: file, relay: relay) : NoteFileRow(file: file, relay: relay)),
      ]),
    );
  }

  /// A dash for a dashed list, and a round circle for a checklist line that one tap ticks in the accent.
  Widget? _leading(LeadingConfig config, BrandColors brand) {
    final kind = config.attribute.value;
    if (kind == dashedList) {
      return SizedBox(width: 34, child: Text('–', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: brand.ink)));
    }
    if (kind != 'checked' && kind != 'unchecked') return null;
    final ticked = config.value;
    return SizedBox(width: 34, child: Semantics(
      checked: ticked,
      label: ticked ? 'Ticked' : 'Not ticked',
      child: InkResponse(
        onTap: config.enabled == false ? null : () => config.onCheckboxTap(!ticked),
        radius: 18,
        child: Icon(ticked ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, size: 24,
          color: ticked ? brand.accent : brand.muted),
      ),
    ));
  }
}

/// The note's text styles, as Apple Notes draws them: Title, Heading and Subheading larger and bold, Body at 17.
DefaultStyles noteStyles(BuildContext context) {
  final brand = brandOf(context);
  final ink = brand.ink;
  DefaultTextBlockStyle block(double size, FontWeight weight, double top) => DefaultTextBlockStyle(
    TextStyle(fontFamily: brandFont, fontSize: size, fontWeight: weight, height: 1.3, color: ink), HorizontalSpacing.zero,
    VerticalSpacing(top, 4), VerticalSpacing.zero, null);
  return DefaultStyles(
    h1: block(28, FontWeight.w700, 4),
    h2: block(22, FontWeight.w700, 10),
    h3: block(19, FontWeight.w600, 8),
    paragraph: DefaultTextBlockStyle(TextStyle(fontFamily: brandFont, fontSize: 17, height: 1.5, color: ink), HorizontalSpacing.zero,
      VerticalSpacing.zero, VerticalSpacing.zero, null),
    link: TextStyle(color: brand.accentText, decoration: TextDecoration.underline, decorationColor: brand.accentText),
    // A highlight's colour by its name, as the note keeps it: soft enough to read the words through.
    palette: {for (final colour in highlightColours) colour: highlightColourOf(colour, Theme.of(context).brightness)},
  );
}

/// A web address in a note's words: `https://…`, `http://…` or `www.…`, up to a space, less the stop or bracket that
/// ends a sentence.
final _webAddress = RegExp(r'(?:https?://|www\.)[^\s<>"]+', caseSensitive: false);
final _endPunctuation = RegExp(r'''[.,;:!?)\]}'"]+$''');

/// [delta] with each web address in its words marked as a link, for the page to show, as [linkFixes] marks them. The
/// Markdown codec writes an address linked to itself as the bare address, so the stored words never change, and an
/// old note is never sent again.
Delta withLinks(Delta delta) {
  final document = Document.fromDelta(delta);
  for (final (start, length, link) in linkFixes(document)) {
    document.format(start, length, LinkAttribute(link));
  }
  return document.toDelta();
}

/// The link marks that make [document] show its links: each link on words that hold no web address and are no piece
/// of the link stays, as `[the menu](…)` does; each other mark goes, as the editor's own marks can take a stop at an
/// address's end, and an edited address keeps the mark of what it was; then each web address in the words is marked
/// as itself.
List<(int, int, String?)> linkFixes(Document document) {
  final runs = <(int, int, String)>[];
  var offset = 0;
  for (final op in document.toDelta().toList()) {
    final length = op.length ?? 0;
    final link = op.attributes?[Attribute.link.key];
    if (link is String && op.data is String) {
      final last = runs.lastOrNull;
      if (last != null && last.$3 == link && last.$1 + last.$2 == offset) {
        runs.last = (last.$1, last.$2 + length, link);
      } else {
        runs.add((offset, length, link));
      }
    }
    offset += length;
  }
  final words = document.toPlainText();
  bool keeps((int, int, String) run) {
    final linked = words.substring(run.$1, run.$1 + run.$2).trim().toLowerCase();
    // Words that are a piece of their own link were an address: `example.com` left from `https://example.com`. Only
    // words with a `.` or a `/` can be such a piece, so *menu* linked to `https://example.com/menu` stays a link.
    final address = run.$3.toLowerCase().replaceFirst(_scheme, '').replaceFirst(RegExp('^//'), '');
    final piece = linked.isEmpty || (linked.contains(RegExp('[./]')) && address.contains(linked));
    return linkRanges(linked).isEmpty && !piece;
  }
  final kept = [for (final run in runs) if (keeps(run)) run];
  return [
    for (final run in runs) if (!kept.contains(run)) (run.$1, run.$2, null),
    for (final range in linkRanges(words))
      if (!kept.any((run) => range.start < run.$1 + run.$2 && run.$1 < range.start + range.address.length))
        (range.start, range.address.length, range.address),
  ];
}

/// Where the link at [offset] in [document] starts and ends: the run of words with the same link.
TextRange? linkRunAt(Document document, int offset) {
  final link = linkAt(document, offset) ?? linkAt(document, offset - 1);
  if (link == null) return null;
  var start = offset, end = offset;
  while (start > 0 && linkAt(document, start - 1) == link) {
    start--;
  }
  while (linkAt(document, end) == link) {
    end++;
  }
  return TextRange(start: start, end: end);
}

/// The address a person typed in the *Link* box, as the link keeps it: `example.com` gains `https://`, and an address
/// with its own scheme, such as `mailto:`, stays. Null for words that are no address.
String? linkAddressOf(String typed) {
  final words = typed.trim();
  if (words.isEmpty || words.contains(RegExp(r'\s'))) return null;
  if (_scheme.hasMatch(words)) return words;
  return words.contains('.') ? 'https://$words' : null;
}

/// A link's own scheme, such as `https:` or `mailto:`; `www.` has none.
final _scheme = RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false);

/// Each web address in [words], with where it starts.
Iterable<({int start, String address})> linkRanges(String words) sync* {
  for (final match in _webAddress.allMatches(words)) {
    final address = match[0]!.replaceFirst(_endPunctuation, '');
    if (address.contains('.') && !address.endsWith('://')) yield (start: match.start, address: address);
  }
}

/// The link on the letter at [offset] in [document], or null. A tap in the space after a line's end gives that line's
/// end, which is no link, so it places the cursor.
String? linkAt(Document document, int offset) => offset < 0 || offset >= document.length - 1 ? null
  : document.collectStyle(offset, 1).attributes[Attribute.link.key]?.value as String?;

/// The link under a tap at [position], or null. A tap on a letter's right half gives the place after that letter,
/// upstream, so the letter before it is the one tapped: the link's last letter opens it, and the space before a link
/// does not.
String? linkAtPosition(Document document, TextPosition position) =>
  linkAt(document, position.affinity == TextAffinity.upstream ? position.offset - 1 : position.offset);
