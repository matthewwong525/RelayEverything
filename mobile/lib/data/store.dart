import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

/// How a note on this phone was made.
enum NoteKind { typed, voice }

/// A note typed or said on this phone. It stays here; it goes to the server only while sending is on.
class LocalNote {
  const LocalNote({required this.clientId, required this.text, required this.createdAt, this.pin, this.sentAt,
    this.queued = false, this.pinning = false, this.kind = NoteKind.typed, this.audioPath, this.durationMs,
    this.wordsPending = false});

  final String clientId;
  final String text;
  final DateTime createdAt;
  final Pin? pin;

  /// When the server took it, or null for a note only on this phone.
  final DateTime? sentAt;

  /// True once the note has its upload: written with sending on, or picked by *Send them*.
  final bool queued;

  /// True while the note waits for the phone's fix.
  final bool pinning;

  final NoteKind kind;

  /// A voice note's recording, from the app's support folder. It never leaves the phone.
  final String? audioPath;
  final int? durationMs;

  /// True while the phone writes a voice note's words. The note gets no upload until it has them.
  final bool wordsPending;

  /// The body the server's `notes` route takes: a voice note goes as its words, the same as a typed note.
  Map<String, dynamic> toJson() => {
    'clientId': clientId, 'text': text, 'createdAt': createdAt.millisecondsSinceEpoch,
    if (pin != null) ...{'lat': pin!.lat, 'lon': pin!.lon, 'accuracy': pin!.accuracy, if (pin!.place != null) 'place': pin!.place},
  };
}

/// Where the phone was: for a note's pin, or one point of location history.
class Pin {
  const Pin({required this.at, required this.lat, required this.lon, required this.accuracy, this.place});

  final DateTime at;
  final double lat;
  final double lon;
  final double accuracy;
  final String? place;

  Map<String, dynamic> toJson() =>
    {'at': at.millisecondsSinceEpoch, 'lat': lat, 'lon': lon, 'accuracy': accuracy, if (place != null) 'place': place};
}

/// Where an upload goes. Only the Relay server today; a later change can add another, such as a webhook.
const relayServer = 'relay-server';

/// One waiting upload: a route and the JSON body to send it.
class OutboxItem {
  const OutboxItem(this.id, this.route, this.body);

  final int id;
  final String route;
  final Map<String, dynamic> body;
}

/// A photo waiting to go: its JPEG copy in the app's support folder, and what the server's `photos` route takes with it.
class QueuedPhoto {
  const QueuedPhoto({required this.clientId, required this.assetId, required this.takenAt, this.lat, this.lon,
    required this.width, required this.height, required this.path});

  /// The phone's own id for this photo, so a resend is stored once.
  final String clientId;
  /// The photo's id in the phone's library.
  final String assetId;
  final DateTime takenAt;
  final double? lat;
  final double? lon;
  /// The JPEG copy's own size, in pixels.
  final int width;
  final int height;
  /// The JPEG copy, under the app's support folder: `photos/<client id>.jpg`.
  final String path;

  /// The upload's text fields. A place goes only whole: both numbers, or neither.
  Map<String, String> get fields => {
    'clientId': clientId, 'takenAt': '${takenAt.millisecondsSinceEpoch}',
    if (lat != null && lon != null) ...{'lat': '$lat', 'lon': '$lon'},
  };
}

/// Where a queued photo's JPEG copy lives, under the app's support folder.
String photoPathOf(String clientId) => 'photos/$clientId.jpg';

const _voiceColumns = "kind TEXT NOT NULL DEFAULT 'typed', audio_path TEXT, duration_ms INTEGER, "
  'words_pending INTEGER NOT NULL DEFAULT 0';

const _schema = [
  'CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, destination TEXT NOT NULL DEFAULT \'$relayServer\', route TEXT NOT NULL, '
    'body TEXT NOT NULL, created_at INTEGER NOT NULL)',
  // queued = 1: the note has its upload. pinning = 1: the note waits for its fix, so no upload can go without its place.
  // words_pending = 1: a voice note still waits for its words, so no upload can go without them.
  'CREATE TABLE notes (client_id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER NOT NULL, sent_at INTEGER, '
    'queued INTEGER NOT NULL DEFAULT 0, pinning INTEGER NOT NULL DEFAULT 0, $_voiceColumns)',
  'CREATE TABLE points (at INTEGER PRIMARY KEY, body TEXT NOT NULL)',
  'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  _photosTable,
];

// Photos wait here, not in the outbox: the outbox stops at the first upload that can not go, so a photo waiting for
// Wi-Fi would hold back every note.
const _photosTable = 'CREATE TABLE photos (client_id TEXT PRIMARY KEY, asset_id TEXT NOT NULL, taken_at INTEGER NOT NULL, '
  'lat REAL, lon REAL, width INTEGER NOT NULL, height INTEGER NOT NULL, path TEXT NOT NULL, created_at INTEGER NOT NULL)';

/// The phone's own SQLite file: its typed and voice notes, waiting uploads, location points not yet sent, photos
/// waiting to go, and small settings. Written as plain SQL through drift, so the app needs no generated code. A
/// waiting photo's JPEG copy lives in [folder], the app's support folder unless a test gives its own.
class Store extends GeneratedDatabase {
  Store(super.executor, {Future<Directory> Function()? folder}) : _folder = folder ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _folder;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (_) async {
    for (final statement in _schema) {
      await customStatement(statement);
    }
  }, onUpgrade: (_, from, to) async {
    // Version 1 queued every note as it was kept.
    if (from < 2) await customStatement('ALTER TABLE notes ADD COLUMN queued INTEGER NOT NULL DEFAULT 1');
    // Version 2 sent every note, and marked one waiting for its pin with queued = 0.
    if (from < 3) {
      for (final statement in [
        "ALTER TABLE outbox ADD COLUMN destination TEXT NOT NULL DEFAULT '$relayServer'",
        'ALTER TABLE notes ADD COLUMN sent_at INTEGER',
        'ALTER TABLE notes ADD COLUMN pinning INTEGER NOT NULL DEFAULT 0',
        'UPDATE notes SET sent_at = created_at WHERE sent = 1',
        'UPDATE notes SET pinning = 1 WHERE queued = 0 AND sent = 0',
        'ALTER TABLE notes DROP COLUMN sent',
      ]) {
        await customStatement(statement);
      }
    }
    // Version 3 had typed notes only.
    if (from < 4) {
      for (final column in _voiceColumns.split(', ')) {
        await customStatement('ALTER TABLE notes ADD COLUMN $column');
      }
    }
    // Version 4 had no photos.
    if (from < 5) await customStatement(_photosTable);
  });

  Future<List<QueryRow>> _rows(String sql, [List<Object?> values = const []]) =>
    customSelect(sql, variables: [for (final value in values) Variable(value)]).get();

  Future<void> _run(String sql, [List<Object?> values = const []]) => customStatement(sql, values);

  Future<void> enqueue(String route, Map<String, dynamic> body, {String destination = relayServer}) =>
    _run('INSERT INTO outbox (destination, route, body, created_at) VALUES (?, ?, ?, ?)',
      [destination, route, jsonEncode(body), DateTime.now().millisecondsSinceEpoch]);

  /// Every waiting upload for [destination], oldest first.
  Future<List<OutboxItem>> outbox({String destination = relayServer}) async => [
    for (final row in await _rows('SELECT id, route, body FROM outbox WHERE destination = ? ORDER BY id', [destination]))
      OutboxItem(row.read<int>('id'), row.read<String>('route'), jsonDecode(row.read<String>('body')) as Map<String, dynamic>),
  ];

  /// Waiting uploads, and notes that wait for their pin.
  Future<int> waiting() async => (await _rows(
    'SELECT (SELECT count(*) FROM outbox) + (SELECT count(*) FROM notes WHERE pinning = 1) AS n')).single.read<int>('n');

  Future<void> done(int id) => _run('DELETE FROM outbox WHERE id = ?', [id]);

  /// Keeps the note, and with [send] queues its upload in the same step. With [waitForPin] the note is kept and shown,
  /// but gets its upload only from [settlePin], so a sync meanwhile can not send it bare.
  Future<void> addNote(LocalNote note, {bool waitForPin = false, bool send = false}) => transaction(() async {
    final body = note.toJson();
    final queue = send && !waitForPin;
    await _run('INSERT INTO notes (client_id, body, created_at, queued, pinning) VALUES (?, ?, ?, ?, ?)',
      [note.clientId, jsonEncode(body), note.createdAt.millisecondsSinceEpoch, queue ? 1 : 0, waitForPin ? 1 : 0]);
    if (queue) await enqueue('notes', body);
  });

  /// Ends a note's wait for its pin, with the pin when the phone found one. With [send] the note and its upload get the
  /// same body in one step. False when the note is not waiting, such as one settled already.
  Future<bool> settlePin(String clientId, Pin? pin, {required bool send}) => transaction(() async {
    final notes = await _rows('SELECT body FROM notes WHERE client_id = ? AND pinning = 1', [clientId]);
    if (notes.isEmpty) return false;
    final note = _noteOf(jsonDecode(notes.single.read<String>('body')) as Map<String, dynamic>);
    final body = LocalNote(clientId: clientId, text: note.text, createdAt: note.createdAt, pin: pin).toJson();
    await _run('UPDATE notes SET body = ?, pinning = 0, queued = ? WHERE client_id = ?', [jsonEncode(body), send ? 1 : 0, clientId]);
    if (send) await enqueue('notes', body);
    return true;
  });

  /// Settles, without a place, each note whose wait for a pin the app's close cut short.
  Future<void> settleWaiting({required bool send}) async {
    for (final row in await _rows('SELECT client_id FROM notes WHERE pinning = 1 ORDER BY created_at')) {
      await settlePin(row.read<String>('client_id'), null, send: send);
    }
  }

  /// Keeps a voice note at once, with no words yet and no upload: [setWords] gives it both.
  Future<void> addVoiceNote(LocalNote note) =>
    _run('INSERT INTO notes (client_id, body, created_at, kind, audio_path, duration_ms, words_pending) VALUES (?, ?, ?, ?, ?, ?, 1)',
      [note.clientId, jsonEncode(note.toJson()), note.createdAt.millisecondsSinceEpoch, NoteKind.voice.name, note.audioPath,
        note.durationMs]);

  /// Gives a voice note its words, and with [send] its upload in the same step. False when the note is gone or has
  /// its words already.
  Future<bool> setWords(String clientId, String text, {required bool send}) => transaction(() async {
    final notes = await _rows('SELECT body FROM notes WHERE client_id = ? AND words_pending = 1', [clientId]);
    if (notes.isEmpty) return false;
    final note = _noteOf(jsonDecode(notes.single.read<String>('body')) as Map<String, dynamic>);
    final body = LocalNote(clientId: clientId, text: text, createdAt: note.createdAt, pin: note.pin).toJson();
    await _run('UPDATE notes SET body = ?, words_pending = 0, queued = ? WHERE client_id = ?', [jsonEncode(body), send ? 1 : 0, clientId]);
    if (send) await enqueue('notes', body);
    return true;
  });

  /// Deletes a note that never had words, such as a recording with no speech.
  Future<void> dropNote(String clientId) => _run('DELETE FROM notes WHERE client_id = ? AND sent_at IS NULL', [clientId]);

  /// Voice notes still waiting for their words, oldest first.
  Future<List<LocalNote>> pendingWords() async =>
    [for (final note in (await notes()).reversed) if (note.wordsPending) note];

  static const _earlier = 'FROM notes WHERE sent_at IS NULL AND queued = 0 AND pinning = 0 AND words_pending = 0';

  /// How many notes never went to the server and have no upload: the notes the earlier-notes prompt asks about.
  Future<int> earlierCount() async => (await _rows('SELECT count(*) AS n $_earlier')).single.read<int>('n');

  /// Queues every earlier note, oldest first.
  Future<void> queueEarlier() => transaction(() async {
    for (final row in await _rows('SELECT client_id, body $_earlier ORDER BY created_at, client_id')) {
      await enqueue('notes', jsonDecode(row.read<String>('body')) as Map<String, dynamic>);
      await _run('UPDATE notes SET queued = 1 WHERE client_id = ?', [row.read<String>('client_id')]);
    }
  });

  Future<void> noteSent(String clientId, DateTime at) =>
    _run('UPDATE notes SET sent_at = ? WHERE client_id = ?', [at.millisecondsSinceEpoch, clientId]);

  /// Every note made on this phone, newest first.
  Future<List<LocalNote>> notes() async => [
    for (final row in await _rows('SELECT body, sent_at, queued, pinning, kind, audio_path, duration_ms, words_pending FROM notes '
        'ORDER BY created_at DESC, client_id DESC'))
      _noteOf(jsonDecode(row.read<String>('body')) as Map<String, dynamic>, sentAt: row.read<int?>('sent_at'),
        queued: row.read<int>('queued') == 1, pinning: row.read<int>('pinning') == 1,
        kind: NoteKind.values.byName(row.read<String>('kind')), audioPath: row.read<String?>('audio_path'),
        durationMs: row.read<int?>('duration_ms'), wordsPending: row.read<int>('words_pending') == 1),
  ];

  static LocalNote _noteOf(Map<String, dynamic> body, {int? sentAt, bool queued = false, bool pinning = false,
    NoteKind kind = NoteKind.typed, String? audioPath, int? durationMs, bool wordsPending = false}) => LocalNote(
    clientId: body['clientId'] as String, text: body['text'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(body['createdAt'] as int),
    pin: body['lat'] == null ? null : Pin(at: DateTime.fromMillisecondsSinceEpoch(body['createdAt'] as int),
      lat: (body['lat'] as num).toDouble(), lon: (body['lon'] as num).toDouble(),
      accuracy: (body['accuracy'] as num).toDouble(), place: body['place'] as String?),
    sentAt: sentAt == null ? null : DateTime.fromMillisecondsSinceEpoch(sentAt), queued: queued, pinning: pinning,
    kind: kind, audioPath: audioPath, durationMs: durationMs, wordsPending: wordsPending,
  );

  /// Drops the health and location that did not go yet, for when sending turns off. Note uploads stay, so a later
  /// turn-on sends them with no second prompt.
  Future<void> dropReadings() => transaction(() async {
    await _run("DELETE FROM outbox WHERE route IN ('health', 'locations')");
    await _run('DELETE FROM points');
  });

  /// One point of location history; a second at the same moment is the same point.
  Future<void> addPoint(Pin point) =>
    _run('INSERT OR IGNORE INTO points (at, body) VALUES (?, ?)', [point.at.millisecondsSinceEpoch, jsonEncode(point.toJson())]);

  /// Moves up to [batch] points at a time into the outbox, in time order.
  Future<void> queuePoints({int batch = 500}) => transaction(() async {
    while (true) {
      final rows = await _rows('SELECT at, body FROM points ORDER BY at LIMIT ?', [batch]);
      if (rows.isEmpty) return;
      await enqueue('locations', {'points': [for (final row in rows) jsonDecode(row.read<String>('body'))]});
      await _run('DELETE FROM points WHERE at <= ?', [rows.last.read<int>('at')]);
    }
  });

  /// The file of a waiting photo's JPEG copy, from its [path] under the app's support folder.
  Future<File> photoFile(String path) async => File('${(await _folder()).path}/$path');

  /// Keeps a photo waiting to go, and saves each of [state] in the same step. Its JPEG copy is at [QueuedPhoto.path]
  /// already.
  Future<void> addPhoto(QueuedPhoto photo, {Map<String, String> state = const {}}) => transaction(() async {
    await _run('INSERT INTO photos (client_id, asset_id, taken_at, lat, lon, width, height, path, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [photo.clientId, photo.assetId, photo.takenAt.millisecondsSinceEpoch, photo.lat, photo.lon, photo.width, photo.height,
        photo.path, DateTime.now().millisecondsSinceEpoch]);
    for (final MapEntry(:key, :value) in state.entries) {
      await set(key, value);
    }
  });

  /// Every photo waiting to go, oldest first.
  Future<List<QueuedPhoto>> waitingPhotos() async => [
    for (final row in await _rows('SELECT client_id, asset_id, taken_at, lat, lon, width, height, path FROM photos '
        'ORDER BY taken_at, created_at, client_id'))
      QueuedPhoto(clientId: row.read<String>('client_id'), assetId: row.read<String>('asset_id'),
        takenAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('taken_at')), lat: row.read<double?>('lat'),
        lon: row.read<double?>('lon'), width: row.read<int>('width'), height: row.read<int>('height'), path: row.read<String>('path')),
  ];

  /// Ends a photo's wait, once it went or the server turned it down: its row and its JPEG copy go.
  Future<void> photoDone(String clientId) async {
    final rows = await _rows('SELECT path FROM photos WHERE client_id = ?', [clientId]);
    await _run('DELETE FROM photos WHERE client_id = ?', [clientId]);
    for (final row in rows) {
      await _delete(row.read<String>('path'));
    }
  }

  /// Drops every photo that did not go yet, with its JPEG copy, for when photos or sending turns off.
  Future<void> dropPhotos() async {
    final rows = await _rows('SELECT path FROM photos');
    await _run('DELETE FROM photos');
    for (final row in rows) {
      await _delete(row.read<String>('path'));
    }
  }

  Future<void> _delete(String path) async {
    final file = await photoFile(path);
    if (await file.exists()) await file.delete();
  }

  Future<String?> get(String key) async {
    final rows = await _rows('SELECT value FROM state WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.single.read<String>('value');
  }

  Future<void> set(String key, String value) => _run('INSERT OR REPLACE INTO state (key, value) VALUES (?, ?)', [key, value]);

  Future<void> remove(String key) => _run('DELETE FROM state WHERE key = ?', [key]);
}
