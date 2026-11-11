import 'dart:async';
import 'dart:convert';

import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client_id.dart';
import '../data/files.dart';
import '../relay.dart';
import 'page_close.dart';
import 'space.dart';

/// Opens a file's address in a new browser tab; a test passes its own.
typedef TabOpener = Future<bool> Function(Uri address);

Future<bool> openInTab(Uri address) => launchUrl(address, webOnlyWindowName: '_blank');

/// Sends a change as the page closes, with no answer to wait for; a test passes its own.
typedef LastSend = void Function(String method, Uri address, [String? json]);

/// Plays a recording from its address; a test passes its own.
typedef UrlPlayer = Future<void> Function(Uri address);

AudioPlayer? _player;

Future<void> playFromUrl(Uri address) async {
  final player = _player ??= AudioPlayer();
  await player.stop();
  await player.setUrl(address.toString());
  unawaited(player.play());
}

/// Where the browser's sign-in stands: [checking] until `GET account` answers.
enum WebSignIn { checking, signedIn, signedOut }

/// The words for a part only the phone app does.
const onlyOnPhone = 'Do this in the Relay Everything app on your phone.';

/// One note as the browser has it: the [entry] the screens show, and how the server names it.
class _Note {
  _Note(this.entry, {this.serverId, this.clientId, this.mine = false});

  Entry entry;
  String? serverId;
  /// The Web device's own id for a note the browser wrote; the server finds it by this.
  final String? clientId;
  final bool mine;

  Map<String, String> get key => mine && clientId != null ? {'clientId': clientId!} : {'id': serverId!};
}

/// The person's notes in the browser, read and changed through their Relay Everything page's routes with the sign-in
/// cookie. It keeps them only in memory: a reload reads them again, and nothing stays in the browser.
class WebRelay extends Relay {
  WebRelay({required this.client, TabOpener? opener, UrlPlayer? player, DateTime Function()? clock, LastSend? lastSend})
    : _opener = opener ?? openInTab, _player = player ?? playFromUrl, _clock = clock ?? DateTime.now,
      _lastSend = lastSend ?? sendAsPageCloses;

  final SpaceClient client;
  final TabOpener _opener;
  final UrlPlayer _player;
  final DateTime Function() _clock;
  final LastSend _lastSend;

  WebSignIn _signIn = WebSignIn.checking;
  WebSignIn get signInState => _signIn;
  String? _email;
  /// The signed-in account's email, from `GET account`.
  String? get email => _email;

  final _notes = <String, _Note>{};
  /// Notes deleted with *Undo* still showing: the delete runs when the bar ends.
  final _deletes = <String, Timer>{};
  final _hidden = <String, _Note>{};
  int _next = 0;
  /// A read left a change to a note out, such as the one open in the editor: [_next] stays before it, so the read after
  /// the note closes takes it.
  bool _held = false;
  bool _loaded = false;
  /// Notes whose words the server did not take because no answer came: they go again at the next save, when the note
  /// closes, and at each sync. A read leaves them as the person typed them.
  final _unsent = <String>{};
  /// The files whose bytes did not reach the server yet, by note and file id: they go again with the next send.
  final _bytes = <String, Map<String, NewFile>>{};
  /// New notes that got no answer from the server: each is also in [_unsent], and goes again as a new note.
  final _unposted = <String>{};
  /// The changes go one at a time, in the order the person made them.
  Future<void> _sending = Future.value();
  Future<void>? _pulling;
  SyncStatus _status = SyncStatus.idle;
  Settings _settings = const Settings(sending: true);
  Set<String> _folded = {};

  @override RelayPlatform get platform => RelayPlatform.web;
  @override bool get connected => _signIn == WebSignIn.signedIn;
  @override String? get server => client.base.origin;
  @override SyncStatus get status => _status;
  @override int get waiting => 0;
  @override Settings get settings => _settings;

  @override
  List<Entry> get entries => [for (final note in _notes.values) note.entry]..sort((a, b) => b.at.compareTo(a.at));

  /// Asks who is signed in, then reads every note. A 401 shows the sign-in.
  Future<void> start() async {
    try {
      final account = await client.get('account');
      _email = account['email'] as String?;
      _signIn = WebSignIn.signedIn;
    } on SpaceRefused catch (refused) {
      _signIn = refused.signedOut ? WebSignIn.signedOut : WebSignIn.signedIn;
      if (!refused.signedOut) notice(refused.message);
    }
    notifyListeners();
    if (connected) await pullNotes();
  }

  /// The sign-in ended, such as on a 401: the notes go from memory and the sign-in shows. [disconnect] sends what waits
  /// first; after a 401 nothing can go.
  void signedOut() {
    for (final timer in _deletes.values) {
      timer.cancel();
    }
    _deletes.clear();
    _hidden.clear();
    _notes.clear();
    _unsent.clear();
    _unposted.clear();
    _bytes.clear();
    _next = 0;
    _held = false;
    _loaded = false;
    _email = null;
    _signIn = WebSignIn.signedOut;
    notifyListeners();
  }

  @override
  Future<void> pullNotes() => _pulling ??= _pull().whenComplete(() => _pulling = null);

  /// Sends the changes that did not go, then reads the notes changed elsewhere: on return to the tab and on leaving a note.
  @override
  Future<void> sync() async {
    if (!connected) return;
    await _inOrder(_sendWaiting);
    await pullNotes();
  }

  @override String? get openNote => _openNote;
  String? _openNote;

  /// Leaving a note sends its words that did not go, and reads the changes a read held for it.
  @override
  set openNote(String? id) {
    final left = _openNote;
    _openNote = id;
    if (left == null || left == id || !(_held || _unsent.contains(left) || _bytes.containsKey(left))) return;
    // After the frame: the editor gives the note back as it closes, while the screens can not change.
    Timer.run(() => unawaited(sync()));
  }

  /// Reads the notes changed since the last read, a page at a time, and shows each page as it comes.
  Future<void> _pull() async {
    if (!connected) return;
    _status = SyncStatus.syncing;
    notifyListeners();
    try {
      var since = _next;
      var held = false;
      while (true) {
        final page = await client.get('notes', query: {'since': '$since', if (_loaded) 'deleted': '1'});
        for (final note in (page['notes'] as List?) ?? const []) {
          if (note is Map<String, dynamic> && !_apply(note)) held = true;
        }
        final next = page['next'] as int? ?? since;
        final more = page['more'] == true && next > since;
        if (!held) _next = next;
        notifyListeners();
        if (!more) break;
        since = next;
      }
      _held = held;
      _loaded = true;
      _status = SyncStatus.synced;
    } on SpaceRefused catch (refused) {
      _status = refused.status == null ? SyncStatus.offline : SyncStatus.refused;
      if (!refused.signedOut) notice(refused.message);
    }
    notifyListeners();
  }

  /// Keeps one note from `GET notes`, or drops a deleted one. It returns false for a change it left out: the note open in
  /// the editor, and one whose typed words did not go yet, keep their words until the read after.
  bool _apply(Map<String, dynamic> json) {
    final serverId = json['id'] as String;
    final clientId = json['clientId'] as String?;
    final mine = json['mine'] == true;
    final id = mine && clientId != null ? clientId : serverId;
    if (json['deleted'] == true) {
      final key = [..._notes.keys, ..._hidden.keys].where((key) => (_notes[key] ?? _hidden[key])!.serverId == serverId)
        .firstOrNull ?? id;
      if (_notes.containsKey(key) && (key == openNote || _unsent.contains(key))) return false;
      _notes.remove(key);
      // Deleted elsewhere while *Undo* shows: there is nothing left to delete or to bring back.
      _deletes.remove(key)?.cancel();
      _hidden.remove(key);
      _bytes.remove(key);
      return true;
    }
    final note = _Note(entryOf(json, id), serverId: serverId, clientId: clientId, mine: mine);
    // *Undo* brings back the newest words.
    if (_hidden.containsKey(id)) {
      _hidden[id] = note;
      return true;
    }
    if (_notes.containsKey(id) && (id == openNote || _unsent.contains(id))) return false;
    _notes[id] = note;
    return true;
  }

  /// The screens' row for a note from `GET notes`, with the routes that read its files and recording.
  Entry entryOf(Map<String, dynamic> json, String id) {
    final serverId = json['id'] as String;
    final ring = json['source'] == 'ring';
    final audio = json['audio'] == true;
    return Entry(
      id: id,
      text: json['text'] as String? ?? '',
      at: DateTime.fromMillisecondsSinceEpoch(json['recordedAt'] as int),
      sent: true,
      voice: ring || audio,
      recording: audio ? client.api('audio', {'id': serverId}).toString() : null,
      files: [
        for (final file in (json['attachments'] as List?) ?? const [])
          if (file is Map) EntryFile(id: file['id'] as String, name: file['name'] as String? ?? '', type: file['type'] as String? ?? '',
            size: file['size'] as int? ?? 0,
            url: file['ready'] == true ? client.api('attachment', {'id': file['id'] as String}).toString() : null),
      ],
      from: json['mine'] == true ? null : json['device'] as String?,
    );
  }

  static const _nothing = 'Give the note words or a file.';
  static const _kept = 'Your change stays here, and goes again at the next save or when you close the note.';

  /// Runs [send] after the changes before it, so the server gets them in order.
  Future<T> _inOrder<T>(Future<T> Function() send) {
    final done = _sending.then((_) => send());
    _sending = done.then((_) {}, onError: (Object _) {});
    return done;
  }

  /// No answer, or a fault on the server's side: the same change can go again later. Any other refusal is the answer.
  static bool _again(SpaceRefused refused) => refused.status == null || refused.status == 429 || refused.status! >= 500;

  @override
  Future<String?> addNote(String text, {List<NewFile> files = const [], String? id, bool sendNow = true}) async {
    final check = checkFiles(const [], files);
    final (kept, problems) = _readable(check);
    if (text.trim().isEmpty && kept.isEmpty) return [...problems, if (problems.isEmpty) _nothing].join(' ');
    final clientId = id ?? newClientId();
    final now = _clock();
    final attached = [for (final file in kept) (newClientId(), file)];
    _notes[clientId] = _Note(Entry(id: clientId, text: text, at: now, waiting: true, files: [for (final (fileId, file) in attached)
      EntryFile(id: fileId, name: file.name, type: file.type, size: file.size)]), clientId: clientId, mine: true);
    if (attached.isNotEmpty) _bytes[clientId] = {for (final (fileId, file) in attached) fileId: file};
    // Unsent until the server answers, so a page that closes first still sends it.
    _unposted.add(clientId);
    _unsent.add(clientId);
    notifyListeners();
    return _inOrder(() async {
      try {
        final answer = await client.post('notes', {'clientId': clientId, 'text': text, 'createdAt': now.millisecondsSinceEpoch,
          if (attached.isNotEmpty) 'attachments': _listOf(attached)});
        final note = _notes[clientId] ?? _hidden[clientId];
        note?.serverId = answer['id'] as String?;
        _unposted.remove(clientId);
        // An edit made while this went is still to go.
        if (note?.entry.text == text) _unsent.remove(clientId);
      } on SpaceRefused catch (refused) {
        // No answer: the note stays, with its files, and goes again at the next save, on close and as the page closes.
        if (_again(refused) && (_notes.containsKey(clientId) || _hidden.containsKey(clientId))) {
          _settle(clientId);
          return ['${refused.message} $_kept', ...problems].join(' ');
        }
        _drop(clientId);
        return [refused.message, ...problems].join(' ');
      }
      problems.addAll(await _sendFiles(clientId));
      _settle(clientId);
      return problems.isEmpty ? null : problems.join(' ');
    });
  }

  /// Shows the new words at once, then sends them. With no answer, the typed words stay and go again later; a newer change
  /// from elsewhere, or a refusal, takes the note back to what it was.
  @override
  Future<String?> editNote(String id, String text, {List<NewFile> files = const [], bool sendNow = true}) async {
    final note = _notes[id];
    if (note == null) return 'This note is gone. It was deleted, maybe on another device.';
    final check = checkFiles(const [], files, already: note.entry.files.length);
    final (kept, problems) = _readable(check);
    final attached = [for (final file in kept) (newClientId(), file)];
    final before = note.entry;
    // A new note still to go is not an earlier edit: a refusal of this edit leaves the note as the server has it.
    final hadUnsent = _unsent.contains(id) && !_unposted.contains(id);
    final all = [...before.files, for (final (fileId, file) in attached)
      EntryFile(id: fileId, name: file.name, type: file.type, size: file.size)];
    note.entry = _copy(before, text: text, files: all, waiting: attached.isNotEmpty);
    if (attached.isNotEmpty) (_bytes[id] ??= {}).addAll({for (final (fileId, file) in attached) fileId: file});
    _unsent.add(id);
    notifyListeners();
    return _inOrder(() async {
      final refused = await _sendWords(id);
      if (refused != null && !_again(refused)) {
        if (_notes[id] == note) note.entry = before;
        if (!hadUnsent) _unsent.remove(id);
        for (final (fileId, _) in attached) {
          _bytes[id]?.remove(fileId);
        }
        if (_bytes[id]?.isEmpty ?? false) _bytes.remove(id);
        notifyListeners();
        // A newer change came from elsewhere: its words show after the read, once the note closes.
        if (refused.status == 409) unawaited(pullNotes());
        return [refused.message, ...problems].join(' ');
      }
      // The words did not go, so the server does not list the new files yet: their bytes go after the words do.
      if (refused != null) problems.insert(0, '${refused.message} $_kept');
      if (refused == null) problems.addAll(await _sendFiles(id));
      _settle(id);
      return problems.isEmpty ? null : problems.join(' ');
    });
  }

  /// Sends note [id]'s words as they are now, and lists its files when some still wait: the server adds the ones it
  /// lacks. A new note that got no answer goes as new again. Gives the refusal, or null once the words went.
  Future<SpaceRefused?> _sendWords(String id) async {
    final note = _notes[id];
    if (note == null) {
      _unsent.remove(id);
      return null;
    }
    final files = [for (final file in note.entry.files) {'id': file.id, 'name': file.name, 'type': file.type, 'size': file.size}];
    try {
      if (_unposted.contains(id)) {
        final answer = await client.post('notes', {..._newOf(note), if (files.isNotEmpty) 'attachments': files});
        note.serverId = answer['id'] as String?;
        _unposted.remove(id);
        // `added` is false when the first send got there unanswered: the server kept its words, so these go as an edit.
        if (answer['added'] != false) {
          _unsent.remove(id);
          return null;
        }
      }
      await client.patch('notes', {...note.key, 'text': note.entry.text, 'editedAt': _clock().millisecondsSinceEpoch,
        if (_bytes[id]?.isNotEmpty ?? false) 'attachments': files});
      _unsent.remove(id);
      return null;
    } on SpaceRefused catch (refused) {
      // The server refused the new note itself: it can not go, so it leaves this page too.
      if (_unposted.contains(id) && !_again(refused)) _drop(id);
      return refused;
    }
  }

  /// A new note as `POST notes` takes it, with no files.
  Map<String, Object?> _newOf(_Note note) =>
    {'clientId': note.clientId, 'text': note.entry.text, 'createdAt': note.entry.at.millisecondsSinceEpoch};

  /// A new note the server refused goes from this page, with its files.
  void _drop(String id) {
    _notes.remove(id);
    _hidden.remove(id);
    _deletes.remove(id)?.cancel();
    _unsent.remove(id);
    _unposted.remove(id);
    _bytes.remove(id);
    notifyListeners();
  }

  /// What did not go before: each note's words, then the files still waiting. A change the server refuses for good
  /// is dropped with a notice, and the read after shows the note as the server has it.
  Future<void> _sendWaiting() async {
    for (final id in [..._unsent]) {
      final posting = _unposted.contains(id);
      final refused = await _sendWords(id);
      if (refused == null && _bytes[id] == null) _settle(id);
      if (refused == null || _again(refused)) continue;
      _unsent.remove(id);
      _bytes.remove(id);
      notice(posting ? 'A new note did not go. ${refused.message}' : 'Your change to a note did not go. ${refused.message}');
    }
    for (final id in [..._bytes.keys]) {
      if (_unsent.contains(id)) continue;
      final problems = await _sendFiles(id);
      _settle(id);
      if (problems.isNotEmpty) notice(problems.join(' '));
    }
  }

  /// The files the browser gave bytes for, and the words for the rest and for those over the limits.
  (List<NewFile>, List<String>) _readable(FilesCheck check) {
    final problems = [?check.problem];
    final kept = [for (final file in check.kept) if (file.bytes != null) file];
    final unread = check.kept.length - kept.length;
    if (unread > 0) {
      problems.add(unread == 1 ? 'The browser did not give one file. Try again.' : 'The browser did not give $unread files. Try again.');
    }
    return (kept, problems);
  }

  static List<Map<String, Object>> _listOf(List<(String, NewFile)> files) =>
    [for (final (id, file) in files) {'id': id, 'name': file.name, 'type': file.type, 'size': file.size}];

  /// Sends the bytes of each of note [id]'s files that wait, after its note, and gives the words for each that did not
  /// go. With no answer the file waits for the next send; a file the server refuses leaves the note.
  Future<List<String>> _sendFiles(String id) async {
    final waiting = _bytes[id];
    if (waiting == null) return const [];
    final noteClientId = (_notes[id] ?? _hidden[id])?.clientId ?? id;
    final problems = <String>[];
    for (final MapEntry(key: fileId, value: file) in [...waiting.entries]) {
      try {
        await client.upload('attachments', file.bytes!, {'Content-Type': file.type, 'X-Note-Client-Id': noteClientId,
          'X-Attachment-Id': fileId});
        waiting.remove(fileId);
      } on SpaceRefused catch (refused) {
        if (_again(refused)) {
          problems.add('${file.name} did not upload. ${refused.message} It goes again at the next save.');
          continue;
        }
        waiting.remove(fileId);
        problems.add('${file.name} did not upload. ${refused.message}');
        final note = _notes[id];
        if (note != null) note.entry = _copy(note.entry, files: [for (final kept in note.entry.files) if (kept.id != fileId) kept]);
      }
    }
    if (waiting.isEmpty) _bytes.remove(id);
    return problems;
  }

  /// Each file the server has shows from its route; one whose bytes still wait shows as on its way.
  void _settle(String id) {
    final note = _notes[id];
    if (note == null) return;
    final waiting = _bytes[id] ?? const {};
    note.entry = _copy(note.entry, waiting: waiting.isNotEmpty || _unsent.contains(id), files: [for (final file in note.entry.files)
      file.url != null || waiting.containsKey(file.id) ? file : EntryFile(id: file.id, name: file.name, type: file.type,
        size: file.size, url: client.api('attachment', {'id': file.id}).toString())]);
    notifyListeners();
  }

  static Entry _copy(Entry entry, {String? text, List<EntryFile>? files, bool? waiting}) => Entry(id: entry.id,
    text: text ?? entry.text, at: entry.at, sent: entry.sent, waiting: waiting ?? entry.waiting,
    voice: entry.voice, recording: entry.recording, length: entry.length, files: files ?? entry.files, from: entry.from);

  @override
  Future<Emptied> dropEmptyNote(String id) async {
    final note = _notes[id];
    if (note == null) return Emptied.dropped;
    if (note.entry.files.isNotEmpty || note.entry.recording != null) return Emptied.kept;
    if (note.serverId == null && note.mine) {
      _notes.remove(id);
      _unsent.remove(id);
      _unposted.remove(id);
      notifyListeners();
      return Emptied.dropped;
    }
    await deleteNote(id);
    return Emptied.deleting;
  }

  @override
  Future<void> deleteNote(String id) async {
    final note = _notes.remove(id);
    if (note == null) return;
    _hidden[id] = note;
    notifyListeners();
    _deletes.remove(id)?.cancel();
    _deletes[id] = Timer(deleteAfter, () => unawaited(_finishDelete(id)));
  }

  @override
  Future<void> undoDelete(String id) async {
    _deletes.remove(id)?.cancel();
    final note = _hidden.remove(id);
    if (note != null) _notes[id] = note;
    notifyListeners();
  }

  @override
  Future<void> endUndo(String id) async {
    final timer = _deletes.remove(id);
    if (timer == null) return;
    timer.cancel();
    await _finishDelete(id);
  }

  /// The *Undo* time ended: the note goes from the person's space. A refused delete brings it back.
  Future<void> _finishDelete(String id) async {
    _deletes.remove(id);
    final note = _hidden.remove(id);
    if (note == null || note.serverId == null && note.clientId == null) return;
    final unsent = _unsent.remove(id);
    // A new note that got no answer may still be on the server, so its delete goes too.
    final unposted = _unposted.remove(id);
    final files = _bytes.remove(id);
    try {
      await _inOrder(() => client.delete('notes', query: note.key));
    } on SpaceRefused catch (refused) {
      if (refused.status == 404 || refused.signedOut) return;
      _notes[id] = note;
      if (unsent) _unsent.add(id);
      if (unposted) _unposted.add(id);
      if (files != null) _bytes[id] = files;
      notifyListeners();
      notice('The note was not deleted. ${refused.message}');
    }
  }

  /// Each delete still under *Undo* goes now, as the bar would end it.
  Future<void> _finishDeletes() async {
    final ids = [..._deletes.keys];
    for (final id in ids) {
      _deletes.remove(id)?.cancel();
    }
    await Future.wait([for (final id in ids) _finishDelete(id)]);
  }

  /// The page is closing: each delete under *Undo*, the words that did not go, and the open note's words not yet saved,
  /// are sent as well as the browser lets a closing page send. No answer can come back.
  void pageClosing() {
    final now = _clock().millisecondsSinceEpoch;
    if (editorWords?.call() case (:final id, :final text)) {
      final note = _notes[id];
      if (note == null && !_hidden.containsKey(id) && text.isNotEmpty) {
        _lastSend('POST', client.api('notes'), jsonEncode({'clientId': id, 'text': text, 'createdAt': now}));
      } else if (note != null && note.entry.text != text && (text.isNotEmpty || note.entry.files.isNotEmpty)) {
        note.entry = _copy(note.entry, text: text);
        _unsent.add(id);
      }
    }
    for (final id in [..._deletes.keys]) {
      _deletes.remove(id)!.cancel();
      final note = _hidden.remove(id);
      _unsent.remove(id);
      _unposted.remove(id);
      if (note == null || note.serverId == null && note.clientId == null) continue;
      _lastSend('DELETE', client.api('notes', note.key));
    }
    for (final id in _unsent) {
      final note = _notes[id];
      if (note == null) continue;
      // A new note with no answer goes as new; the edit after it covers a first send that got there unanswered.
      if (_unposted.contains(id) && note.entry.text.isNotEmpty) _lastSend('POST', client.api('notes'), jsonEncode(_newOf(note)));
      _lastSend('PATCH', client.api('notes'), jsonEncode({...note.key, 'text': note.entry.text, 'editedAt': now}));
    }
  }

  @override
  Future<void> openFile(EntryFile file) async {
    final url = file.url;
    if (url == null) return notice('This file is still on its way. Try again soon.');
    if (!await _opener(Uri.parse(url))) notice('The browser did not open the file. Try again.');
  }

  @override
  Future<void> play(String recording) async {
    try {
      await _player(Uri.parse(recording));
    } on Exception {
      notice('The recording did not play. Try again.');
    }
  }

  /// *Sign out*: the deletes under *Undo* and the changes that wait go first. Then the browser's sign-in ends, even when
  /// the server did not answer, and the notes go from memory.
  @override
  Future<void> disconnect() async {
    if (connected) {
      await _finishDeletes();
      await _inOrder(_sendWaiting);
    }
    try {
      await client.postTo(client.signIn('out'));
    } on SpaceRefused {
      // The cookie may already be gone; the browser shows the sign-in either way.
    }
    signedOut();
  }

  @override
  Future<void> setAppearance(Appearance appearance) async {
    _settings = _settings.copyWith(appearance: appearance);
    notifyListeners();
  }

  @override Set<String> get folded => _folded;

  @override
  Future<void> setFolded(String header, bool folded) async {
    _folded = folded ? {..._folded, header} : ({..._folded}..remove(header));
    notifyListeners();
  }

  // The parts below are the phone's own: health, places, the calendar, photos, its webhook and voice notes.
  @override SendState get healthSent => const SendState();
  @override SendState get pointsSent => const SendState();
  @override SendState get calendarSent => const SendState();
  @override List<PhoneCalendar> get calendars => const [];
  @override bool get locationModes => false;
  @override Connections? get connections => null;
  @override Future<void> refreshConnections() async {}
  @override Future<String?> signOutPhone(String id) async => onlyOnPhone;
  @override Future<String?> connect(String code) async => onlyOnPhone;
  @override Future<String?> signIn(String server) async => onlyOnPhone;
  @override Future<String?> setLocationMode(LocationMode mode) async => onlyOnPhone;
  @override Future<String?> setLocationSend(LocationSend send) async => onlyOnPhone;
  @override Future<String?> setServer(String server) async => onlyOnPhone;
  @override Future<String?> setHistory(bool on) async => onlyOnPhone;
  @override Future<String?> setHealth(bool on) async => onlyOnPhone;
  @override Future<String?> setCalendar(bool on) async => onlyOnPhone;
  @override Future<void> setCalendarShown(String id, bool on) async {}
  @override Future<String?> setPhotos(bool on) async => onlyOnPhone;
  @override Future<String?> setPhotosOnMobileData(bool on) async => onlyOnPhone;
  @override Future<int> earlierNotes({SendPlace? to}) async => 0;
  @override Future<String?> startSending({required bool sendEarlier, SendPlace? place, SendPlace? privateTo}) async => onlyOnPhone;
  @override String? get webhookAddress => null;
  @override String? get webhookSecret => null;
  @override WebhookProblem? get webhookProblem => null;
  @override String newWebhookSecret() => '';
  @override Future<String?> saveWebhook(String address, String secret) async => onlyOnPhone;
  @override Future<String> testWebhook(String address, String secret) async => onlyOnPhone;
  @override Future<String?> setPrivatePlace(SendPlace place) async => onlyOnPhone;
  @override bool get privateWebhookMissing => false;
  @override Future<void> stopSending() async {}
  @override ModelState get speechModel => ModelState.missing;
  @override double get modelProgress => 0;
  @override ModelProblem? get modelProblem => null;
  @override int get modelBytes => 0;
  @override void askSpeechModel() {}
  @override void notNowSpeechModel() {}
  @override Future<void> getSpeechModel() async {}
  @override Future<void> removeSpeechModel() async {}
  @override DateTime? get listening => null;
  @override Stream<double>? get level => null;
  @override bool get holdTipSeen => true;
  @override Future<String?> startVoiceNote() async => onlyOnPhone;
  @override Future<String?> endVoiceNote() async => null;
  @override Future<void> cancelVoiceNote() async {}
  @override Future<void> writeWordsAgain() async {}

  @override
  void dispose() {
    for (final timer in _deletes.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
