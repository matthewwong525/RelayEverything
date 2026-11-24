import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../markdown.dart' show Json;
import 'note_state.dart';

export 'note_state.dart';

// The note's words are edited in a web page, `mobile/editor-web/`, built into `assets/editor/`. A phone and the Mac
// show it in the system's web view; the browser app shows it in a frame. The app and the page talk in small JSON
// messages: the app's have `do`, the page's have `is`. The app keeps the Markdown; the page keeps the editing.

/// One open editor page. [send] queues each message until the page has started; [receive] takes each message the page
/// sends. A page that the system closed, such as a web view's process that stopped, loads again with the last document.
abstract class WebNote extends ChangeNotifier {
  WebNote();

  /// The page has started and takes messages.
  bool get booted => _booted;
  bool _booted = false;

  /// The page has drawn the last document it was given: it shows from now on.
  bool get ready => _ready;
  bool _ready = false;

  /// The cursor's styles and the page's mode, as the page last said.
  NoteState get state => _state;
  NoteState _state = const NoteState();

  /// The document as the page last sent it, or as last loaded.
  Json? get doc => _doc;
  Json? _doc;

  /// How long the last load took, from the message to the drawn page, as the page measured it.
  int? get loadMs => _loadMs;
  int? _loadMs;

  /// Each message from the page other than `boot`, `ready` and `state`, which this keeps.
  void Function(Json message)? onMessage;

  /// The pages whose words have the keyboard's focus now: a shake or ⌘Z then undoes the typing, not a delete.
  static final _typing = <WebNote>{};

  /// Whether the words of an open note have the keyboard's focus.
  static bool get typing => _typing.isNotEmpty;

  /// The page whose words have the keyboard's focus, or null: the Mac's *Edit* menu acts on its words.
  static WebNote? get focused => _typing.lastOrNull;

  final _waiting = <Json>[];
  Json? _lastLoad;
  bool _disposed = false;

  /// Sends one message to the page now. A host writes it in its own way.
  @protected
  void post(Json message);

  /// Starts the page again, after the system closed it.
  @protected
  void reloadPage();

  /// The page on the screen.
  Widget view();

  /// Sends [message] once the page takes messages. A `load` drops what still waits: it replaces everything.
  void send(Json message) {
    if (_disposed) return;
    if (message['do'] == 'load') {
      _lastLoad = {...message};
      _doc = (message['doc'] as Map?)?.cast();
      _ready = false;
      _state = const NoteState();
      _waiting.clear();
    } else {
      _keep(message);
    }
    if (!_booted) {
      _waiting.add(message);
      return;
    }
    post(message);
  }

  /// Opens [doc] in the page, with a fresh Undo, in place of what it showed.
  void load({required Json doc, required Map<String, String> theme, bool editable = true, bool fromElsewhere = false,
      bool focus = false, double bottom = 0, bool keys = false, List<String> appKeys = const [], bool mac = false,
      String placeholder = '', String highlight = 'purple', Json head = const {}, Json files = const {}}) =>
    send({
      'do': 'load', 'doc': doc, 'theme': theme, 'editable': editable, 'fromElsewhere': fromElsewhere, 'focus': focus,
      'bottom': bottom, 'keys': keys, 'appKeys': appKeys, 'mac': mac, 'placeholder': placeholder,
      'highlight': highlight, 'head': head, 'files': files,
    });

  /// Does one editing [action] in the page, such as `bold` or `indent` with 1.
  void run(String action, [Object? value]) => send({'do': 'run', 'action': action, 'value': ?value});

  /// An *Edit* menu item on the words: `cut`, `copy`, `paste`, `select-all`, `undo` or `redo`. A host whose page can
  /// not do one itself, such as the Mac's web view for the clipboard, does it in its own way.
  void editItem(String action) => run(action);

  /// Writes a setting sent after the load into the last load, so a page that starts again gets the note as it is now:
  /// its files, its date line, its colours, the room under the words, the pen, the page keys, the placeholder and
  /// whether it edits.
  void _keep(Json message) {
    final load = _lastLoad;
    if (load == null) return;
    Json merged(Object? before, Object? after) => {...?(before as Map?)?.cast<String, Object?>(),
      ...?(after as Map?)?.cast<String, Object?>()};
    switch (message['do']) {
      case 'files':
        load['files'] = merged(load['files'], message['files']);
      case 'head':
        load['head'] = merged(load['head'], message['head']);
      case 'theme':
        load['theme'] = message['theme'];
      case 'bottom':
        load['bottom'] = message['bottom'];
      case 'highlight':
        load['highlight'] = message['colour'] ?? load['highlight'];
      case 'appKeys':
        load['appKeys'] = message['appKeys'];
      case 'run' when message['action'] == 'editable':
        load['editable'] = message['value'] == true;
      case 'run' when message['action'] == 'placeholder':
        load['placeholder'] = message['value'] ?? '';
    }
  }

  /// Takes one message from the page, as JSON text or as a map.
  void receive(Object? raw) {
    if (_disposed) return;
    final Json message;
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return;
      message = decoded.cast<String, Object?>();
    } on FormatException {
      return;
    }
    switch (message['is']) {
      case 'boot':
        // A second start: the page loaded again by itself, as a frame the browser's page moved does. It gets the note
        // back, as after [gone].
        if (_booted) {
          _booted = false;
          _again();
        }
        _booted = true;
        final waiting = List.of(_waiting);
        _waiting.clear();
        waiting.forEach(post);
      case 'ready':
        _ready = true;
        _loadMs = (message['ms'] as num?)?.toInt();
        notifyListeners();
      case 'state':
        _state = NoteState.fromJson(message);
        _state.focus ? _typing.add(this) : _typing.remove(this);
        notifyListeners();
      case 'changed':
        _doc = (message['doc'] as Map?)?.cast();
        onMessage?.call(message);
      case String():
        onMessage?.call(message);
    }
  }

  /// The system closed the page: it starts again and gets the last document back, as it was.
  void gone() {
    if (_disposed) return;
    _booted = false;
    _again();
    reloadPage();
  }

  /// The page starts again: it shows nothing until it draws, and its next message is the last load, with the words
  /// and every setting as they are now, and no keyboard.
  void _again() {
    _ready = false;
    _state = const NoteState();
    _typing.remove(this);
    final load = _lastLoad;
    if (load != null) {
      _waiting
        ..clear()
        ..add({...load, 'doc': ?_doc, 'focus': false});
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _typing.remove(this);
    onMessage = null;
    super.dispose();
  }
}

/// The JavaScript that hands [message] to a page in a web view: one JSON text, so no letter in a note can break out.
String scriptFor(Json message) => 'window.relayReceive(${jsonEncode(jsonEncode(message))})';

/// Whether a web view may load [url]: only the editor page itself. A link opens in the browser, never in the note.
bool pageMayLoad(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme == 'about' && uri.path == 'blank') return true;
  return uri.scheme == 'file' && uri.path.endsWith('/assets/editor/index.html');
}

/// Whether [message] puts the cursor in the words: a load with `focus`, or a run of `focus`.
bool asksFocus(Json message) =>
  (message['do'] == 'load' && message['focus'] == true) || (message['do'] == 'run' && message['action'] == 'focus');
