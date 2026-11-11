import 'dart:convert';
import 'dart:io';

import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../sync/stays.dart';
import 'settings.dart';

/// How a note on this phone was made.
enum NoteKind { typed, voice }

/// A note typed or said on this phone. It stays here; it goes to the server only while sending is on. It keeps no
/// place: where the phone was goes into location history, at the note's time.
class LocalNote {
  const LocalNote({required this.clientId, required this.text, required this.createdAt, this.sentAt,
    this.queued = false, this.kind = NoteKind.typed, this.audioPath, this.durationMs,
    this.wordsPending = false, this.attachments = const [], this.editedAt, this.serverId, this.device, this.mine = true,
    this.fromWatch = false});

  final String clientId;
  final String text;
  final DateTime createdAt;

  /// When the server took it, or null for a note only on this phone.
  final DateTime? sentAt;

  /// True once the note has its upload: written with sending on, or picked by *Send them*.
  final bool queued;

  final NoteKind kind;

  /// A voice note's recording, from the app's support folder. It never leaves the phone.
  final String? audioPath;
  final int? durationMs;

  /// True while the phone writes a voice note's words. The note gets no upload until it has them.
  final bool wordsPending;

  /// The note's files, in the order they were added.
  final List<Attachment> attachments;

  /// When the person last changed the note's words or files, or null for never.
  final DateTime? editedAt;

  /// The server's id for the note, once a pull read it.
  final String? serverId;

  /// Where the note was made, as the server names it, such as `Email` or another phone.
  final String? device;

  /// False for a note from elsewhere, which only a pull brings: sign-out deletes it.
  final bool mine;

  /// True for a voice note the person's Apple Watch handed over. It stays on this phone only: the server never gets it.
  final bool fromWatch;

  /// True for a watch note in which the phone found no words: it keeps its recording, waits for nothing, and is not
  /// sent until the person writes words in it. Its SQL twin is [Store]'s `_noWords`.
  bool get noWords => fromWatch && kind == NoteKind.voice && !wordsPending && text.isEmpty;

  /// The body the server's `notes` route takes: a voice note goes as its words, the same as a typed note. A note with
  /// files lists them; their bytes go later, one `attachment` upload each.
  Map<String, dynamic> toJson() => {
    'clientId': clientId, 'text': text, 'createdAt': createdAt.millisecondsSinceEpoch,
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

/// Where the phone was: one point of location history.
class Pin {
  const Pin({required this.at, required this.lat, required this.lon, required this.accuracy, this.place});

  final DateTime at;
  final double lat;
  final double lon;
  final double accuracy;
  final String? place;

  Map<String, dynamic> toJson() =>
    {'at': at.millisecondsSinceEpoch, 'lat': lat, 'lon': lon, 'accuracy': accuracy, if (place != null) 'place': place};

  factory Pin.fromJson(Map<String, dynamic> json) => Pin(at: DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
    lat: (json['lat'] as num).toDouble(), lon: (json['lon'] as num).toDouble(), accuracy: (json['accuracy'] as num).toDouble(),
    place: json['place'] as String?);
}

/// The route of a sent note's change: `PATCH notes` on the server, `note.updated` to a webhook.
const noteUpdate = 'note.update';

/// The route of a sent note's delete: `DELETE notes` on the server, `note.deleted` to a webhook.
const noteDelete = 'note.delete';

/// Where an upload goes: the person's Relay Everything server, or their own webhook. Each waiting upload keeps one.
const relayServer = 'relay-server', ownWebhook = 'webhook';

/// The outbox destination for [place].
String destinationOf(SendPlace place) => place == SendPlace.webhook ? ownWebhook : relayServer;

/// The `state` keys: the destination new uploads take, the destination new [privateRoutes] uploads take, this install's
/// own id, and the next health or point id.
const _destination = 'outbox.destination', _private = 'outbox.private', _installId = 'install.id', _nextId = 'ids.next';

/// The routes of the person's private data: health, nights, location points, stays and trips, and calendar events. They
/// may go to another place than notes, the person's own webhook.
const privateRoutes = {'health', nightsRoute, 'locations', 'stays', 'calendar'};
final _privateList = privateRoutes.map((route) => "'$route'").join(', ');

/// The last change number a pull of notes read, in the store's `state`: the next pull asks for the changes after it.
const noteSyncSeq = 'note_sync_seq';

/// A ring note's recording shows as a file of its note with this id prefix and the note's server id.
const recordingPrefix = 'audio:';

/// When an upload of health, of location points, or of calendar events last reached the server, in the store's `state`.
const sentHealth = 'sent.health', sentPoints = 'sent.points', sentCalendar = 'sent.calendar';

/// The open stay or trip, in the store's `state`: lib/sync/stays.dart's [TimelineState]. Not `timeline`, which the first
/// versions used for the server's timeline and which the app deletes at each open.
const timelineKey = 'stays.timeline';

/// The outbox route of stays and trips: `POST stays` on the server, `location.stays` to a webhook.
const staysRoute = 'stays';

/// The outbox route of nights: `POST nights` on the server, `health.nights` to a webhook.
const nightsRoute = 'nights';

/// lib/sync/health.dart's list of the nights and sleep and workout samples queued lately, and its 90-day redo mark, in
/// the store's `state`. Sending turned off forgets both; a new private place forgets the list.
const healthSent = 'health.sent', healthDetail = 'health.detail';

/// One waiting upload: a route and the JSON body to send it, where it goes, and when the phone queued it.
class OutboxItem {
  const OutboxItem(this.id, this.route, this.body, {required this.destination, required this.createdAt, this.raw});

  final int id;
  final String route;
  final Map<String, dynamic> body;
  final String destination;
  final DateTime createdAt;

  /// [body] as the store keeps it, so [Store.finish] sees a change made while it went.
  final String? raw;
}

/// A photo waiting to go: its JPEG copy in the app's support folder, and what the server's `photos` route takes with it.
class QueuedPhoto {
  const QueuedPhoto({required this.clientId, required this.assetId, required this.takenAt, this.lat, this.lon,
    required this.width, required this.height, required this.path, this.queuedAt});

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
  /// When the phone queued it: a webhook message's `timestamp`. The store sets it.
  final DateTime? queuedAt;

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

// mine = 0: a note from elsewhere, which a pull brought. SQLite can not add a UNIQUE column, so an index keeps
// server_id unique. edit_unsent = 1: this phone kept a change to the note and queued no upload for it, as with sending
// off, so the server never got it. The edit time can not say so: the server keeps a fast phone's edit at its own now.
const _syncColumns = 'server_id TEXT, device TEXT, mine INTEGER NOT NULL DEFAULT 1, edit_unsent INTEGER NOT NULL DEFAULT 0';
const _serverIdIndex = 'CREATE UNIQUE INDEX notes_server_id ON notes (server_id)';

// deleting_at: when the person deleted the note. It is hidden, and still here for *Undo*, until its delete runs.
const _deletingColumn = 'deleting_at INTEGER';

// source: 'watch' for a voice note the Apple Watch handed over, else null. It is not in the body, which is the upload.
const _sourceColumn = 'source TEXT';

const _schema = [
  'CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, destination TEXT NOT NULL DEFAULT \'$relayServer\', route TEXT NOT NULL, '
    'body TEXT NOT NULL, created_at INTEGER NOT NULL)',
  // queued = 1: the note has its upload. pinning: unused since version 12, when a note stopped keeping a place.
  // words_pending = 1: a voice note still waits for its words, so no upload can go without them.
  'CREATE TABLE notes (client_id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER NOT NULL, sent_at INTEGER, '
    'queued INTEGER NOT NULL DEFAULT 0, pinning INTEGER NOT NULL DEFAULT 0, $_voiceColumns, edited_at INTEGER, $_syncColumns, '
    '$_deletingColumn, $_sourceColumn)',
  _serverIdIndex,
  'CREATE TABLE points (at INTEGER PRIMARY KEY, body TEXT NOT NULL)',
  'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  _attachmentsTable,
  _calendarSentTable,
  _photosTable,
  _trackTable,
  _motionsTable,
];

// The open stay or trip's points and motion changes, by time: lib/sync/stays.dart works them out. Rows go once the
// stay or trip ends, and all of them when sending or location history turns off.
const _trackTable = 'CREATE TABLE track (at INTEGER PRIMARY KEY, body TEXT NOT NULL)';
const _motionsTable = 'CREATE TABLE motions (at INTEGER PRIMARY KEY, body TEXT NOT NULL)';

// A note's files: one row each, in the order they were added. sent_at: when the server took the file. path is null for
// a file from elsewhere until the person opens it.
const _attachmentsTable = 'CREATE TABLE attachments (id TEXT PRIMARY KEY, note_client_id TEXT NOT NULL, name TEXT, type TEXT, '
  'size INTEGER, path TEXT, sent_at INTEGER)';

// Each calendar event sent, by its key, with the SHA-256 of what was sent: a round sends only what changed.
const _calendarSentTable = 'CREATE TABLE calendar_sent (key TEXT PRIMARY KEY, hash TEXT NOT NULL)';

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
  int get schemaVersion => 13;

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
    // Version 5 had no calendar.
    if (from < 6) await customStatement(_calendarSentTable);
    // Version 6 had no photos.
    if (from < 7) await customStatement(_photosTable);
    // Version 7 could not change a note.
    if (from < 8) await customStatement('ALTER TABLE notes ADD COLUMN edited_at INTEGER');
    // Version 8 had only this phone's notes.
    if (from < 9) {
      for (final column in _syncColumns.split(', ')) {
        await customStatement('ALTER TABLE notes ADD COLUMN $column');
      }
      await customStatement(_serverIdIndex);
    }
    // Version 9 could not delete a note, and its pulls left out deleted notes: the next pull starts again from 0.
    if (from < 10) {
      await customStatement('ALTER TABLE notes ADD COLUMN $_deletingColumn');
      await customStatement("DELETE FROM state WHERE key = '$noteSyncSeq'");
    }
    // Version 10 sent points only, with no stays or trips.
    if (from < 11) {
      await customStatement(_trackTable);
      await customStatement(_motionsTable);
    }
    // Version 11 kept a place on a note: it moves into location history.
    if (from < 12) await _movePins();
    // Version 12 did not know which notes came from the watch.
    if (from < 13) await customStatement('ALTER TABLE notes ADD COLUMN $_sourceColumn');
  });

  /// A note keeps no place: each unsent note's place becomes one location point at its time while location history is
  /// on, every note and waiting upload loses its place, and a note that waited for its fix gets its upload.
  Future<void> _movePins() => transaction(() async {
    // A store with no sending setting is the first version's, which sent everything with its key.
    final settings = Settings.decode(await get(settingsKey), hasKey: true);
    final place = "json_extract(body, '\$.lat') IS NOT NULL";
    if (settings.history) {
      for (final row in await _rows('SELECT body FROM notes WHERE sent_at IS NULL AND $place')) {
        final body = jsonDecode(row.read<String>('body')) as Map<String, dynamic>;
        await addPoint(Pin(at: DateTime.fromMillisecondsSinceEpoch(body['createdAt'] as int), lat: (body['lat'] as num).toDouble(),
          lon: (body['lon'] as num).toDouble(), accuracy: (body['accuracy'] as num?)?.toDouble() ?? 0,
          place: body['place'] as String?), send: settings.locationSend);
      }
    }
    const placeless = "json_remove(body, '\$.lat', '\$.lon', '\$.accuracy', '\$.place')";
    await _run('UPDATE notes SET body = $placeless WHERE $place');
    await _run("UPDATE outbox SET body = $placeless WHERE route IN ('notes', '$noteUpdate') AND $place");
    for (final row in await _rows('SELECT body, words_pending FROM notes WHERE pinning = 1')) {
      final body = jsonDecode(row.read<String>('body')) as Map<String, dynamic>;
      final queue = settings.sending && row.read<int>('words_pending') == 0;
      await _run('UPDATE notes SET pinning = 0, queued = ? WHERE client_id = ?', [queue ? 1 : 0, body['clientId']]);
      if (queue) await _queue(body);
    }
  });

  Future<List<QueryRow>> _rows(String sql, [List<Object?> values = const []]) =>
    customSelect(sql, variables: [for (final value in values) Variable(value)]).get();

  Future<void> _run(String sql, [List<Object?> values = const []]) => customStatement(sql, values);

  /// Queues one upload. With no [destination] it takes the current one for its route, read in the same statement, so an
  /// upload never lands on the place the person just left: the private destination for [privateRoutes], else the notes
  /// destination. A store from before the private destination has none, so its private uploads take the notes one.
  Future<void> enqueue(String route, Map<String, dynamic> body, {String? destination}) =>
    _run("INSERT INTO outbox (destination, route, body, created_at) VALUES (coalesce(?, "
      "(SELECT value FROM state WHERE key = CASE WHEN ? IN ($_privateList) THEN '$_private' END), "
      "(SELECT value FROM state WHERE key = '$_destination'), '$relayServer'), ?, ?, ?)",
      [destination, route, route, jsonEncode(body), DateTime.now().millisecondsSinceEpoch]);

  /// Every waiting upload, or those for [destination], oldest first. With [private] true only the [privateRoutes]
  /// uploads, with false only the others, the notes and their changes, deletes and files.
  Future<List<OutboxItem>> outbox({String? destination, bool? private}) async {
    final where = [
      if (destination != null) 'destination = ?',
      if (private != null) 'route ${private ? '' : 'NOT '}IN ($_privateList)',
    ];
    return [
      for (final row in await _rows('SELECT id, destination, route, body, created_at FROM outbox '
          '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}ORDER BY id', [?destination])) _outboxItem(row),
    ];
  }

  /// The waiting upload [id] as it is now, or null when it is gone.
  Future<OutboxItem?> outboxItem(int id) async {
    final rows = await _rows('SELECT id, destination, route, body, created_at FROM outbox WHERE id = ?', [id]);
    return rows.isEmpty ? null : _outboxItem(rows.single);
  }

  static OutboxItem _outboxItem(QueryRow row) => OutboxItem(row.read<int>('id'), row.read<String>('route'),
    jsonDecode(row.read<String>('body')) as Map<String, dynamic>, destination: row.read<String>('destination'),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at')), raw: row.read<String>('body'));

  /// The destination new uploads take.
  Future<String> destination() async => await get(_destination) ?? relayServer;

  /// The destination new [privateRoutes] uploads take; with none kept, as in a store from before it, the notes one.
  Future<String> privateDestination() async => await get(_private) ?? await destination();

  /// Sends every waiting upload, and each new one, to [destination], and the [privateRoutes] ones to [private], or to
  /// [destination] with none given, in one step. Points queued before they had ids get them here, as a webhook message
  /// needs them. A new private place has none of the calendar, so the phone forgets what went and the
  /// next read sends the whole window there. It also forgets when health, points and the calendar last sent, so a
  /// folder never says *Sent to your webhook* for a send that went to the server.
  Future<void> moveOutbox(String destination, {String? private}) => transaction(() async {
    final privateTo = private ?? destination;
    if (await privateDestination() != privateTo) {
      await _dropCalendar();
      for (final key in [sentHealth, sentPoints, sentCalendar, healthSent]) {
        await remove(key);
      }
    }
    await set(_destination, destination);
    await set(_private, privateTo);
    // Samples, nights and stays carry no ids: a webhook message makes each from the install id and its own fields.
    for (final row in await _rows("SELECT id, body FROM outbox WHERE route = 'locations'")) {
      final body = jsonDecode(row.read<String>('body')) as Map<String, dynamic>;
      final items = [for (final item in body['points'] as List) item as Map<String, dynamic>];
      final missing = items.where((item) => item['id'] == null).toList();
      if (missing.isEmpty) continue;
      var id = await _takeIds(missing.length);
      for (final item in missing) {
        item['id'] = id++;
      }
      await _run('UPDATE outbox SET body = ? WHERE id = ?', [jsonEncode(body), row.read<int>('id')]);
    }
    await _run('UPDATE outbox SET destination = ? WHERE route NOT IN ($_privateList)', [destination]);
    await _run('UPDATE outbox SET destination = ? WHERE route IN ($_privateList)', [privateTo]);
  });

  /// This install's own id, a UUID made once: a webhook message names the phone by it.
  Future<String> installId() => transaction(() async {
    final kept = await get(_installId);
    if (kept != null) return kept;
    final made = newUuid();
    await set(_installId, made);
    return made;
  });

  /// The first of [count] new ids for points, unique on this phone. Run it inside a transaction.
  Future<int> _takeIds(int count) async {
    final first = int.tryParse(await get(_nextId) ?? '') ?? 1;
    await set(_nextId, '${first + count}');
    return first;
  }

  /// Queues health readings, 500 to a batch. They carry no ids: a webhook message makes each from its type, start, end
  /// and source, so a reading the 90-day redo sends again keeps its id.
  Future<void> queueSamples(List<Map<String, dynamic>> samples) => transaction(() async {
    for (var at = 0; at < samples.length; at += 500) {
      await enqueue('health', {'samples': samples.sublist(at, min(at + 500, samples.length))});
    }
  });

  /// Queues [nights], 30 to a batch, so 30 full timelines stay under the server's 1 MB. They carry no ids: a webhook
  /// message makes each from its source and start.
  Future<void> queueNights(List<Map<String, dynamic>> nights) => transaction(() async {
    for (var at = 0; at < nights.length; at += 30) {
      await enqueue(nightsRoute, {'nights': nights.sublist(at, min(at + 30, nights.length))});
    }
  });

  /// Waiting uploads.
  Future<int> waiting() async => (await _rows('SELECT count(*) AS n FROM outbox')).single.read<int>('n');

  Future<void> done(int id) => _run('DELETE FROM outbox WHERE id = ?', [id]);

  /// Ends an upload that went. One whose body changed while it went stays: a note's upload turns into its change, as
  /// the server has the old words.
  Future<void> finish(OutboxItem item) => transaction(() async {
    final rows = await _rows('SELECT body FROM outbox WHERE id = ?', [item.id]);
    if (rows.isEmpty) return;
    if (item.raw == null || rows.single.read<String>('body') == item.raw) return done(item.id);
    if (item.route == 'notes') await _run("UPDATE outbox SET route = '$noteUpdate' WHERE id = ?", [item.id]);
  });

  /// Keeps the person's change to a note: its new [text], and [files] added. A note not sent yet changes its waiting
  /// upload, or none; a sent note with [send] gets one change upload, and a change still waiting takes the new words.
  /// New files' uploads go after. False when nothing changed, or the note is gone or waits for its words.
  /// A note changes by its server id once a pull saved one, and a note from elsewhere's new files stay on this phone.
  /// A watch note with no words that gets words, with [send], gets its upload, as a note kept with sending on.
  Future<bool> editNote(String clientId, String text, {List<Attachment> files = const [], required bool send,
    required DateTime at}) => transaction(() async {
    final notes = await _rows('SELECT body, sent_at, server_id, mine, queued, kind, source FROM notes '
      'WHERE client_id = ? AND words_pending = 0', [clientId]);
    if (notes.isEmpty) return false;
    final row = notes.single;
    final old = _noteOf(jsonDecode(row.read<String>('body')) as Map<String, dynamic>, kind: NoteKind.values.byName(row.read<String>('kind')),
      fromWatch: row.read<String?>('source') == 'watch');
    if (old.text == text && files.isEmpty) return false;
    for (final file in files) {
      await _run('INSERT INTO attachments (id, note_client_id, name, type, size, path) VALUES (?, ?, ?, ?, ?, ?)',
        [file.id, clientId, file.name, file.type, file.size, file.path]);
    }
    final body = LocalNote(clientId: clientId, text: text, createdAt: old.createdAt,
      attachments: await attachmentsOf(clientId)).toJson();
    final mine = notes.single.read<int>('mine') == 1;
    final change = _changeOf(body, at.millisecondsSinceEpoch, serverId: notes.single.read<String?>('server_id'), mine: mine);
    await _run('UPDATE notes SET body = ?, edited_at = ?, edit_unsent = 0 WHERE client_id = ?',
      [jsonEncode(body), at.millisecondsSinceEpoch, clientId]);
    final waiting = await _rows("SELECT id, route FROM outbox WHERE route IN ('notes', '$noteUpdate') "
      "AND json_extract(body, '\$.clientId') = ? ORDER BY id DESC LIMIT 1", [clientId]);
    if (waiting.isNotEmpty) {
      final route = waiting.single.read<String>('route');
      await _run('UPDATE outbox SET body = ? WHERE id = ?', [jsonEncode(route == 'notes' ? body : change), waiting.single.read<int>('id')]);
    } else if (send && old.noWords && text.isNotEmpty && row.read<int?>('sent_at') == null && row.read<int>('queued') == 0) {
      // Its files go with it: _queue queues each file not sent.
      await _queue(body);
      await _run('UPDATE notes SET queued = 1 WHERE client_id = ?', [clientId]);
      return true;
    } else if (send && notes.single.read<int?>('sent_at') != null) {
      await enqueue(noteUpdate, change);
    } else {
      await _run('UPDATE notes SET edit_unsent = 1 WHERE client_id = ?', [clientId]);
      return true;
    }
    for (final file in mine ? files : const <Attachment>[]) {
      await enqueue('attachment', file.upload(clientId));
    }
    return true;
  });

  /// A sent note's change upload. It names the note by its server id when a pull saved one: a new key is a new device
  /// on the server, which then knows this phone's older notes by id only. A note from elsewhere lists no files, as the
  /// server takes new files only from the phone that sent the note.
  static Map<String, dynamic> _changeOf(Map<String, dynamic> body, int editedAt, {String? serverId, required bool mine}) => {
    for (final entry in body.entries) if (mine || entry.key != 'attachments') entry.key: entry.value,
    'editedAt': editedAt,
    'id': ?serverId,
  };

  /// Keeps the note, and with [send] queues its upload in the same step.
  Future<void> addNote(LocalNote note, {bool send = false}) => transaction(() async {
    final body = note.toJson();
    await _run('INSERT INTO notes (client_id, body, created_at, queued) VALUES (?, ?, ?, ?)',
      [note.clientId, jsonEncode(body), note.createdAt.millisecondsSinceEpoch, send ? 1 : 0]);
    for (final file in note.attachments) {
      await _run('INSERT INTO attachments (id, note_client_id, name, type, size, path) VALUES (?, ?, ?, ?, ?, ?)',
        [file.id, note.clientId, file.name, file.type, file.size, file.path]);
    }
    if (send) await _queue(body);
  });

  /// Keeps a note the iPhone's share card made, with no location point. [sentAt] is set when the card sent the note already,
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
  /// before its note. With [allFiles], one for each file on this phone, sent or not.
  Future<void> _queue(Map<String, dynamic> body, {bool allFiles = false}) async {
    final clientId = body['clientId'] as String;
    await enqueue('notes', body);
    await _run('UPDATE notes SET edit_unsent = 0 WHERE client_id = ?', [clientId]);
    for (final file in await attachmentsOf(clientId)) {
      if (file.sentAt == null || (allFiles && file.path.isNotEmpty)) await enqueue('attachment', file.upload(clientId));
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

  /// Keeps a voice note at once, with no written words yet and no upload: [setWords] gives it both. Its text holds the
  /// words typed with it, such as a shortcut's label.
  Future<void> addVoiceNote(LocalNote note) =>
    _run('INSERT INTO notes (client_id, body, created_at, kind, audio_path, duration_ms, words_pending, source) '
        'VALUES (?, ?, ?, ?, ?, ?, 1, ?)',
      [note.clientId, jsonEncode(note.toJson()), note.createdAt.millisecondsSinceEpoch, NoteKind.voice.name, note.audioPath,
        note.durationMs, note.fromWatch ? 'watch' : null]);

  /// Gives a voice note its written words, after its typed words on a new line, and with [send] its upload in the same
  /// step. False when the note is gone or has its words already.
  Future<bool> setWords(String clientId, String text, {required bool send}) => transaction(() async {
    final notes = await _rows('SELECT body FROM notes WHERE client_id = ? AND words_pending = 1', [clientId]);
    if (notes.isEmpty) return false;
    final note = _noteOf(jsonDecode(notes.single.read<String>('body')) as Map<String, dynamic>);
    final words = [note.text.trim(), text.trim()].where((part) => part.isNotEmpty).join('\n');
    final body = LocalNote(clientId: clientId, text: words, createdAt: note.createdAt, attachments: note.attachments).toJson();
    await _run('UPDATE notes SET body = ?, words_pending = 0, queued = ? WHERE client_id = ?', [jsonEncode(body), send ? 1 : 0, clientId]);
    if (send) await _queue(body);
    return true;
  });

  /// True when a note keeps the recording at [audioPath], from the support folder.
  Future<bool> keepsRecording(String audioPath) async =>
    (await _rows('SELECT 1 FROM notes WHERE audio_path = ?', [audioPath])).isNotEmpty;

  /// Deletes a note that never had words, such as a recording with no speech.
  Future<void> dropNote(String clientId) => transaction(() async {
    await _run('DELETE FROM notes WHERE client_id = ? AND sent_at IS NULL', [clientId]);
    await _run('DELETE FROM attachments WHERE note_client_id = ? AND note_client_id NOT IN (SELECT client_id FROM notes)', [clientId]);
  });

  // A typed note with no file, recording or words to come: blank words leave nothing in it.
  static const _bare = "kind = 'typed' AND audio_path IS NULL AND words_pending = 0 "
    'AND NOT EXISTS (SELECT 1 FROM attachments WHERE note_client_id = notes.client_id)';

  /// True when blank words leave nothing in the note: it has no file or recording, and waits for no words.
  Future<bool> isBare(String clientId) async =>
    (await _rows('SELECT 1 FROM notes WHERE client_id = ? AND $_bare', [clientId])).isNotEmpty;

  /// Deletes a note the person left with no words, as Apple Notes does, with each change of it still waiting, so it
  /// never goes. The caller found its words blank. False when the note stays: it is not [isBare], or the server has it or
  /// may get it, as it went or its upload waits or is on its way, so [deleteNote] deletes it everywhere.
  Future<bool> dropEmptyNote(String clientId) => transaction(() async {
    final bare = await _rows('SELECT 1 FROM notes WHERE client_id = ? AND sent_at IS NULL AND server_id IS NULL AND $_bare '
      "AND NOT EXISTS (SELECT 1 FROM outbox WHERE route = 'notes' AND json_extract(body, '\$.clientId') = notes.client_id)",
      [clientId]);
    if (bare.isEmpty) return false;
    await _run('DELETE FROM notes WHERE client_id = ?', [clientId]);
    await _run("DELETE FROM outbox WHERE route IN ('notes', '$noteUpdate') AND json_extract(body, '\$.clientId') = ?", [clientId]);
    return true;
  });

  /// Hides a note the person deleted, so *Undo* can bring it back until [deleteNote] runs.
  Future<void> markDeleted(String clientId, DateTime at) =>
    _run('UPDATE notes SET deleting_at = ? WHERE client_id = ?', [at.millisecondsSinceEpoch, clientId]);

  /// Brings back a note marked deleted, as it was.
  Future<void> undoDelete(String clientId) => _run('UPDATE notes SET deleting_at = NULL WHERE client_id = ?', [clientId]);

  /// Each note marked deleted, with when, such as one whose *Undo* time a close cut short.
  Future<List<(String, DateTime)>> marked() async => [
    for (final row in await _rows('SELECT client_id, deleting_at FROM notes WHERE deleting_at IS NOT NULL ORDER BY deleting_at'))
      (row.read<String>('client_id'), DateTime.fromMillisecondsSinceEpoch(row.read<int>('deleting_at'))),
  ];

  /// Deletes a note on this phone, with its files and each upload of it still waiting. A note the server may have, as
  /// it went or its upload may be on its way, gets one `note.delete`, also with sending off: the outbox keeps it until
  /// sending is on, so the note never comes back. A 404 for one that never landed is dropped. True when one was queued.
  Future<bool> deleteNote(String clientId) async {
    final files = <String>[];
    final queued = await transaction(() async {
      final notes = await _rows('SELECT sent_at, server_id FROM notes WHERE client_id = ?', [clientId]);
      if (notes.isEmpty) return false;
      final serverId = notes.single.read<String?>('server_id');
      final going = await _rows("SELECT 1 FROM outbox WHERE route = 'notes' AND json_extract(body, '\$.clientId') = ?", [clientId]);
      final sent = serverId != null || notes.single.read<int?>('sent_at') != null || going.isNotEmpty;
      files.addAll(await _drop(clientId));
      if (sent) await enqueue(noteDelete, {'clientId': clientId, 'id': ?serverId});
      return sent;
    });
    for (final path in files) {
      await _delete(path);
    }
    return queued;
  }

  /// Deletes a note's row, its files' rows and its waiting uploads, inside a step; gives its local files, which the
  /// caller deletes after the step.
  Future<List<String>> _drop(String clientId) async {
    final files = [
      for (final row in await _rows("SELECT path FROM attachments WHERE note_client_id = ? AND path IS NOT NULL AND path != ''",
          [clientId])) row.read<String>('path'),
      for (final row in await _rows('SELECT audio_path FROM notes WHERE client_id = ? AND audio_path IS NOT NULL', [clientId]))
        row.read<String>('audio_path'),
    ];
    await _run("DELETE FROM outbox WHERE (route IN ('notes', '$noteUpdate') AND json_extract(body, '\$.clientId') = ?) "
      "OR (route = 'attachment' AND json_extract(body, '\$.noteClientId') = ?)", [clientId, clientId]);
    await _run('DELETE FROM attachments WHERE note_client_id = ?', [clientId]);
    await _run('DELETE FROM notes WHERE client_id = ?', [clientId]);
    return files;
  }

  /// Voice notes still waiting for their words, oldest first.
  Future<List<LocalNote>> pendingWords() async =>
    [for (final note in (await notes()).reversed) if (note.wordsPending) note];

  /// [LocalNote.noWords] in SQL: such a note is not an earlier note to send.
  static const _noWords = "source IS 'watch' AND kind = 'voice' AND words_pending = 0 AND json_extract(body, '\$.text') = ''";

  static const _earlier = 'FROM notes WHERE sent_at IS NULL AND queued = 0 AND words_pending = 0 AND deleting_at IS NULL '
    'AND NOT ($_noWords)';

  /// With the notes that went only to the person's own webhook: this phone's own, sent, with no server id and no upload
  /// waiting. A note on the person's Relay Everything space has a server id once a pull saw it, so it never counts again.
  static const _earlierOrWebhook = 'FROM notes WHERE words_pending = 0 AND deleting_at IS NULL AND NOT ($_noWords) AND '
    '((sent_at IS NULL AND queued = 0) OR (mine = 1 AND server_id IS NULL AND sent_at IS NOT NULL AND NOT EXISTS '
    "(SELECT 1 FROM outbox WHERE route = 'notes' AND json_extract(outbox.body, '\$.clientId') = notes.client_id)))";

  /// How many notes never went to the server and have no upload: the notes the earlier-notes prompt asks about. With
  /// [fromWebhook], as when a phone that sent to the person's own webhook signs in, the notes that went only there too.
  Future<int> earlierCount({bool fromWebhook = false}) async =>
    (await _rows('SELECT count(*) AS n ${fromWebhook ? _earlierOrWebhook : _earlier}')).single.read<int>('n');

  /// Queues every earlier note, oldest first, each with its files. With [fromWebhook], the notes that went only to the
  /// person's own webhook too, with all their files: the webhook took the files, the server never did. A change still
  /// waiting for such a note goes: the new upload carries its newest words.
  Future<void> queueEarlier({bool fromWebhook = false}) => transaction(() async {
    final rows = await _rows('SELECT client_id, body, sent_at ${fromWebhook ? _earlierOrWebhook : _earlier} '
      'ORDER BY created_at, client_id');
    for (final row in rows) {
      final clientId = row.read<String>('client_id');
      final went = row.read<int?>('sent_at') != null;
      if (went) {
        await _run("DELETE FROM outbox WHERE route = '$noteUpdate' AND json_extract(body, '\$.clientId') = ?", [clientId]);
      }
      await _queue(jsonDecode(row.read<String>('body')) as Map<String, dynamic>, allFiles: went);
      await _run('UPDATE notes SET queued = 1 WHERE client_id = ?', [clientId]);
    }
  });

  Future<void> noteSent(String clientId, DateTime at) =>
    _run('UPDATE notes SET sent_at = ? WHERE client_id = ?', [at.millisecondsSinceEpoch, clientId]);

  /// Keeps the notes a pull read, in change order; gives false when it left out [editing], the note open in the editor,
  /// or the delete of a note this phone marked deleted.
  /// A note matches by server id, then by client id against this phone's own notes, whatever the server's `mine` says:
  /// a new key makes a new device on the server, which then calls this phone's older notes not its own. Phone ids are
  /// 32 random hex characters and email ids start `email:`, so no other note matches. One from elsewhere is kept as
  /// `srv:<id>`. A deleted note's `{id, clientId, deleted: true}` deletes it here, with its files, after the step.
  Future<bool> applyPulled(List<Map<String, dynamic>> notes, {String? editing}) async {
    final files = <String>[];
    final all = await transaction(() async {
      var all = true;
      for (final note in notes) {
        final kept = note['deleted'] == true ? await _applyDeleted(note, editing, files) : await _applyPulled(note, editing);
        if (!kept) all = false;
      }
      return all;
    });
    for (final path in files) {
      await _delete(path);
    }
    return all;
  }

  /// Deletes a note deleted elsewhere, matched as [_applyPulled] matches, and adds its local files to [files]. The note
  /// open in the editor stays, as for a change, and so does a note this phone marked deleted: false holds the sync place,
  /// so the next pull deletes it here too if *Undo* brought it back.
  Future<bool> _applyDeleted(Map<String, dynamic> note, String? editing, List<String> files) async {
    final clientId = note['clientId'] as String?;
    const columns = 'SELECT client_id, deleting_at FROM notes';
    var rows = await _rows('$columns WHERE server_id = ?', [note['id']]);
    if (rows.isEmpty && clientId != null) rows = await _rows('$columns WHERE client_id = ? AND mine = 1', [clientId]);
    if (rows.isEmpty) return true;
    final id = rows.single.read<String>('client_id');
    if (id == editing || rows.single.read<int?>('deleting_at') != null) return false;
    files.addAll(await _drop(id));
    return true;
  }

  /// Newer wins: this phone's words stay when its waiting change, or its own last edit that never went, is later than
  /// the pulled edit time; else the pulled words are kept and any waiting change of the note is dropped. An edit that
  /// never went, such as one made while sending was off, gets its change queued: a pull runs only while sending is on.
  /// An edit that went, or was dropped, is never queued again: the server may keep it at an earlier time than the phone.
  Future<bool> _applyPulled(Map<String, dynamic> note, String? editing) async {
    final serverId = note['id'] as String;
    final clientId = note['clientId'] as String?;
    const columns = 'SELECT client_id, body, edited_at, mine, edit_unsent FROM notes';
    var rows = await _rows('$columns WHERE server_id = ?', [serverId]);
    if (rows.isEmpty && clientId != null) rows = await _rows('$columns WHERE client_id = ? AND mine = 1', [clientId]);
    final mine = rows.isNotEmpty ? rows.single.read<int>('mine') == 1 : note['mine'] == true && clientId != null;
    final id = rows.isNotEmpty ? rows.single.read<String>('client_id') : mine ? clientId! : 'srv:$serverId';
    if (id == editing) return false;
    final recordedAt = note['recordedAt'] as int;
    final editedAt = note['editedAt'] as int?;
    final serverAt = editedAt ?? recordedAt;
    final text = note['text'] as String? ?? '';
    final change = await _rows("SELECT json_extract(body, '\$.editedAt') AS at FROM outbox WHERE route = '$noteUpdate' "
      "AND json_extract(body, '\$.clientId') = ? ORDER BY id DESC LIMIT 1", [id]);
    final local = rows.isEmpty ? null : jsonDecode(rows.single.read<String>('body')) as Map<String, dynamic>;
    final localAt = rows.isEmpty ? null : rows.single.read<int?>('edited_at');
    final waits = change.isNotEmpty && (change.single.read<int?>('at') ?? 0) > serverAt;
    // Same words need no change: a phone clock that runs ahead of the server's would otherwise send one on each pull.
    final neverWent = rows.isNotEmpty && rows.single.read<int>('edit_unsent') == 1;
    final unsent = change.isEmpty && neverWent && local != null && localAt != null && localAt > serverAt && local['text'] != text;
    final keep = waits || unsent;
    final ring = note['source'] == 'ring' && note['audio'] == true;
    final files = [
      for (final file in (note['attachments'] as List?) ?? const [])
        if (file is Map<String, dynamic>) Attachment(id: file['id'] as String, name: file['name'] as String? ?? '',
          type: file['type'] as String? ?? '', size: file['size'] as int? ?? 0, path: ''),
      if (ring) Attachment(id: '$recordingPrefix$serverId', name: 'Recording.m4a', type: 'audio/mp4', size: 0, path: ''),
    ];
    final body = jsonEncode(LocalNote(clientId: id, text: text,
      createdAt: DateTime.fromMillisecondsSinceEpoch(recordedAt), attachments: files).toJson());
    if (rows.isEmpty) {
      await _run('INSERT INTO notes (client_id, body, created_at, sent_at, queued, kind, edited_at, server_id, device, mine) '
        'VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?)', [id, body, recordedAt, recordedAt, ring ? NoteKind.voice.name : NoteKind.typed.name,
          editedAt, serverId, note['device'], mine ? 1 : 0]);
    } else {
      await _run('UPDATE notes SET server_id = ?, device = ?, sent_at = coalesce(sent_at, ?) WHERE client_id = ?',
        [serverId, note['device'], recordedAt, id]);
      if (!keep) await _run('UPDATE notes SET body = ?, edited_at = ?, edit_unsent = 0 WHERE client_id = ?', [body, editedAt, id]);
    }
    if (!keep) {
      await _run("DELETE FROM outbox WHERE route = '$noteUpdate' AND json_extract(body, '\$.clientId') = ?", [id]);
    } else if (unsent) {
      await enqueue(noteUpdate, _changeOf(local, localAt, serverId: serverId, mine: mine));
      await _run('UPDATE notes SET edit_unsent = 0 WHERE client_id = ?', [id]);
    } else {
      // A change queued before this pull saved the server id goes by it now.
      await _run("UPDATE outbox SET body = json_set(body, '\$.id', ?) WHERE route = '$noteUpdate' "
        "AND json_extract(body, '\$.clientId') = ?", [serverId, id]);
    }
    for (final file in files) {
      await _run('INSERT OR IGNORE INTO attachments (id, note_client_id, name, type, size, sent_at) VALUES (?, ?, ?, ?, ?, ?)',
        [file.id, id, file.name, file.type, file.size, recordedAt]);
    }
    return true;
  }

  /// Keeps where a downloaded file of a note now is, from the app's support folder.
  Future<void> fileKept(String id, String path) => _run('UPDATE attachments SET path = ? WHERE id = ?', [path, id]);

  /// For sign-out: deletes the notes from elsewhere, their files and waiting changes, and the pull's place, so a later
  /// sign-in pulls from the start.
  Future<void> dropSynced() async {
    const synced = 'SELECT client_id FROM notes WHERE mine = 0';
    final files = await _rows("SELECT path FROM attachments WHERE path IS NOT NULL AND path != '' AND note_client_id IN ($synced)");
    await transaction(() async {
      await _run('DELETE FROM attachments WHERE note_client_id IN ($synced)');
      await _run("DELETE FROM outbox WHERE route = '$noteUpdate' AND json_extract(body, '\$.clientId') IN ($synced)");
      await _run('DELETE FROM notes WHERE mine = 0');
      await remove(noteSyncSeq);
    });
    for (final row in files) {
      await _delete(row.read<String>('path'));
    }
  }

  /// Every note made on this phone, newest first, each with its files. A note marked deleted is left out.
  Future<List<LocalNote>> notes() async {
    final files = <String, List<Attachment>>{};
    for (final row in await _rows('SELECT note_client_id, id, name, type, size, path, sent_at FROM attachments ORDER BY rowid')) {
      files.putIfAbsent(row.read<String>('note_client_id'), () => []).add(_attachmentOf(row));
    }
    return [
      for (final row in await _rows('SELECT client_id, body, sent_at, queued, kind, audio_path, duration_ms, words_pending, '
          'edited_at, server_id, device, mine, source FROM notes WHERE deleting_at IS NULL ORDER BY created_at DESC, client_id DESC'))
        _noteOf(jsonDecode(row.read<String>('body')) as Map<String, dynamic>, sentAt: row.read<int?>('sent_at'),
          queued: row.read<int>('queued') == 1,
          kind: NoteKind.values.byName(row.read<String>('kind')), audioPath: row.read<String?>('audio_path'),
          durationMs: row.read<int?>('duration_ms'), wordsPending: row.read<int>('words_pending') == 1,
          attachments: files[row.read<String>('client_id')], editedAt: row.read<int?>('edited_at'),
          serverId: row.read<String?>('server_id'), device: row.read<String?>('device'), mine: row.read<int>('mine') == 1,
          fromWatch: row.read<String?>('source') == 'watch'),
    ];
  }

  /// A note's body, with its files listed by the body when the table's rows are not given.
  static LocalNote _noteOf(Map<String, dynamic> body, {int? sentAt, bool queued = false,
    NoteKind kind = NoteKind.typed, String? audioPath, int? durationMs, bool wordsPending = false,
    List<Attachment>? attachments, int? editedAt, String? serverId, String? device, bool mine = true,
    bool fromWatch = false}) => LocalNote(
    clientId: body['clientId'] as String, text: body['text'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(body['createdAt'] as int),
    sentAt: sentAt == null ? null : DateTime.fromMillisecondsSinceEpoch(sentAt), queued: queued,
    kind: kind, audioPath: audioPath, durationMs: durationMs, wordsPending: wordsPending,
    editedAt: editedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(editedAt),
    serverId: serverId, device: device, mine: mine, fromWatch: fromWatch,
    attachments: attachments ?? [
      for (final file in (body['attachments'] as List?) ?? const [])
        Attachment(id: (file as Map)['id'] as String, name: file['name'] as String, type: file['type'] as String,
          size: file['size'] as int, path: ''),
    ],
  );

  /// Drops the health, nights, location and calendar events that did not go yet, and health's sent list and redo mark,
  /// for when sending turns off. Note uploads stay, so a later turn-on sends them with no second prompt.
  Future<void> dropReadings() => transaction(() async {
    await _run("DELETE FROM outbox WHERE route IN ('health', '$nightsRoute', 'locations', '$staysRoute')");
    await _run('DELETE FROM points');
    await remove(healthSent);
    await remove(healthDetail);
    await _dropTimeline();
    await _dropCalendar();
  });

  /// Drops the open stay or trip, its points and its motion, for when location history turns off.
  Future<void> dropTimeline() => transaction(_dropTimeline);

  /// Queues the open stay as ended, then drops the timeline, for when stays stop while sending goes on:
  /// the server would otherwise keep the stay as ongoing.
  Future<void> closeTimeline() => transaction(() async {
    final open = (await timeline()).closeOpen();
    if (open != null) await enqueue(staysRoute, {'stays': [open.toJson()]});
    await _dropTimeline();
  });

  Future<void> _dropTimeline() async {
    await _run('DELETE FROM track');
    await _run('DELETE FROM motions');
    await remove(timelineKey);
  }

  /// Drops the points not yet queued, for when the person picks *Only stays and trips*. Points already in the outbox
  /// are on their way. Returns how many it dropped.
  Future<int> dropPoints() => transaction(() async {
    final count = (await _rows('SELECT count(*) AS n FROM points')).single.read<int>('n');
    await _run('DELETE FROM points');
    return count;
  });

  /// Drops waiting calendar uploads and forgets what was sent, so the calendar turned on again sends its whole window.
  Future<void> dropCalendar() => transaction(_dropCalendar);

  Future<void> _dropCalendar() async {
    await _run("DELETE FROM outbox WHERE route = 'calendar'");
    await _run('DELETE FROM calendar_sent');
  }

  /// Each calendar event sent, by key, with the hash of what was sent.
  Future<Map<String, String>> calendarSent() async => {
    for (final row in await _rows('SELECT key, hash FROM calendar_sent')) row.read<String>('key'): row.read<String>('hash'),
  };

  /// Queues calendar [uploads] and, in the same step, marks [sent] keys with their hashes and forgets [forget] keys, so a
  /// crash never marks an event sent that has no upload.
  Future<void> queueCalendar(List<Map<String, dynamic>> uploads, Map<String, String> sent, Iterable<String> forget) =>
    transaction(() async {
      for (final upload in uploads) {
        await enqueue('calendar', upload);
      }
      for (final entry in sent.entries) {
        await _run('INSERT OR REPLACE INTO calendar_sent (key, hash) VALUES (?, ?)', [entry.key, entry.value]);
      }
      for (final key in forget) {
        await _run('DELETE FROM calendar_sent WHERE key = ?', [key]);
      }
    });

  /// One point of location history; a second at the same moment is the same point. By [send], it waits to go as a point,
  /// goes into the open stay or trip, or both.
  /// A point at or before the timeline's cursor is marked late: a round already stepped past its time.
  Future<void> addPoint(Pin point, {LocationSend send = LocationSend.all}) async {
    final at = point.at.millisecondsSinceEpoch;
    if (send != LocationSend.stays) await _run('INSERT OR IGNORE INTO points (at, body) VALUES (?, ?)', [at, jsonEncode(point.toJson())]);
    if (send == LocationSend.points) return;
    final cursor = (await timeline()).cursor;
    final late = cursor != null && !point.at.isAfter(cursor);
    await _run('INSERT OR IGNORE INTO track (at, body) VALUES (?, ?)', [at, jsonEncode({...point.toJson(), if (late) 'late': true})]);
  }

  /// The open stay or trip's points, oldest first.
  Future<List<Pin>> track() async => [
    for (final row in await _rows('SELECT body FROM track ORDER BY at'))
      Pin.fromJson(jsonDecode(row.read<String>('body')) as Map<String, dynamic>),
  ];

  /// The times of the open stay or trip's points that came late.
  Future<Set<DateTime>> lateTrack() async => {
    for (final row in await _rows("SELECT at FROM track WHERE json_extract(body, '\$.late')"))
      DateTime.fromMillisecondsSinceEpoch(row.read<int>('at')),
  };

  /// Keeps motion changes; a second at the same moment is the same change.
  Future<void> addMotions(List<MotionChange> changes) => transaction(() async {
    for (final change in changes) {
      await _run('INSERT OR IGNORE INTO motions (at, body) VALUES (?, ?)',
        [change.at.millisecondsSinceEpoch, jsonEncode(change.toJson())]);
    }
  });

  /// The motion changes kept, oldest first.
  Future<List<MotionChange>> motions() async => [
    for (final row in await _rows('SELECT body FROM motions ORDER BY at')) ?MotionChange.fromJson(jsonDecode(row.read<String>('body'))),
  ];

  /// The open stay or trip, as the last round left it.
  Future<TimelineState> timeline() async => TimelineState.decode(await get(timelineKey));

  /// Queues [segments], up to 500 an upload, saves [state], and drops the points and motion it no longer needs, in one
  /// step: a round cut before it keeps every point, and does the step again.
  Future<void> queueStays(List<Segment> segments, TimelineState state, {int batch = 500}) => transaction(() async {
    for (var i = 0; i < segments.length; i += batch) {
      await enqueue(staysRoute, {'stays': [for (final segment in segments.skip(i).take(batch)) segment.toJson()]});
    }
    await set(timelineKey, state.encode());
    final keep = state.keepFrom?.millisecondsSinceEpoch;
    if (keep == null) return;
    await _run('DELETE FROM track WHERE at < ?', [keep]);
    // The change before the open stay or trip says what the person was doing as it began.
    await _run('DELETE FROM motions WHERE at < (SELECT max(at) FROM motions WHERE at <= ?)', [keep]);
  });

  /// Gives the point kept at [at] its place name, while it waits in the store. A point already queued stays unnamed.
  Future<void> namePoint(DateTime at, String place) =>
    _run("UPDATE points SET body = json_set(body, '\$.place', ?) WHERE at = ?", [place, at.millisecondsSinceEpoch]);

  /// Moves up to [batch] points at a time into the outbox, in time order.
  Future<void> queuePoints({int batch = 500}) => transaction(() async {
    while (true) {
      final rows = await _rows('SELECT at, body FROM points ORDER BY at LIMIT ?', [batch]);
      if (rows.isEmpty) return;
      var id = await _takeIds(rows.length);
      await enqueue('locations', {'points': [
        for (final row in rows) {...jsonDecode(row.read<String>('body')) as Map<String, dynamic>, 'id': id++},
      ]});
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
    for (final row in await _rows('SELECT client_id, asset_id, taken_at, lat, lon, width, height, path, created_at FROM photos '
        'ORDER BY taken_at, created_at, client_id'))
      QueuedPhoto(clientId: row.read<String>('client_id'), assetId: row.read<String>('asset_id'),
        takenAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('taken_at')), lat: row.read<double?>('lat'),
        lon: row.read<double?>('lon'), width: row.read<int>('width'), height: row.read<int>('height'), path: row.read<String>('path'),
        queuedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at'))),
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

  /// Health readings waiting to send, in the outbox.
  Future<int> waitingReadings() async => (await _rows(
    "SELECT coalesce(sum(json_array_length(body, '\$.samples')), 0) AS n FROM outbox WHERE route = 'health'")).single.read<int>('n');

  /// Calendar events waiting to send, changed or removed, in the outbox.
  Future<int> waitingEvents() async => (await _rows(
    "SELECT coalesce(sum(json_array_length(body, '\$.events') + json_array_length(body, '\$.removed')), 0) AS n "
    "FROM outbox WHERE route = 'calendar'")).single.read<int>('n');

  /// Stays and trips waiting to send, in the outbox.
  Future<int> waitingStays() async => (await _rows(
    "SELECT coalesce(sum(json_array_length(body, '\$.stays')), 0) AS n FROM outbox WHERE route = '$staysRoute'")).single.read<int>('n');

  /// Location points waiting to send: in the outbox, and kept but not yet queued.
  Future<int> waitingPoints() async => (await _rows(
    "SELECT coalesce((SELECT sum(json_array_length(body, '\$.points')) FROM outbox WHERE route = 'locations'), 0) "
    '+ (SELECT count(*) FROM points) AS n')).single.read<int>('n');

  /// When [key], [sentHealth], [sentPoints] or [sentCalendar], was last written, or null for never.
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

/// A random UUID, version 4.
String newUuid([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List.generate(16, (_) => source.nextInt(256));
  bytes[6] = bytes[6] & 0x0f | 0x40;
  bytes[8] = bytes[8] & 0x3f | 0x80;
  final hex = [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
