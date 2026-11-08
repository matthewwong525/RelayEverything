import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:share_plus/share_plus.dart';

import '../brand.dart';
import '../controller.dart' show newClientId;
import '../editor/markdown.dart';
import '../relay.dart';
import 'back_to.dart';
import 'days.dart';
import 'note_bars.dart';
import 'note_blocks.dart';
import 'round_button.dart';

/// Picks photos ([photos] true) or files from the phone. The app's is `file_picker`; a test passes its own.
typedef FilesPicker = Future<List<NewFile>> Function({required bool photos});

/// The phone's own picker: Photos for pictures and videos, Files for any file.
Future<List<NewFile>> pickWithPhone({required bool photos}) async {
  final picked = await FilePicker.pickFiles(type: photos ? FileType.media : FileType.any);
  return [
    for (final file in picked)
      if (file.path != null) NewFile(path: file.path!, name: file.name, size: await file.length() ?? 0),
  ];
}

/// Gives a note's words to the phone's share sheet. The app's is `share_plus`; a test passes its own.
typedef Sharer = Future<void> Function(String text);

Future<void> shareWithPhone(String text) => SharePlus.instance.share(ShareParams(text: text));

/// How long typing pauses before the change is kept: under the two seconds the person may wait.
const savePause = Duration(milliseconds: 1500);

/// One note's page, as Apple Notes has it: the note to read, and a tap in its words edits it in place. A new note
/// opens with the keyboard up and a Title first line. Each change is kept on a pause and on leave, with no *Save*.
class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.relay, this.entry, this.picker, this.sharer, this.back = 'Notes'});

  final Relay relay;
  /// The note to open, or null for a new one.
  final Entry? entry;
  final FilesPicker? picker;
  final Sharer? sharer;
  /// The page it opened from, *Home* or a folder, which its back button names.
  final String back;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final String _id = widget.entry?.id ?? newClientId();
  /// The phone keeps the note: set only once an add kept it, so a save after an add that kept nothing adds again.
  late bool _stored = widget.entry != null;
  /// Saves made before the phone kept the note that still wait in [_writing]: a save meanwhile goes after them, so
  /// words cleared meanwhile still delete the note on leave.
  int _adds = 0;
  late final QuillController _controller;
  late Delta _saved;
  /// The words as last kept: a file added to an unchanged note keeps them as they were.
  late String _savedText = widget.entry?.text ?? '';
  StreamSubscription<DocChange>? _changes;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _pause;
  Future<void> _writing = Future.value();
  ScaffoldMessengerState? _messenger;
  /// Kept with no send yet, as typing saves: leaving sends it.
  bool _unsent = false;
  /// A voice note still writing its words, or one whose words failed: the page shows that until the words come.
  late bool _waiting = _wordsMissing(widget.entry);
  bool _formatting = false;
  /// Set with the keyboard, or at once when a button brings it up, so the edit that comes first waits for a pause.
  late bool _typing = widget.entry == null;
  double _keyboard = 300;

  Relay get relay => widget.relay;

  static bool _wordsMissing(Entry? entry) => entry != null && (entry.writing || entry.failed);

  /// The kept note has no file and no recording, so blank words leave nothing in it.
  bool get _bare {
    final note = _current;
    return note != null && note.files.isEmpty && note.recording == null && !note.voice;
  }

  /// The note as the list has it now, so words still being written fill in here too.
  Entry? get _current {
    final opened = widget.entry;
    if (!_stored) return null;
    return relay.entries.where((other) => other.id == _id &&
      (_id.isNotEmpty || (other.at == opened?.at && other.voice == opened?.voice))).firstOrNull ?? opened;
  }

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _controller = QuillController(document: _documentOf(entry), selection: const TextSelection.collapsed(offset: 0));
    _listen();
    _focus.addListener(_focusChanged);
    relay.addListener(_relayChanged);
  }

  static Document _documentOf(Entry? entry) => Document.fromDelta(entry == null
    ? (Delta()..insert('\n', Attribute.h1.toJson()))
    : markdownToDelta(entry.text, title: true));

  void _listen() {
    _saved = _controller.document.toDelta();
    _changes?.cancel();
    _changes = _controller.document.changes.listen((_) => _changed());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard > 100) _keyboard = keyboard;
  }

  @override
  void dispose() {
    _save(sendNow: true, leaving: true);
    relay.removeListener(_relayChanged);
    _changes?.cancel();
    _pause?.cancel();
    _focus.dispose();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// The format panel lets go of the cursor, but the person is still editing; the cursor coming back closes it.
  void _focusChanged() {
    if (_focus.hasFocus) _formatting = false;
    _typing = _focus.hasFocus || _formatting;
    if (mounted) setState(() {});
  }

  /// Words that came for a voice note fill the page, once.
  void _relayChanged() {
    final note = _current;
    if (!_waiting || note == null || note.writing || note.failed) return;
    _controller.document = _documentOf(note);
    _savedText = note.text;
    _listen();
    setState(() => _waiting = false);
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
    final unsent = _unsent;
    _unsent = !sendNow;
    final adding = !_stored;
    if (adding) _adds++;
    _writing = _writing.then((_) async {
      String? problem;
      if (_stored && empty && files.isEmpty && _bare) {
        if (leaving && await relay.dropEmptyNote(_id)) _stored = false;
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
    final photos = await showModalBottomSheet<bool>(context: context, builder: (context) => SafeArea(
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
      return _say('The phone did not give the file. Try again.');
    }
    if (mounted && picked.isNotEmpty) _save(sendNow: !_focus.hasFocus, files: picked);
  }

  String get _plain => plainText(deltaToMarkdown(_controller.document.toDelta()));

  Future<void> _share() => (widget.sharer ?? shareWithPhone)(_plain);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _plain));
    _say('Copied');
  }

  void _compose() => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
    builder: (_) => NoteEditor(relay: relay, picker: widget.picker, sharer: widget.sharer, back: widget.back)));

  /// *Yesterday at 18:05 · Home*.
  String _when(BuildContext context, DateTime at, String? place) {
    final days = daysAgo(at, DateTime.now());
    final day = days <= 0 ? 'Today' : days == 1 ? 'Yesterday' : MaterialLocalizations.of(context).formatMediumDate(at);
    return ['$day at ${TimeOfDay.fromDateTime(at).format(context)}', place].whereType<String>().join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final editing = _focus.hasFocus || _formatting;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > 100) _keyboard = inset;
    return Scaffold(
      appBar: AppBar(leading: BackTo(widget.back), leadingWidth: BackTo.widthOf(widget.back), actions: [
        ButtonPill(children: [
          PillIconButton(icon: CupertinoIcons.square_arrow_up, tooltip: 'Share', onPressed: _share),
          _MoreMenu(copy: _copy, play: _current?.recording == null ? null : () => relay.play(_current!.recording!)),
        ]),
        if (editing) Padding(padding: const EdgeInsets.only(left: 8),
          child: RoundIconButton(icon: CupertinoIcons.checkmark_alt, tooltip: 'Done', onPressed: _done, accent: true)),
        const SizedBox(width: 12),
      ]),
      body: Column(children: [
        Expanded(child: Stack(children: [
          Positioned.fill(child: ListenableBuilder(listenable: relay, builder: (context, _) => _page(context, brand))),
          if (!_waiting && !_formatting) Positioned(left: 16, right: 16, bottom: editing ? 8 : 0, child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 12),
            child: editing
              ? Center(child: FloatingToolBar(onStyles: _styles, onChecklist: _checklist, onAttach: _attach))
              : ReadingBar(onChecklist: _checklist, onAttach: _attach, onCompose: _compose),
          )),
        ])),
        if (_formatting) FormatSheet(controller: _controller, height: _keyboard, onClose: _closeStyles),
      ]),
    );
  }

  Widget _page(BuildContext context, BrandColors brand) {
    final note = _current;
    final muted = TextStyle(fontSize: 13, color: brand.muted);
    final recording = note?.recording;
    final state = note == null ? null : sendState(note);
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_when(context, note?.at ?? DateTime.now(), note?.place), style: muted, textAlign: TextAlign.center),
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
            controller: _controller,
            focusNode: _focus,
            scrollController: _scroll,
            config: QuillEditorConfig(
              scrollable: false,
              autoFocus: widget.entry == null,
              placeholder: recording != null ? 'No words, only the recording.' : 'What do you want to keep?',
              customStyles: noteStyles(context),
              // The only way to draw Apple's round checklist circles and dashed lists; pinned by pubspec.lock.
              // ignore: experimental_member_use
              customLeadingBlockBuilder: (_, config) => _leading(config, brand),
            ),
          ),
        for (final file in note?.files ?? const <EntryFile>[])
          Padding(padding: const EdgeInsets.only(top: 14),
            child: file.picture ? NotePicture(file: file, relay: relay) : NoteFileRow(file: file, relay: relay)),
        if (recording != null) Padding(padding: const EdgeInsets.only(top: 14),
          child: PlayRow(length: note?.length, onPlay: () => relay.play(recording))),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 14), child: Row(spacing: 8, children: [
          BrandTag(note.voice ? 'Voice' : 'Typed', spark: note.voice, large: true),
          if (state != null) Text(state, style: muted),
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
  final ink = brandOf(context).ink;
  DefaultTextBlockStyle block(double size, FontWeight weight, double top) => DefaultTextBlockStyle(
    TextStyle(fontFamily: brandFont, fontSize: size, fontWeight: weight, height: 1.3, color: ink), HorizontalSpacing.zero,
    VerticalSpacing(top, 4), VerticalSpacing.zero, null);
  return DefaultStyles(
    h1: block(28, FontWeight.w700, 4),
    h2: block(22, FontWeight.w700, 10),
    h3: block(19, FontWeight.w600, 8),
    paragraph: DefaultTextBlockStyle(TextStyle(fontFamily: brandFont, fontSize: 17, height: 1.5, color: ink), HorizontalSpacing.zero,
      VerticalSpacing.zero, VerticalSpacing.zero, null),
  );
}

/// ⋯ on the note's page: *Copy*, and *Play* for a voice note.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.copy, this.play});

  final VoidCallback copy;
  final VoidCallback? play;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      MenuItemButton(leadingIcon: const Icon(CupertinoIcons.doc_on_doc, size: 20), onPressed: copy, child: const Text('Copy')),
      if (play != null)
        MenuItemButton(leadingIcon: const Icon(CupertinoIcons.play_fill, size: 20), onPressed: play, child: const Text('Play')),
    ],
    builder: (context, menu, _) => PillIconButton(icon: CupertinoIcons.ellipsis, tooltip: 'More',
      onPressed: () => menu.isOpen ? menu.close() : menu.open()),
  );
}
