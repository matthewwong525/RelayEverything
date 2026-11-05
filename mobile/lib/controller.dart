import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'data/api.dart';
import 'data/connection.dart';
import 'data/outbox.dart';
import 'data/sender.dart';
import 'data/settings.dart';
import 'data/store.dart';
import 'relay.dart';
import 'sync/health.dart';
import 'sync/location.dart';
import 'voice/model.dart';
import 'voice/recorder.dart';
import 'voice/transcriber.dart';

const _cacheKey = 'timeline';

/// What voice notes need: the speech model, the microphone, the words and playback. All of it stays on this phone.
class VoiceParts {
  const VoiceParts({required this.model, required this.recorder, required this.transcriber, required this.player});

  final SpeechModel model;
  final VoiceRecorder recorder;
  final Transcriber transcriber;
  final VoicePlayer player;
}

/// A random id for a note, so a resend is stored once.
String newClientId([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(16, (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// The app's one Relay: notes in the store, and the key in the vault. Notes stay on this phone; while sending is on,
/// it syncs on open, on a new note, on pull, and every hour in the background.
class RelayController extends Relay {
  RelayController({required this.store, required this.vault, required this.places, required this.health,
    RelayApi Function(Connection)? apiFor, DateTime Function()? clock, this.schedule, this.voice})
    : _sender = Sender(apiFor), _clock = clock ?? DateTime.now {
    voice?.model.addListener(notifyListeners);
    // A recording at its longest ends as if the person let go.
    voice?.recorder.onLongest = (recording) {
      _listening = null;
      notifyListeners();
      unawaited(_keepVoice(recording));
    };
  }

  final Store store;
  final KeyVault vault;
  final Places places;
  final HealthSource health;
  /// Turns the hourly background sync on or off.
  final Future<void> Function(bool on)? schedule;
  /// Voice notes; with none, the app has typed notes only.
  final VoiceParts? voice;
  final Sender _sender;
  final DateTime Function() _clock;

  Connection? _connection;
  List<Entry> _server = const [];
  List<LocalNote> _notes = const [];
  List<Entry> _entries = const [];
  Cursor? _next;
  SyncStatus _status = SyncStatus.idle;
  int _waiting = 0;
  Settings _settings = const Settings();
  StreamSubscription<Pin>? _history;
  Future<void>? _syncing;
  DateTime? _listening;
  Future<bool>? _starting;
  final _writing = <Future<void>>{};

  @override bool get connected => _connection != null;
  @override String? get server => _connection?.server;
  @override List<Entry> get entries => _entries;
  @override bool get hasMore => _settings.sending && _next != null;
  @override SyncStatus get status => _status;
  @override int get waiting => _waiting;
  @override Settings get settings => _settings;

  RelayApi? get _api => _sender.api(_settings, _connection);

  /// Reads the key, the settings, the notes and the last timeline seen, so the app opens with no network.
  Future<void> load() async {
    _connection = await vault.read();
    final saved = await store.get(settingsKey);
    _settings = Settings.decode(saved, hasKey: _connection != null);
    // A phone that lost its key, such as from a restore, can not send: sending reads as off until a new key.
    if (_connection == null && _settings.sending) _settings = _settings.copyWith(sending: false);
    // The first version's settings, read once by the upgrade rule, are saved in today's shape.
    if (_settings.encode() != saved) await store.set(settingsKey, _settings.encode());
    final cache = await store.get(_cacheKey);
    if (cache != null) _server = [for (final note in jsonDecode(cache) as List) _entryOf(RemoteNote.fromJson(note as Map<String, dynamic>))];
    if (_settings.history) _startHistory();
    // Nothing waits for a fix yet at start, so a note still waiting lost its wait when the app closed.
    await store.settleWaiting(send: _settings.sending);
    await voice?.model.load();
    await _refreshLocal();
    // A voice note whose words the app's close cut short gets them now, from its kept recording.
    _track(_writePending(dropStray: true));
  }

  static Entry _entryOf(RemoteNote note) => Entry(text: note.text, ring: note.source == 'ring', at: note.recordedAt,
    place: note.place, device: note.device, audio: note.audio);

  // A typed note on the server is the same note when its time and words match: the timeline does not give its clientId.
  static String _sameAs(DateTime at, String text) => '${at.millisecondsSinceEpoch} $text';

  Entry _entryOfLocal(LocalNote note) => Entry(text: note.text, ring: false, at: note.createdAt,
    // With sending off the phone looks up no place name, so a pin with no name reads as Pinned.
    place: note.pin == null ? null : note.pin!.place ?? 'Pinned',
    waiting: _settings.sending && note.sentAt == null && (note.queued || note.pinning),
    voice: note.kind == NoteKind.voice, writing: note.wordsPending, recording: note.audioPath,
    length: note.durationMs == null ? null : Duration(milliseconds: note.durationMs!));

  // The server keeps a voice note as typed words; this phone still knows it as a voice note, with its recording.
  static Entry _withVoice(Entry entry, LocalNote? note) => note == null ? entry : Entry(text: entry.text, ring: false,
    at: entry.at, place: entry.place, device: entry.device, waiting: entry.waiting, audio: entry.audio, voice: true,
    recording: note.audioPath, length: note.durationMs == null ? null : Duration(milliseconds: note.durationMs!));

  Future<void> _refreshLocal() async {
    _notes = await store.notes();
    _waiting = await store.waiting();
    _merge();
  }

  /// This phone's notes beside the server's, newest first; a note on both shows once, as the server has it.
  void _merge() {
    final onServer = {for (final entry in _server) if (!entry.ring) _sameAs(entry.at, entry.text)};
    final local = [for (final note in _notes) if (note.sentAt == null || !onServer.contains(_sameAs(note.createdAt, note.text))) _entryOfLocal(note)];
    final voiced = {for (final note in _notes) if (note.kind == NoteKind.voice && note.sentAt != null) _sameAs(note.createdAt, note.text): note};
    final server = [for (final entry in _server) entry.ring ? entry : _withVoice(entry, voiced[_sameAs(entry.at, entry.text)])];
    final merged = <Entry>[];
    var l = 0, s = 0;
    while (l < local.length || s < server.length) {
      final takeLocal = s == server.length || (l < local.length && !local[l].at.isBefore(server[s].at));
      merged.add(takeLocal ? local[l++] : server[s++]);
    }
    _entries = merged;
    notifyListeners();
  }

  @override
  Future<String?> connect(String code) async {
    final connection = Connection.parse(code);
    if (connection == null) return 'That is not a Relay key. Scan the QR code again, or paste all of it.';
    try {
      await _sender.check(connection).timeline();
    } on ApiException catch (error) {
      // With no signal the key is kept and tried on the next sync.
      if (error.failure != Failure.offline) return 'The server did not take this key. Make a new key and try again.';
    }
    await vault.save(connection);
    _connection = connection;
    notifyListeners();
    return null;
  }

  @override
  Future<String?> setServer(String text) async {
    final server = Connection.serverOf(text);
    if (server == null) return 'Enter an address that starts with https:// and has no path.';
    if (_connection == null) return 'Connect a key first.';
    _connection = _connection!.withServer(server);
    await vault.save(_connection!);
    notifyListeners();
    return null;
  }

  @override
  Future<int> earlierNotes() => store.earlierCount();

  @override
  Future<String?> startSending({required bool sendEarlier}) async {
    if (_connection == null) return 'Connect a key first.';
    if (sendEarlier) await store.queueEarlier();
    await _saveSettings(_settings.copyWith(sending: true));
    await _refreshLocal();
    unawaited(sync());
    return null;
  }

  @override
  Future<void> stopSending() async {
    await _saveSettings(_settings.copyWith(sending: false));
    await _history?.cancel();
    _history = null;
    // A round already sending finishes first, so nothing it read lands after the drop.
    await _syncing;
    await store.dropReadings();
    _status = SyncStatus.idle;
    await _refreshLocal();
  }

  @override
  Future<void> disconnect() async {
    await stopSending();
    await vault.forget();
    await store.set(_cacheKey, '[]');
    _connection = null;
    _server = const [];
    _next = null;
    _merge();
  }

  Future<void> _saveSettings(Settings settings) async {
    _settings = settings;
    await store.set(settingsKey, settings.encode());
    await schedule?.call(settings.history || settings.health);
    notifyListeners();
  }

  static const _noLocation = 'Relay may not read your location. Allow it in the phone\'s settings.';
  static const _sendFirst = 'Turn on Send to your Relay server first.';

  @override
  Future<String?> setPinNotes(bool on) async {
    if (on && !await places.allow(always: false)) return _noLocation;
    await _saveSettings(_settings.copyWith(pinNotes: on));
    return null;
  }

  @override
  Future<String?> setHistory(bool on) async {
    if (on && !_settings.sending) return _sendFirst;
    if (on && !await places.allow(always: true)) return 'Relay may not read your location all the time. Allow it in the phone\'s settings.';
    await _saveSettings(_settings.copyWith(history: on));
    if (on) {
      _startHistory();
    } else {
      await _history?.cancel();
      _history = null;
    }
    return null;
  }

  void _startHistory() {
    _history ??= places.history().listen((point) => store.addPoint(point), onError: (_) {});
  }

  @override
  Future<String?> setHealth(bool on) async {
    if (on && !_settings.sending) return _sendFirst;
    if (on && !await health.allow()) return 'Relay may not read your health data. Allow it in the phone\'s health settings.';
    // Health starts from now: nothing was kept while it was off, and there is no earlier backfill.
    if (on) await store.set(healthSince, '${_clock().millisecondsSinceEpoch}');
    await _saveSettings(_settings.copyWith(health: on));
    if (on) unawaited(sync());
    return null;
  }

  /// Keeps and shows the note at once; Save never waits for a fix. With pins on, the note settles only when the phone
  /// has a fix or gives up (up to 10 s), so a sync meanwhile sends the rest and leaves this note waiting.
  @override
  Future<void> addNote(String text) async {
    final note = LocalNote(clientId: newClientId(), text: text.trim(), createdAt: _clock());
    final pinned = _settings.pinNotes;
    await store.addNote(note, waitForPin: pinned, send: _settings.sending);
    await _refreshLocal();
    unawaited(pinned ? _pinThenSync(note.clientId) : sync());
  }

  Future<void> _pinThenSync(String clientId) async {
    Pin? pin;
    try {
      pin = await places.here(name: _settings.sending);
    } on Exception {
      // No fix: the note is kept without a place.
    }
    await store.settlePin(clientId, pin, send: _settings.sending);
    await _refreshLocal();
    await sync();
  }

  /// One sync at a time; a second call waits for the one running. With sending off it does nothing.
  @override
  Future<void> sync() => _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<void> _sync() async {
    final api = _api;
    if (api == null) return;
    _status = SyncStatus.syncing;
    notifyListeners();
    // Sending can turn off while a round runs: from then on it reads, queues and sends nothing more.
    if (_settings.health) {
      try {
        await syncHealth(store, health, now: _clock());
      } on Exception {
        // The health store can be closed for a while, such as on a locked iPhone; the next round reads again.
      }
    }
    if (_settings.sending) await store.queuePoints();
    final result = await flush(store, api, clock: _clock, keepGoing: () => _settings.sending);
    _status = switch (result.failure) { Failure.refused => SyncStatus.refused, null => SyncStatus.synced, _ => SyncStatus.offline };
    if (result.failure == null && _settings.sending) {
      try {
        final page = await api.timeline();
        _server = [for (final note in page.notes) _entryOf(note)];
        _next = page.next;
        await store.set(_cacheKey, jsonEncode([for (final note in page.notes) note.json]));
      } on ApiException catch (error) {
        _status = error.failure == Failure.refused ? SyncStatus.refused : SyncStatus.offline;
      }
    }
    // The stop's own state wins.
    if (!_settings.sending) _status = SyncStatus.idle;
    await _refreshLocal();
  }

  @override
  Future<void> more() async {
    final api = _api, before = _next;
    if (api == null || before == null) return;
    try {
      final page = await api.timeline(before: before);
      _server = [..._server, for (final note in page.notes) _entryOf(note)];
      _next = page.next;
    } on ApiException {
      _status = SyncStatus.offline;
    }
    _merge();
  }

  // Voice notes.

  static const _noMicrophone = 'Relay may not use the microphone. Allow it in the phone\'s settings.';
  static const _microphoneFailed = 'The microphone did not start. Try again.';
  static const _noRecording = 'This recording is not on this phone.';
  static const _holdLonger = 'Hold the button while you talk, then let go.';
  static const _noSpeech = 'No speech heard. Nothing was saved.';

  @override ModelState get speechModel => voice?.model.state ?? ModelState.missing;
  @override double get modelProgress => voice?.model.progress ?? 0;
  @override ModelProblem? get modelProblem => voice?.model.problem;
  @override int get modelBytes => voice?.model.bytes ?? modelSize;
  @override DateTime? get listening => _listening;

  @override
  void askSpeechModel() => voice?.model.ask();

  @override
  void notNowSpeechModel() => voice?.model.notNow();

  @override
  Future<void> getSpeechModel() async {
    final parts = voice;
    if (parts == null) return;
    // Notes kept while the model was away get their words once it is back.
    if (await parts.model.download()) _track(_writePending());
  }

  @override
  Future<void> removeSpeechModel() async {
    final parts = voice;
    if (parts == null) return;
    await parts.transcriber.close();
    await parts.model.remove();
  }

  @override
  Future<String?> startVoiceNote() async {
    final parts = voice;
    if (parts == null || parts.model.state != ModelState.ready || _starting != null || parts.recorder.recording) return null;
    final bool allowed;
    try {
      allowed = await (_starting = parts.recorder.start(newClientId()));
    } catch (_) {
      // The recorder keeps no state from a failed start, so the next press tries again.
      return _microphoneFailed;
    } finally {
      _starting = null;
    }
    if (!allowed) return _noMicrophone;
    // A quick release can end it before this line.
    if (parts.recorder.recording) {
      _listening = parts.recorder.startedAt;
      notifyListeners();
    }
    return null;
  }

  /// Waits for a start still running. A failed start has told the person already, so this does not throw.
  Future<void> _started() async {
    try {
      await _starting;
    } catch (_) {
      // startVoiceNote returned its message.
    }
  }

  @override
  Future<String?> endVoiceNote() async {
    final parts = voice;
    if (parts == null) return null;
    await _started();
    if (!parts.recorder.recording) return null;
    final recording = await parts.recorder.stop();
    _listening = null;
    notifyListeners();
    if (recording == null) return _holdLonger;
    await _keepVoice(recording);
    return null;
  }

  @override
  Future<void> cancelVoiceNote() async {
    final parts = voice;
    if (parts == null) return;
    await _started();
    await parts.recorder.cancel();
    _listening = null;
    notifyListeners();
  }

  @override
  Future<void> play(String recording) async {
    final parts = voice;
    if (parts == null) return;
    final file = await parts.recorder.fileOf(recording);
    // Phone backups leave recordings out, so a note restored to a new phone has its words but no recording.
    if (!await file.exists()) return notice(_noRecording);
    await parts.player.play(file);
  }

  /// Shows the note at once, with no words yet, and writes them in the background.
  Future<void> _keepVoice(Recording recording) async {
    final note = LocalNote(clientId: recording.clientId, text: '', createdAt: recording.startedAt, kind: NoteKind.voice,
      audioPath: recording.audioPath, durationMs: recording.length.inMilliseconds, wordsPending: true);
    await store.addVoiceNote(note);
    await _refreshLocal();
    _track(_write(note));
  }

  void _track(Future<void> job) {
    _writing.add(job);
    job.whenComplete(() => _writing.remove(job));
  }

  /// Ends when every voice note being written has its words or is gone. Tests wait on it.
  @visibleForTesting
  Future<void> wordsWritten() async {
    while (_writing.isNotEmpty) {
      await Future.wait(List.of(_writing));
    }
  }

  /// Writes the words of each voice note still waiting, oldest first. With [dropStray], deletes recordings no note
  /// keeps, such as one the app's close cut off while the person still held the button.
  Future<void> _writePending({bool dropStray = false}) async {
    final parts = voice;
    if (parts == null) return;
    final pending = await store.pendingWords();
    if (dropStray) {
      final kept = {for (final note in await store.notes()) if (note.audioPath != null) note.audioPath};
      final folder = (await parts.recorder.fileOf(VoiceRecorder.pathOf('x'))).parent;
      if (await folder.exists()) {
        await for (final file in folder.list()) {
          if (file is File && !kept.contains('voice/${file.uri.pathSegments.last}')) await file.delete();
        }
      }
    }
    for (final note in pending) {
      await _write(note);
    }
  }

  /// Writes one voice note's words. No words: the note and its recording go, and the app says it heard no speech.
  /// A note waits, kept, while the model is away or the words fail; the next open tries again.
  Future<void> _write(LocalNote note) async {
    final parts = voice;
    if (parts == null) return;
    final file = await parts.recorder.fileOf(note.audioPath ?? VoiceRecorder.pathOf(note.clientId));
    if (!await file.exists()) {
      await store.dropNote(note.clientId);
      await _refreshLocal();
      return;
    }
    if (parts.model.state != ModelState.ready) return;
    final String words;
    try {
      words = await parts.transcriber.words(file);
    } on Exception {
      return;
    }
    if (words.isEmpty) {
      await store.dropNote(note.clientId);
      await file.delete();
      await _refreshLocal();
      notice(_noSpeech);
      return;
    }
    if (await store.setWords(note.clientId, words, send: _settings.sending)) {
      await _refreshLocal();
      await sync();
    }
  }

  bool _disposed = false;

  // Words written after the app closed its controller change the store only.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _history?.cancel();
    voice?.model.removeListener(notifyListeners);
    super.dispose();
  }
}
