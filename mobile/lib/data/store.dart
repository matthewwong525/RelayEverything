import 'dart:convert';

import 'package:drift/drift.dart';

/// How a note on this phone was made.
enum NoteKind { typed, voice }

/// A note typed or said on this phone. It stays here; it goes to the server only while sending is on.
class LocalNote {
  const LocalNote({required this.clientId, required this.text, required this.createdAt, this.pin, this.sentAt,
    this.queued = false, this.pinning = false, this.kind = NoteKind.typed, this.audioPath, this.durationMs,
    this.wordsPending = false, this.attachments = const []});

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

  /// The note's files, in the order they were added.
  final List<Attachment> attachments;

  /// The body the server's `notes` route takes: a voice note goes as its words, the same as a typed note. A note with
  /// files lists them; their bytes go later, one `attachment` upload each.
  Map<String, dynamic> toJson() => {
    'clientId': clientId, 'text': text, 'createdAt': createdAt.millisecondsSinceEpoch,
    if (pin != null) ...{'lat': pin!.lat, 'lon': pin!.lon, 'accuracy': pin!.accuracy, if (pin!.place != null) 'place': pin!.place},
    if (attachments.isNotEmpty) 'attachments': [for (final file in attachments) file.toJson()],
  };
}

/// One file on a note. The app keeps its own copy at [path], from the app's support folder.
class Attachment {
  const Attachment({required this.id, required this.name, required this.type, required this.size, required this.path,
    this.sentAt});

  final String id;
  final String name;
  final String type;
  final int size;

  /// `attachments/<id><.ext>`, from the app's support folder. The folder's full path can change when the app updates,
  /// so the store keeps this part only.
  final String path;

  /// When the server took the file, or null.
  final DateTime? sentAt;

  bool get picture => type.startsWith('image/');

  /// What the note's upload lists for the file: never its bytes.
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type, 'size': size};

  /// The body of the file's own upload, queued after its note's.
  Map<String, dynamic> upload(String noteClientId) =>
    {'noteClientId': noteClientId, 'id': id, 'path': path, 'name': name, 'type': type};
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

/// When an upload of health, or of location points, last reached the server, in the store's `state`.
const sentHealth = 'sent.health', sentPoints = 'sent.points';

/// One waiting upload: a route and the JSON body to send it.
class OutboxItem {
  const OutboxItem(this.id, this.route, this.body);

  final int id;
  final String route;
  final Map<String, dynamic> body;
}

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
  _attachmentsTable,
];

// A note's files: one row each, in the order they were added. sent_at: when the server took the file.
const _attachmentsTable = 'CREATE TABLE attachments (id TEXT PRIMARY KEY, note_client_id TEXT NOT NULL, name TEXT, type TEXT, '
  'size INTEGER, path TEXT, sent_at INTEGER)';

/// The phone's own SQLite file: its typed and voice notes, waiting uploads, location points not yet sent, and small settings.
/// Written as plain SQL through drift, so the app needs no generated code.
class Store extends GeneratedDatabase {
  Store(super.executor);

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
    // Version 4 had notes with no files.
    if (from < 5) await customStatement(_attachmentsTable);
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
    for (final file in note.attachments) {
      await _run('INSERT INTO attachments (id, note_client_id, name, type, size, path) VALUES (?, ?, ?, ?, ?, ?)',
        [file.id, note.clientId, file.name, file.type, file.size, file.path]);
    }
    if (queue) await _queue(body);
  });

  /// Keeps a note the iPhone's share card made, with no place. [sentAt] is set when the card sent the note already,
  /// and [sentFiles] names the files it sent. With [send], what the card did not send is queued: the note, unless sent,
  /// then each file not sent. False when this phone keeps the note already.
  Future<bool> addSharedNote(LocalNote note, {DateTime? sentAt, Set<String> sentFiles = const {}, required bool send}) =>
    transaction(() async {
      if (await hasNote(note.clientId)) return false;
      final body = note.toJson();
      await _run('INSERT INTO notes (client_id, body, created_at, sent_at, queued) VALUES (?, ?, ?, ?, ?)',
        [note.clientId, jsonEncode(body), note.createdAt.millisecondsSinceEpoch, sentAt?.millisecondsSinceEpoch,
          sentAt != null || send ? 1 : 0]);
      for (final file in note.attachments) {
        final sent = sentFiles.contains(file.id) ? sentAt ?? DateTime.now() : null;
        await _run('INSERT INTO attachments (id, note_client_id, name, type, size, path, sent_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [file.id, note.clientId, file.name, file.type, file.size, file.path, sent?.millisecondsSinceEpoch]);
      }
      if (!send) return true;
      if (sentAt == null) {
        await _queue(body);
      } else {
        for (final file in note.attachments) {
          if (!sentFiles.contains(file.id)) await enqueue('attachment', file.upload(note.clientId));
        }
      }
      return true;
    });

  /// Queues a note's upload, then one upload for each of its files not sent yet, so a file never reaches the server
  /// before its note.
  Future<void> _queue(Map<String, dynamic> body) async {
    final clientId = body['clientId'] as String;
    await enqueue('notes', body);
    for (final file in await attachmentsOf(clientId)) {
      if (file.sentAt == null) await enqueue('attachment', file.upload(clientId));
    }
  }

  /// True when this phone keeps a note with [clientId].
  Future<bool> hasNote(String clientId) async =>
    (await _rows('SELECT 1 FROM notes WHERE client_id = ?', [clientId])).isNotEmpty;

  /// A note's files, in the order they were added.
  Future<List<Attachment>> attachmentsOf(String clientId) async => [
    for (final row in await _rows('SELECT id, name, type, size, path, sent_at FROM attachments WHERE note_client_id = ? '
        'ORDER BY rowid', [clientId]))
      _attachmentOf(row),
  ];

  static Attachment _attachmentOf(QueryRow row) {
    final sentAt = row.read<int?>('sent_at');
    return Attachment(id: row.read<String>('id'), name: row.read<String?>('name') ?? '', type: row.read<String?>('type') ?? '',
      size: row.read<int?>('size') ?? 0, path: row.read<String?>('path') ?? '',
      sentAt: sentAt == null ? null : DateTime.fromMillisecondsSinceEpoch(sentAt));
  }

  /// The server took a file, or turned it down for good: either way it goes no more.
  Future<void> attachmentSent(String id, DateTime at) =>
    _run('UPDATE attachments SET sent_at = ? WHERE id = ?', [at.millisecondsSinceEpoch, id]);

  /// Ends a note's wait for its pin, with the pin when the phone found one. With [send] the note and its upload get the
  /// same body in one step. False when the note is not waiting, such as one settled already.
  Future<bool> settlePin(String clientId, Pin? pin, {required bool send}) => transaction(() async {
    final notes = await _rows('SELECT body FROM notes WHERE client_id = ? AND pinning = 1', [clientId]);
    if (notes.isEmpty) return false;
    final note = _noteOf(jsonDecode(notes.single.read<String>('body')) as Map<String, dynamic>);
    final body = LocalNote(clientId: clientId, text: note.text, createdAt: note.createdAt, pin: pin,
      attachments: note.attachments).toJson();
    await _run('UPDATE notes SET body = ?, pinning = 0, queued = ? WHERE client_id = ?', [jsonEncode(body), send ? 1 : 0, clientId]);
    if (send) await _queue(body);
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
    final body = LocalNote(clientId: clientId, text: text, createdAt: note.createdAt, pin: note.pin,
      attachments: note.attachments).toJson();
    await _run('UPDATE notes SET body = ?, words_pending = 0, queued = ? WHERE client_id = ?', [jsonEncode(body), send ? 1 : 0, clientId]);
    if (send) await _queue(body);
    return true;
  });

  /// Deletes a note that never had words, such as a recording with no speech.
  Future<void> dropNote(String clientId) => transaction(() async {
    await _run('DELETE FROM notes WHERE client_id = ? AND sent_at IS NULL', [clientId]);
    await _run('DELETE FROM attachments WHERE note_client_id = ? AND note_client_id NOT IN (SELECT client_id FROM notes)', [clientId]);
  });

  /// Voice notes still waiting for their words, oldest first.
  Future<List<LocalNote>> pendingWords() async =>
    [for (final note in (await notes()).reversed) if (note.wordsPending) note];

  static const _earlier = 'FROM notes WHERE sent_at IS NULL AND queued = 0 AND pinning = 0 AND words_pending = 0';

  /// How many notes never went to the server and have no upload: the notes the earlier-notes prompt asks about.
  Future<int> earlierCount() async => (await _rows('SELECT count(*) AS n $_earlier')).single.read<int>('n');

  /// Queues every earlier note, oldest first, each with its files.
  Future<void> queueEarlier() => transaction(() async {
    for (final row in await _rows('SELECT client_id, body $_earlier ORDER BY created_at, client_id')) {
      await _queue(jsonDecode(row.read<String>('body')) as Map<String, dynamic>);
      await _run('UPDATE notes SET queued = 1 WHERE client_id = ?', [row.read<String>('client_id')]);
    }
  });

  Future<void> noteSent(String clientId, DateTime at) =>
    _run('UPDATE notes SET sent_at = ? WHERE client_id = ?', [at.millisecondsSinceEpoch, clientId]);

  /// Every note made on this phone, newest first, each with its files.
  Future<List<LocalNote>> notes() async {
    final files = <String, List<Attachment>>{};
    for (final row in await _rows('SELECT note_client_id, id, name, type, size, path, sent_at FROM attachments ORDER BY rowid')) {
      files.putIfAbsent(row.read<String>('note_client_id'), () => []).add(_attachmentOf(row));
    }
    return [
      for (final row in await _rows('SELECT client_id, body, sent_at, queued, pinning, kind, audio_path, duration_ms, words_pending '
          'FROM notes ORDER BY created_at DESC, client_id DESC'))
        _noteOf(jsonDecode(row.read<String>('body')) as Map<String, dynamic>, sentAt: row.read<int?>('sent_at'),
          queued: row.read<int>('queued') == 1, pinning: row.read<int>('pinning') == 1,
          kind: NoteKind.values.byName(row.read<String>('kind')), audioPath: row.read<String?>('audio_path'),
          durationMs: row.read<int?>('duration_ms'), wordsPending: row.read<int>('words_pending') == 1,
          attachments: files[row.read<String>('client_id')]),
    ];
  }

  /// A note's body, with its files listed by the body when the table's rows are not given.
  static LocalNote _noteOf(Map<String, dynamic> body, {int? sentAt, bool queued = false, bool pinning = false,
    NoteKind kind = NoteKind.typed, String? audioPath, int? durationMs, bool wordsPending = false,
    List<Attachment>? attachments}) => LocalNote(
    clientId: body['clientId'] as String, text: body['text'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(body['createdAt'] as int),
    pin: body['lat'] == null ? null : Pin(at: DateTime.fromMillisecondsSinceEpoch(body['createdAt'] as int),
      lat: (body['lat'] as num).toDouble(), lon: (body['lon'] as num).toDouble(),
      accuracy: (body['accuracy'] as num).toDouble(), place: body['place'] as String?),
    sentAt: sentAt == null ? null : DateTime.fromMillisecondsSinceEpoch(sentAt), queued: queued, pinning: pinning,
    kind: kind, audioPath: audioPath, durationMs: durationMs, wordsPending: wordsPending,
    attachments: attachments ?? [
      for (final file in (body['attachments'] as List?) ?? const [])
        Attachment(id: (file as Map)['id'] as String, name: file['name'] as String, type: file['type'] as String,
          size: file['size'] as int, path: ''),
    ],
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

  /// Gives the point kept at [at] its place name, while it waits in the store. A point already queued stays unnamed.
  Future<void> namePoint(DateTime at, String place) =>
    _run("UPDATE points SET body = json_set(body, '\$.place', ?) WHERE at = ?", [place, at.millisecondsSinceEpoch]);

  /// Moves up to [batch] points at a time into the outbox, in time order.
  Future<void> queuePoints({int batch = 500}) => transaction(() async {
    while (true) {
      final rows = await _rows('SELECT at, body FROM points ORDER BY at LIMIT ?', [batch]);
      if (rows.isEmpty) return;
      await enqueue('locations', {'points': [for (final row in rows) jsonDecode(row.read<String>('body'))]});
      await _run('DELETE FROM points WHERE at <= ?', [rows.last.read<int>('at')]);
    }
  });

  /// Health readings waiting to send, in the outbox.
  Future<int> waitingReadings() async => (await _rows(
    "SELECT coalesce(sum(json_array_length(body, '\$.samples')), 0) AS n FROM outbox WHERE route = 'health'")).single.read<int>('n');

  /// Location points waiting to send: in the outbox, and kept but not yet queued.
  Future<int> waitingPoints() async => (await _rows(
    "SELECT coalesce((SELECT sum(json_array_length(body, '\$.points')) FROM outbox WHERE route = 'locations'), 0) "
    '+ (SELECT count(*) FROM points) AS n')).single.read<int>('n');

  /// When [key], [sentHealth] or [sentPoints], was last written, or null for never.
  Future<DateTime?> sentAt(String key) async {
    final value = int.tryParse(await get(key) ?? '');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<String?> get(String key) async {
    final rows = await _rows('SELECT value FROM state WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.single.read<String>('value');
  }

  Future<void> set(String key, String value) => _run('INSERT OR REPLACE INTO state (key, value) VALUES (?, ?)', [key, value]);

  Future<void> remove(String key) => _run('DELETE FROM state WHERE key = ?', [key]);
}
