import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'data/api.dart';
import 'data/connection.dart';
import 'data/outbox.dart';
import 'data/sender.dart';
import 'data/settings.dart';
import 'data/store.dart';
import 'relay.dart';
import 'sync/health.dart';
import 'sync/location.dart';

const _cacheKey = 'timeline';

/// A random id for a typed note, so a resend is stored once.
String newClientId([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(16, (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// The app's one Relay: notes in the store, and the key in the vault. Notes stay on this phone; while sending is on,
/// it syncs on open, on a new note, on pull, and every hour in the background.
class RelayController extends Relay {
  RelayController({required this.store, required this.vault, required this.places, required this.health,
    RelayApi Function(Connection)? apiFor, DateTime Function()? clock, this.schedule})
    : _sender = Sender(apiFor), _clock = clock ?? DateTime.now;

  final Store store;
  final KeyVault vault;
  final Places places;
  final HealthSource health;
  /// Turns the hourly background sync on or off.
  final Future<void> Function(bool on)? schedule;
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
    await _refreshLocal();
  }

  static Entry _entryOf(RemoteNote note) => Entry(text: note.text, ring: note.source == 'ring', at: note.recordedAt,
    place: note.place, device: note.device, audio: note.audio);

  // A typed note on the server is the same note when its time and words match: the timeline does not give its clientId.
  static String _sameAs(DateTime at, String text) => '${at.millisecondsSinceEpoch} $text';

  Entry _entryOfLocal(LocalNote note) => Entry(text: note.text, ring: false, at: note.createdAt,
    // With sending off the phone looks up no place name, so a pin with no name reads as Pinned.
    place: note.pin == null ? null : note.pin!.place ?? 'Pinned',
    waiting: _settings.sending && note.sentAt == null && (note.queued || note.pinning));

  Future<void> _refreshLocal() async {
    _notes = await store.notes();
    _waiting = await store.waiting();
    _merge();
  }

  /// This phone's notes beside the server's, newest first; a note on both shows once, as the server has it.
  void _merge() {
    final onServer = {for (final entry in _server) if (!entry.ring) _sameAs(entry.at, entry.text)};
    final local = [for (final note in _notes) if (note.sentAt == null || !onServer.contains(_sameAs(note.createdAt, note.text))) _entryOfLocal(note)];
    final merged = <Entry>[];
    var l = 0, s = 0;
    while (l < local.length || s < _server.length) {
      final takeLocal = s == _server.length || (l < local.length && !local[l].at.isBefore(_server[s].at));
      merged.add(takeLocal ? local[l++] : _server[s++]);
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

  @override
  void dispose() {
    _history?.cancel();
    super.dispose();
  }
}
