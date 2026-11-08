import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'connection.dart';
import 'store.dart';

/// The phone's name in each message. The app reads no phone model, so it is the kind of phone.
String phoneName() => Platform.isIOS ? 'iPhone' : 'Android phone';

const _prefix = 'whsec_';

/// A new secret: `whsec_` and 32 random bytes in base64, as the server's webhooks make.
String makeWebhookSecret([Random? random]) {
  final source = random ?? Random.secure();
  return _prefix + base64.encode(List.generate(32, (_) => source.nextInt(256)));
}

/// The Standard Webhooks headers of one message, signed as the server signs (`app/worker/apps/relay/webhooks/sign.ts`):
/// an HMAC-SHA256 of "{id}.{timestamp}.{body}", sent as `webhook-signature: v1,<base64>`. The timestamp is the send time.
Map<String, String> signedHeaders(String secret, String id, String body, DateTime now) {
  final timestamp = '${now.millisecondsSinceEpoch ~/ 1000}';
  final mac = Hmac(sha256, base64.decode(secret.substring(_prefix.length))).convert(utf8.encode('$id.$timestamp.$body'));
  return {'Content-Type': 'application/json', 'User-Agent': 'RelayEverything-Phone/1', 'webhook-id': id,
    'webhook-timestamp': timestamp, 'webhook-signature': 'v1,${base64.encode(mac.bytes)}'};
}

String _iso(Object? ms) => DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true).toIso8601String();

String _type(Object? type) => type is String && type.isNotEmpty ? type : 'application/octet-stream';

/// Sends the outbox straight to the person's own webhook, in format v1 (`site/public/webhooks/v1.schema.json`), so a
/// receiver built for the server's webhooks takes it unchanged. It builds each message from the waiting upload's body
/// when it sends, so a move between places needs no rewrite.
///
/// Only a 2xx answer counts as sent. A 413 on a file drops that file; every other answer, or none, keeps the upload
/// and stops the round: a receiver's 400 is most often its own bug, and dropping would lose data.
class WebhookClient implements Outbound {
  WebhookClient(this.webhook, {required this.installId, String? deviceName, http.Client? client, DateTime Function()? clock})
    : deviceName = deviceName ?? phoneName(), _client = client ?? http.Client(), _clock = clock ?? DateTime.now;

  final Webhook webhook;
  /// This install's own id: the `device.id` of each message, and the start of each `webhook-id`.
  final String installId;
  final String deviceName;
  final http.Client _client;
  final DateTime Function() _clock;
  static const _timeout = Duration(seconds: 30);
  /// A 25 MB file is about 33 MB of JSON, so it may take longer on a slow signal.
  static const _fileTimeout = Duration(minutes: 5);

  @override
  String get destination => ownWebhook;

  Map<String, dynamic> get _device => {'id': installId, 'name': deviceName};

  /// The v1 message for one waiting upload, the same each time it is built. [bytes] are an `attachment`'s file. Null
  /// for a batch with no rows, which needs no message.
  Map<String, dynamic>? message(OutboxItem item, [List<int>? bytes]) {
    final body = item.body;
    final (String type, Map<String, dynamic> data) = switch (item.route) {
      'notes' => ('note.created', {'note': _note(body)}),
      noteUpdate => ('note.updated', {'note': _note(body)
        ..remove('audio')..['edited_at'] = _iso(body['editedAt'] ?? item.createdAt.millisecondsSinceEpoch)}),
      'attachment' => ('note.file', {'note_id': body['noteClientId'], 'file': {'id': body['id'], 'name': body['name'],
        'content_type': _type(body['type']), 'size': bytes!.length, 'base64': base64.encode(bytes)}}),
      'health' => ('health.samples', {'samples': [for (final sample in body['samples'] as List) _sample(sample as Map)]}),
      'locations' => ('location.points', {'points': [for (final point in body['points'] as List) _point(point as Map)]}),
      'calendar' => ('calendar.events', {'events': [
        for (final event in body['events'] as List) _event(event as Map),
        for (final key in body['removed'] as List) _removed(key as String),
      ]}),
      final route => throw ArgumentError.value(route, 'route'),
    };
    if ((data['samples'] ?? data['points'] ?? data['events']) case final List rows when rows.isEmpty) return null;
    return {'version': 1, 'type': type, 'timestamp': _iso(item.createdAt.millisecondsSinceEpoch), 'data': data};
  }

  /// A note as `note.created` and `note.updated` both carry it. `created_at` is when the phone kept the note, as the
  /// phone keeps no time it was first queued, so a change carries the same `created_at` as the note did.
  Map<String, dynamic> _note(Map<String, dynamic> body) {
    final files = body['attachments'] as List?;
    return {
      'id': body['clientId'], 'source': 'typed', 'text': body['text'], 'recorded_at': _iso(body['createdAt']),
      'created_at': _iso(body['createdAt']), 'device': _device,
      'place': body['lat'] == null ? null
        : {'lat': body['lat'], 'lon': body['lon'], 'accuracy': body['accuracy'], 'name': body['place'], 'from': 'phone'},
      'audio': null,
      if (files != null && files.isNotEmpty) 'attachments': [
        for (final file in files.cast<Map>())
          {'id': file['id'], 'name': file['name'], 'content_type': _type(file['type']), 'size': file['size']},
      ],
    };
  }

  Map<String, dynamic> _sample(Map sample) => {'id': sample['id'], 'device': _device, 'type': sample['type'],
    'start': _iso(sample['start']), 'end': _iso(sample['end']), 'value': sample['value'], 'unit': sample['unit'],
    'source': sample['source']};

  Map<String, dynamic> _point(Map point) => {'id': point['id'], 'device': _device, 'at': _iso(point['at']),
    'lat': point['lat'], 'lon': point['lon'], 'accuracy': point['accuracy'], 'place': point['place']};

  /// An event's id: the first 48 bits of the SHA-256 of the install id and its key, so each change of one occurrence
  /// has the same id, and a receiver upserts by it as it does the server's.
  int _eventId(String key) =>
    sha256.convert(utf8.encode('$installId:$key')).bytes.take(6).fold(0, (id, byte) => id * 256 + byte);

  Map<String, dynamic> _event(Map event) => {'id': _eventId(event['key'] as String), 'status': 'changed', 'device': _device,
    'key': event['key'], 'calendar': event['calendar'], 'title': event['title'], 'start': _iso(event['start']),
    'end': _iso(event['end']), 'all_day': event['allDay'], 'location': event['location'], 'notes': event['notes'],
    'url': event['url'], 'people': event['people']};

  /// A removed event. The phone keeps only its key, so the start comes from the key's end and the rest is empty.
  Map<String, dynamic> _removed(String key) {
    final start = _iso(int.tryParse(key.substring(key.lastIndexOf(':') + 1)) ?? 0);
    return {'id': _eventId(key), 'status': 'removed', 'device': _device, 'key': key, 'calendar': null, 'title': null,
      'start': start, 'end': start, 'all_day': false, 'location': null, 'notes': null, 'url': null, 'people': []};
  }

  /// `<install id>:<outbox row id>`: the same over every retry, so a receiver keeps a message sent twice once.
  String _id(OutboxItem item) => '$installId:${item.id}';

  @override
  Future<void> send(OutboxItem item) async {
    final built = message(item);
    if (built != null) await _post(_id(item), built);
  }

  @override
  Future<void> sendFile(OutboxItem item, List<int> bytes) async {
    await _post(_id(item), message(item, bytes)!, file: true);
  }

  /// *Send a test*: a signed `webhook.test` message. Returns the receiver's status, or null when it did not answer.
  Future<int?> test() async {
    final now = _clock();
    try {
      return await _post('$installId:test-${now.millisecondsSinceEpoch}', {'version': 1, 'type': 'webhook.test',
        'timestamp': _iso(now.millisecondsSinceEpoch), 'data': {'webhook': {'id': installId, 'name': deviceName}}});
    } on ApiException catch (error) {
      return error.status;
    }
  }

  /// Sends one signed message and returns its 2xx status; throws for any other answer.
  Future<int> _post(String id, Map<String, dynamic> message, {bool file = false}) async {
    final body = jsonEncode(message);
    final http.Response response;
    try {
      response = await _client.post(Uri.parse(webhook.address), headers: signedHeaders(webhook.secret, id, body, _clock()),
        body: body).timeout(file ? _fileTimeout : _timeout);
    } on Exception {
      throw const ApiException(Failure.offline, null);
    }
    final status = response.statusCode;
    if (status >= 200 && status < 300) return status;
    throw ApiException(file && status == 413 ? Failure.rejected : Failure.offline, status);
  }
}
