import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:share_plus/share_plus.dart';

import '../brand.dart';
import '../data/client_id.dart';
import '../editor/magnifier.dart';
import '../editor/markdown.dart';
import '../editor/system_menu.dart';
import '../relay.dart';
import 'back_to.dart';
import 'days.dart';
import 'folder.dart' show Opener, openInBrowser;
import 'more_menu.dart';
import 'note_bars.dart';
import 'note_blocks.dart';
import 'round_button.dart';
import 'timeline.dart' show showDeleted;

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
  late Delta _saved;
  /// The words as last kept: a file added to an unchanged note keeps them as they were.
  late String _savedText = _current?.text ?? '';
  StreamSubscription<DocChange>? _changes;
  final _focus = FocusNode();
  final _editor = GlobalKey<QuillEditorState>();
  final _scroll = ScrollController();
  Timer? _pause;
  Future<void> _writing = Future.value();
  ScaffoldMessengerState? _messenger;
  /// Kept with no send yet, as typing saves: leaving sends it.
  bool _unsent = false;
  /// Set by ⋯ → *Delete*: no save runs after it, so leaving keeps nothing.
  bool _deleted = false;
  /// A voice note still writing its words, or one whose words failed: the page shows that until the words come.
  late bool _waiting = _wordsMissing(_current);
  bool _formatting = false;
  /// Set with the keyboard, or at once when a button brings it up, so the edit that comes first waits for a pause.
  late bool _typing = widget.entry == null;
  double _keyboard = 300;
  /// The note held open before this page, such as the note page a voice note from Shortcuts opens over: leaving gives
  /// the hold back to it, so a pull does not change that note's words under its page.
  String? _heldBefore;

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

  /// The note in the list now, or null when the phone no longer has it.
  Entry? get _live {
    final opened = widget.entry;
    return relay.entries.where((other) => other.id == _id &&
      (_id.isNotEmpty || (other.at == opened?.at && other.voice == opened?.voice))).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    // The list as it is now: a voice note's words, or its going, can come between the tap that opens it and this.
    final entry = _current;
    _controller = QuillController(document: _documentOf(entry), selection: const TextSelection.collapsed(offset: 0));
    _listen();
    _focus.addListener(_focusChanged);
    relay.addListener(_relayChanged);
    // The browser's layout holds one note at a time: the note before has closed, so nothing gets the hold back.
    _heldBefore = widget.onClose == null ? relay.openNote : null;
    relay.openNote = _id;
    relay.editorWords = _words;
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
    _messenger = ScaffoldMessenger.maybeOf(context);
    _measureKeyboard(MediaQuery.viewInsetsOf(context).bottom);
  }

  /// The Format panel takes the keyboard's height. Only a keyboard up for the cursor counts: while it slides down for
  /// the panel, each frame's height is part of the way.
  void _measureKeyboard(double inset) {
    if (_focus.hasFocus && inset > 100) _keyboard = inset;
  }

  /// The words as they are now: the same as kept, or new ones not yet kept.
  ({String id, String text})? _words() {
    if (_deleted) return null;
    final delta = _controller.document.toDelta();
    final text = delta == _saved ? _savedText : deltaToMarkdown(delta);
    return (id: _id, text: plainText(text).trim().isEmpty ? '' : text);
  }

  @override
  void dispose() {
    _save(sendNow: true, leaving: true);
    if (relay.openNote == _id) relay.openNote = _heldBefore;
    if (relay.editorWords == _words) relay.editorWords = null;
    relay.removeListener(_relayChanged);
    _changes?.cancel();
    _pause?.cancel();
    _focus.dispose();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// The format panel lets go of the cursor, but the person is still editing; the cursor coming back closes it. When
  /// editing ends, an address typed meanwhile becomes a link.
  void _focusChanged() {
    if (_focus.hasFocus) _formatting = false;
    _typing = _focus.hasFocus || _formatting;
    if (!_typing && mounted) _markLinks();
    if (mounted) setState(() {});
  }

  /// Words that came for a voice note fill the page, once. A kept note gone from the list closes the page.
  void _relayChanged() {
    if (_stored && !_deleted && _live == null) return _gone();
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
    if (_deleted) return;
    final delta = _controller.document.toDelta();
    final text = delta == _saved ? _savedText : deltaToMarkdown(delta);
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
        if (emptied == Emptied.deleting) showDeleted(_messenger, relay, _id);
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
      if (problem != null) _messenger?.showSnackBar(SnackBar(content: Text(problem)));
    });
  }

  /// Marks the links in the shown note again, as [withLinks] does when the note opens, so an address typed in this
  /// visit opens too, and an edited one opens what its words now say. The marks change no stored words, because the
  /// Markdown codec writes no link. A note kept as it is stays kept, so the marks alone never write it back.
  void _markLinks() {
    final before = _controller.document.toDelta();
    if (withLinks(before) == before) return;
    // The marks change no words, so the editor must not bring the keyboard back for them.
    _controller.ignoreFocusOnTextChange = true;
    _controller.formatText(0, _controller.document.length - 1, const LinkAttribute(null));
    for (final range in linkRanges(_controller.document.toPlainText())) {
      _controller.formatText(range.start, range.address.length, LinkAttribute(range.address));
    }
    _controller.ignoreFocusOnTextChange = false;
    if (before == _saved) _saved = _controller.document.toDelta();
  }

  void _say(String message) => _messenger?.showSnackBar(SnackBar(content: Text(message)));

  void _done() {
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

  Future<void> _attach() async {
    // The browser has one picker for every kind of file.
    final photos = relay.web ? false : await showModalBottomSheet<bool>(context: context, builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(CupertinoIcons.photo), title: const Text('Photos'), onTap: () => Navigator.pop(context, true)),
        ListTile(leading: const Icon(CupertinoIcons.doc), title: const Text('Files'), onTap: () => Navigator.pop(context, false)),
      ]),
    ));
    if (photos == null) return;
    final List<NewFile> picked;
    try {
      picked = await (widget.picker ?? pickWithPhone)(photos: photos);
    } on Exception {
      return _say(relay.web ? 'The browser did not give the file. Try again.' : 'The phone did not give the file. Try again.');
    }
    if (mounted && picked.isNotEmpty) _save(sendNow: !_focus.hasFocus, files: picked);
  }

  String get _plain => plainText(deltaToMarkdown(_controller.document.toDelta()));

  Future<void> _share() => (widget.sharer ?? shareWithPhone)(_plain);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _plain));
    _say('Copied');
  }

  /// ⋯ → *Delete*: the page closes, and the note goes after any save still running, with *Undo* on the list. A new
  /// note not kept yet keeps nothing.
  void _delete() {
    _pause?.cancel();
    _deleted = true;
    final messenger = _messenger;
    _writing = _writing.then((_) async {
      if (!_stored) return;
      await relay.deleteNote(_id);
      showDeleted(messenger, relay, _id);
    });
    _leave();
  }

  /// ⋯ → *Delete*, or the browser's delete key: the note goes, with *Undo*.
  void delete() => _delete();

  void _leave() {
    if (widget.onClose case final close?) return close();
    Navigator.of(context).maybePop();
  }

  /// Files dropped on the note in the browser: they join it as the paperclip's do. A note from elsewhere takes none.
  void addFiles(List<NewFile> files) {
    if (files.isEmpty) return;
    if (_attachOrNull == null) return _say('You can add files only to a note you wrote here or on your phone.');
    _save(sendNow: true, files: files);
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
    if (relay.web || editor == null || !selection.isCollapsed || at.offset != selection.baseOffset) return false;
    if (editor.selectionOverlay?.toolbar != null) {
      editor.hideToolbar();
    } else if (!QuillSystemMenu.closedJustNow(editor)) {
      editor.showToolbar();
    }
    return true;
  }

  Future<void> _openLink(String link) async {
    final address = Uri.tryParse(link.contains('://') ? link : 'https://$link');
    if (address == null || !await (widget.opener ?? openInBrowser)(address)) _say('The browser did not open. Try again.');
  }

  /// *Yesterday at 18:05*, and *From Email* for a note from elsewhere.
  String _when(BuildContext context, DateTime at, String? from) {
    final days = daysAgo(at, DateTime.now());
    final day = days <= 0 ? 'Today' : days == 1 ? 'Yesterday' : MaterialLocalizations.of(context).formatMediumDate(at);
    return ['$day at ${TimeOfDay.fromDateTime(at).format(context)}', if (from != null) 'From $from']
      .whereType<String>().join(' · ');
  }

  /// The server takes new files only from the phone that made the note, so a note from elsewhere offers none.
  VoidCallback? get _attachOrNull => _current?.from == null ? _attach : null;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final editing = _focus.hasFocus || _formatting;
    _measureKeyboard(MediaQuery.viewInsetsOf(context).bottom);
    return Scaffold(
      appBar: widget.pane ? _paneBar(brand) : AppBar(leading: BackTo(widget.back, onPressed: widget.onClose),
        leadingWidth: BackTo.widthOf(widget.back), actions: [
        ButtonPill(children: [
          PillIconButton(icon: CupertinoIcons.square_arrow_up, tooltip: 'Share', onPressed: _share),
          _more(),
        ]),
        if (editing) Padding(padding: const EdgeInsets.only(left: 8),
          child: RoundIconButton(icon: CupertinoIcons.checkmark_alt, tooltip: 'Done', onPressed: _done, accent: true)),
        const SizedBox(width: 12),
      ]),
      body: Column(children: [
        if (widget.pane && _formatting) FormatSheet(controller: _controller, height: 200, onClose: _closePaneStyles),
        Expanded(child: Stack(children: [
          Positioned.fill(child: ListenableBuilder(listenable: relay, builder: (context, _) => widget.pane
            ? Align(alignment: Alignment.topCenter,
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: _page(context, brand)))
            : _page(context, brand))),
          if (!widget.pane && !_waiting && !_formatting) Positioned(left: 16, right: 16, bottom: editing ? 8 : 0, child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 12),
            child: editing
              ? Center(child: FloatingToolBar(onStyles: _styles, onChecklist: _checklist, onAttach: _attachOrNull))
              : ReadingBar(onChecklist: _checklist, onAttach: _attachOrNull, onCompose: _compose),
          )),
        ])),
        if (!widget.pane && _formatting) FormatSheet(controller: _controller, height: _keyboard, onClose: _closeStyles),
      ]),
    );
  }

  /// *Aa* in the wide layout: the styles open under the top bar, and the cursor stays in the words.
  void _paneStyles() => setState(() => _formatting = !_formatting);

  void _closePaneStyles() {
    setState(() => _formatting = false);
    _focus.requestFocus();
  }

  /// The wide layout's one bar: *New note*, then *Aa*, *Checklist* and *Attach*, then *Share* and ⋯, then search.
  PreferredSizeWidget _paneBar(BrandColors brand) => PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(spacing: 10, children: [
        ButtonPill(children: [PillIconButton(icon: CupertinoIcons.square_pencil, tooltip: 'New note', onPressed: _compose)]),
        ButtonPill(children: [
          PillIconButton(icon: CupertinoIcons.textformat, tooltip: 'Text styles', onPressed: _waiting ? null : _paneStyles),
          PillIconButton(icon: CupertinoIcons.checkmark_circle, tooltip: 'Checklist', onPressed: _waiting ? null : _checklist),
          PillIconButton(icon: CupertinoIcons.paperclip, tooltip: 'Attach', onPressed: _attachOrNull),
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

  Widget _more() => MoreMenu(
    items: [
      ('Copy', CupertinoIcons.doc_on_doc, _copy),
      if (_current?.recording case final recording?) ('Play', CupertinoIcons.play_fill, () => relay.play(recording)),
    ],
    destructive: ('Delete', CupertinoIcons.trash, _delete),
    builder: (context, toggle) => PillIconButton(icon: CupertinoIcons.ellipsis, tooltip: 'More', onPressed: toggle),
  );

  Widget _page(BuildContext context, BrandColors brand) {
    final note = _current;
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    final recording = note?.recording;
    final state = note == null ? null : sendState(note);
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_when(context, note?.at ?? DateTime.now(), note?.from), style: muted, textAlign: TextAlign.center),
        const SizedBox(height: 14),
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
              customShortcuts: relay.web ? pageKeys : null,
              onTapUp: _tapUp,
              contextMenuBuilder: noteContextMenu,
              quillMagnifierBuilder: relay.web ? null : noteMagnifier,
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
        if (recording != null) Padding(padding: const EdgeInsets.only(top: 14),
          child: PlayRow(length: note?.length, onPlay: () => relay.play(recording))),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 14), child: Row(spacing: 8, children: [
          BrandTag(note.voice ? 'Voice' : 'Typed', spark: note.voice, large: true),
          if (note.waiting && !note.sent)
            _SendNow(relay: relay)
          else if (state != null)
            Text(state, style: muted),
        ])),
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
  );
}

/// A web address in a note's words: `https://…`, `http://…` or `www.…`, up to a space, less the stop or bracket that
/// ends a sentence.
final _webAddress = RegExp(r'(?:https?://|www\.)[^\s<>"]+', caseSensitive: false);
final _endPunctuation = RegExp(r'''[.,;:!?)\]}'"]+$''');

/// [delta] with each web address in its words marked as a link, for the page to show. Only the shown note gets the
/// marks: the Markdown codec writes no link, so the stored words never change, and an old note is never sent again.
/// Each old mark goes first: the editor's own marks can take a stop at an address's end, and an edited address keeps
/// the mark of what it was.
Delta withLinks(Delta delta) {
  final document = Document.fromDelta(delta);
  document.format(0, document.length - 1, const LinkAttribute(null));
  for (final range in linkRanges(document.toPlainText())) {
    document.format(range.start, range.address.length, LinkAttribute(range.address));
  }
  return document.toDelta();
}

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

/// *Waiting to send · Send now* on a note's page: a tap sends what waits, and it says *Sending…* while it goes.
class _SendNow extends StatelessWidget {
  const _SendNow({required this.relay});

  final Relay relay;

  @override
  Widget build(BuildContext context) {
    final sending = relay.status == SyncStatus.syncing;
    return TextButton(
      onPressed: sending ? null : relay.sync,
      style: quietButton(context).copyWith(
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(sending ? 'Sending…' : 'Waiting to send · Send now'),
    );
  }
}
