import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:relay_app/data/api.dart';
import 'package:relay_app/data/outbox.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/data/webhook.dart';

import 'fakes.dart';

final queued = DateTime.utc(2026, 11, 4, 14, 1, 2);
final sent = DateTime.utc(2026, 11, 4, 14, 5);

OutboxItem item(int id, String route, Map<String, dynamic> body) =>
  OutboxItem(id, route, body, destination: ownWebhook, createdAt: queued);

final note = item(7, 'notes', {'clientId': '3f9a0c1d2e4b5a6978c1d2e3f4a5b6c7', 'text': 'Receipt for the desk lamp',
  'createdAt': Date.recorded, 'lat': 43.65, 'lon': -79.38, 'accuracy': 12.0, 'place': 'King St W',
  'attachments': [{'id': 'f1', 'name': 'receipt.jpg', 'type': 'image/jpeg', 'size': 4}]});
final update = item(11, noteUpdate, {'clientId': '3f9a0c1d2e4b5a6978c1d2e3f4a5b6c7', 'text': '# Receipt\n- [x] Paid',
  'createdAt': Date.recorded, 'editedAt': Date.recorded + 600000,
  'attachments': [{'id': 'f1', 'name': 'receipt.jpg', 'type': 'image/jpeg', 'size': 4}]});
final deleted = item(15, noteDelete, {'clientId': '3f9a0c1d2e4b5a6978c1d2e3f4a5b6c7', 'id': 's1'});
final file = item(8, 'attachment', {'noteClientId': '3f9a0c1d2e4b5a6978c1d2e3f4a5b6c7', 'id': 'f1',
  'path': 'attachments/f1.jpg', 'name': 'receipt.jpg', 'type': 'image/jpeg'});
final samples = item(9, 'health', {'samples': [{'type': 'steps', 'start': Date.recorded,
  'end': Date.recorded + 60000, 'value': 120.0, 'unit': 'count', 'source': 'com.apple.health'},
  {'type': 'workout', 'start': Date.recorded, 'end': Date.recorded + 1920000, 'value': 32.0, 'unit': 'min',
    'source': 'com.apple.health', 'kind': 'running', 'distance': 5100.0, 'calories': 410.0}]});
final nights = item(19, nightsRoute, {'nights': [
  {'source': 'com.apple.health.watch', 'start': Date.recorded - 28800000, 'end': Date.recorded, 'asleepAt': Date.recorded - 27900000,
    'wokeAt': Date.recorded - 600000, 'asleep': 435.0, 'core': 250.0, 'deep': 75.0, 'rem': 110.0, 'awake': 25.0, 'stages': [
      {'stage': 'core', 'start': Date.recorded - 27900000, 'end': Date.recorded - 24900000},
      {'stage': 'deep', 'start': Date.recorded - 24900000, 'end': Date.recorded - 20400000}]},
  {'source': 'com.apple.health', 'start': Date.recorded - 28800000, 'end': Date.recorded, 'asleep': 0.0, 'core': 0.0,
    'deep': 0.0, 'rem': 0.0, 'awake': 0.0, 'stages': []}]});
final points = item(10, 'locations', {'points': [{'id': 2, 'at': Date.recorded, 'lat': 43.65, 'lon': -79.38,
  'accuracy': 12.0, 'place': 'King St W'}]});
final stays = item(16, 'stays', {'stays': [
  {'kind': 'stay', 'start': Date.recorded - 3600000, 'end': Date.recorded, 'lat': 43.65, 'lon': -79.38, 'name': 'Cafe Nero',
    'source': 'calendar', 'address': 'King St W', 'event': 'Coffee with Sam'},
  {'kind': 'trip', 'start': Date.recorded, 'end': Date.recorded + 1200000, 'mode': 'cycling', 'km': 4.2},
  {'kind': 'stay', 'start': Date.recorded + 1200000, 'end': Date.recorded + 1500000, 'ongoing': true, 'lat': 43.66,
    'lon': -79.39, 'name': '43.660, -79.390', 'source': 'point'}]});

final calendar = item(13, 'calendar', {'events': [{'key': 'work:a:${Date.recorded}', 'calendar': 'Work',
  'title': 'Board meeting', 'start': Date.recorded, 'end': Date.recorded + 3600000, 'allDay': false, 'location': 'Room 4',
  'people': [{'name': 'Sam', 'email': 'sam@example.com', 'organizer': true}]}], 'removed': ['work:b:${Date.recorded}']});

final photo = QueuedPhoto(clientId: '7b2e4c1a-9d3f-4e6a-8b5c-0a1d2e3f4a5b', assetId: 'IMG_0001',
  takenAt: DateTime.utc(2026, 11, 4, 13, 58), lat: 38.7139, lon: -9.1394, width: 1600, height: 1200,
  path: 'photos/7b2e4c1a-9d3f-4e6a-8b5c-0a1d2e3f4a5b.jpg', queuedAt: queued);

abstract final class Date {
  static final recorded = DateTime.utc(2026, 11, 4, 14, 1).millisecondsSinceEpoch;
}

WebhookClient client(FakeServer server) =>
  WebhookClient(hook, installId: installId, deviceName: 'Android phone', client: server.client(), clock: () => sent);

/// True when [request] is signed with [fixtureSecret] by Standard Webhooks.
bool signed(http.Request request) {
  final id = request.headers['webhook-id'], timestamp = request.headers['webhook-timestamp'];
  final mac = Hmac(sha256, base64.decode(fixtureSecret.substring(6))).convert(utf8.encode('$id.$timestamp.${request.body}'));
  return request.headers['webhook-signature'] == 'v1,${base64.encode(mac.bytes)}';
}

void main() {
  test('builds each upload as a format v1 message, the same as the server sends', () {
    final webhook = client(FakeServer());
    final device = {'id': installId, 'name': 'Android phone'};
    expect(webhook.message(note), {'version': 1, 'type': 'note.created', 'timestamp': '2026-11-04T14:01:02.000Z', 'data': {
      'note': {'id': '3f9a0c1d2e4b5a6978c1d2e3f4a5b6c7', 'source': 'typed', 'text': 'Receipt for the desk lamp',
        'recorded_at': '2026-11-04T14:01:00.000Z', 'created_at': '2026-11-04T14:01:00.000Z', 'device': device,
        'place': {'lat': 43.65, 'lon': -79.38, 'accuracy': 12.0, 'name': 'King St W', 'from': 'phone'}, 'audio': null,
        'attachments': [{'id': 'f1', 'name': 'receipt.jpg', 'content_type': 'image/jpeg', 'size': 4}]}}});
    expect(webhook.message(update), {'version': 1, 'type': 'note.updated', 'timestamp': '2026-11-04T14:01:02.000Z', 'data': {
      'note': {'id': '3f9a0c1d2e4b5a6978c1d2e3f4a5b6c7', 'source': 'typed', 'text': '# Receipt\n- [x] Paid',
        'recorded_at': '2026-11-04T14:01:00.000Z', 'created_at': '2026-11-04T14:01:00.000Z', 'device': device, 'place': null,
        'attachments': [{'id': 'f1', 'name': 'receipt.jpg', 'content_type': 'image/jpeg', 'size': 4}],
        'edited_at': '2026-11-04T14:11:00.000Z'}}});
    // A delete names the note by the id the receiver keeps it under: the phone's own.
    expect(webhook.message(deleted), {'version': 1, 'type': 'note.deleted', 'timestamp': '2026-11-04T14:01:02.000Z', 'data': {
      'note': {'id': '3f9a0c1d2e4b5a6978c1d2e3f4a5b6c7', 'deleted_at': '2026-11-04T14:01:02.000Z'}}});
    // A change carries the note's own created_at, though it was queued later, so a receiver keeps one row as it was.
    final later = OutboxItem(12, noteUpdate, update.body, destination: ownWebhook, createdAt: sent);
    expect(webhook.message(later)!['data']['note']['created_at'], webhook.message(note)!['data']['note']['created_at']);
    expect(webhook.message(file, [1, 2, 3, 4])!['data'], {'note_id': '3f9a0c1d2e4b5a6978c1d2e3f4a5b6c7', 'file': {'id': 'f1',
      'name': 'receipt.jpg', 'content_type': 'image/jpeg', 'size': 4, 'base64': 'AQIDBA=='}});
    // Only a workout carries its kind, distance and calories, null when the phone has none.
    final built = webhook.message(samples)!['data']['samples'] as List;
    expect(built, [{'id': isA<int>(), 'device': device, 'type': 'steps',
      'start': '2026-11-04T14:01:00.000Z', 'end': '2026-11-04T14:02:00.000Z', 'value': 120.0, 'unit': 'count',
      'source': 'com.apple.health'}, {'id': isA<int>(), 'device': device, 'type': 'workout', 'start': '2026-11-04T14:01:00.000Z',
      'end': '2026-11-04T14:33:00.000Z', 'value': 32.0, 'unit': 'min', 'source': 'com.apple.health', 'kind': 'running',
      'distance': 5100.0, 'calories': 410.0}]);
    // A sample's id comes from its type, start, end and source: the 90-day redo, or an id an older phone kept, keeps it.
    final [steps, workout] = [for (final sample in built) (sample as Map)['id'] as int];
    final old = item(20, 'health', {'samples': [{...(samples.body['samples'] as List)[1] as Map, 'id': 3}..remove('kind')
      ..remove('distance')]});
    expect(((webhook.message(old)!['data']['samples'] as List).single as Map), allOf(containsPair('kind', null),
      containsPair('distance', null), containsPair('calories', 410.0), containsPair('id', workout)));
    final longer = item(22, 'health', {'samples': [{...(samples.body['samples'] as List)[0] as Map, 'end': Date.recorded + 120000}]});
    final other = WebhookClient(hook, installId: '1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', deviceName: 'Android phone');
    expect([steps == workout, steps > 0 && steps < 1 << 48, (webhook.message(longer)!['data']['samples'] as List).single['id'] == steps,
      (other.message(samples)!['data']['samples'] as List).first['id'] == steps], [false, true, false, false]);
    // A night's id comes from the install id, its source and its start, so the same night sent again upserts it.
    final [watched, bedtime] = webhook.message(nights)!['data']['nights'] as List;
    expect(watched, {'id': isA<int>(), 'device': device, 'source': 'com.apple.health.watch', 'start': '2026-11-04T06:01:00.000Z',
      'end': '2026-11-04T14:01:00.000Z', 'asleep_at': '2026-11-04T06:16:00.000Z', 'woke_at': '2026-11-04T13:51:00.000Z',
      'minutes': {'asleep': 435.0, 'core': 250.0, 'deep': 75.0, 'rem': 110.0, 'awake': 25.0}, 'stages': [
        {'stage': 'core', 'start': '2026-11-04T06:16:00.000Z', 'end': '2026-11-04T07:06:00.000Z'},
        {'stage': 'deep', 'start': '2026-11-04T07:06:00.000Z', 'end': '2026-11-04T08:21:00.000Z'}]});
    expect([(bedtime as Map)['asleep_at'], bedtime['woke_at'], bedtime['stages'], bedtime['id'] == (watched as Map)['id']],
      [null, null, isEmpty, false]);
    expect(webhook.message(item(21, nightsRoute, {'nights': []})), isNull);
    expect(webhook.message(points)!['data'], {'points': [{'id': 2, 'device': device, 'at': '2026-11-04T14:01:00.000Z',
      'lat': 43.65, 'lon': -79.38, 'accuracy': 12.0, 'place': 'King St W'}]});
    // A stay or trip's id comes from the install id, its kind and its start, so its end, sent later, upserts it.
    final [cafe, ride, open] = webhook.message(stays)!['data']['stays'] as List;
    expect(cafe, {'id': isA<int>(), 'device': device, 'kind': 'stay', 'start': '2026-11-04T13:01:00.000Z',
      'end': '2026-11-04T14:01:00.000Z', 'ongoing': false, 'lat': 43.65, 'lon': -79.38, 'name': 'Cafe Nero',
      'address': 'King St W', 'event': 'Coffee with Sam', 'source': 'calendar', 'mode': null, 'km': null});
    expect(ride, {'id': isA<int>(), 'device': device, 'kind': 'trip', 'start': '2026-11-04T14:01:00.000Z',
      'end': '2026-11-04T14:21:00.000Z', 'ongoing': false, 'lat': null, 'lon': null, 'name': null, 'address': null, 'event': null,
      'source': null, 'mode': 'cycling', 'km': 4.2});
    expect([(open as Map)['ongoing'], open['source'], open['address']], [true, 'point', null]);
    final closed = (webhook.message(item(17, 'stays', {'stays': [{...(stays.body['stays'] as List)[2] as Map, 'ongoing': null}]}))!
      ['data']['stays'] as List).single as Map;
    expect([closed['id'], closed['ongoing'], (cafe as Map)['id'] == (ride as Map)['id']], [open['id'], false, false]);
    expect(webhook.message(item(18, 'stays', {'stays': []})), isNull);
    final [changed, removed] = webhook.message(calendar)!['data']['events'] as List;
    expect(changed, {'id': isA<int>(), 'status': 'changed', 'device': device, 'key': 'work:a:${Date.recorded}',
      'calendar': 'Work', 'title': 'Board meeting', 'start': '2026-11-04T14:01:00.000Z', 'end': '2026-11-04T15:01:00.000Z',
      'all_day': false, 'location': 'Room 4', 'notes': null, 'url': null,
      'people': [{'name': 'Sam', 'email': 'sam@example.com', 'organizer': true}]});
    // A removed event keeps only its key; its start comes from the key.
    expect(removed, {'id': isA<int>(), 'status': 'removed', 'device': device, 'key': 'work:b:${Date.recorded}',
      'calendar': null, 'title': null, 'start': '2026-11-04T14:01:00.000Z', 'end': '2026-11-04T14:01:00.000Z',
      'all_day': false, 'location': null, 'notes': null, 'url': null, 'people': []});
    // Each change of one occurrence has the same id, so a receiver upserts by it; another occurrence has its own.
    final again = webhook.message(item(14, 'calendar', {'events': [], 'removed': ['work:a:${Date.recorded}']}))!;
    final id = (again['data']['events'] as List).single['id'] as int;
    expect([id, id < 1 << 48, id == (removed as Map)['id']], [(changed as Map)['id'], true, false]);
    // A note with no place and no files has place null and no list.
    final bare = webhook.message(item(11, 'notes', {'clientId': 'a' * 32, 'text': 'Plain', 'createdAt': Date.recorded}))!;
    expect((bare['data'] as Map)['note'], allOf(containsPair('place', null), isNot(contains('attachments'))));
    // An empty batch needs no message.
    expect(webhook.message(item(12, 'health', {'samples': []})), isNull);
    // A photo from *Photos*: its own client id, time, place and JPEG, in the server's photo.created shape.
    expect(webhook.photoMessage(photo, [0xff, 0xd8, 0xff, 0xd9]), {'version': 1, 'type': 'photo.created',
      'timestamp': '2026-11-04T14:01:02.000Z', 'data': {'photo': {'id': photo.clientId, 'device': device,
        'taken_at': '2026-11-04T13:58:00.000Z', 'place': {'lat': 38.7139, 'lon': -9.1394}, 'width': 1600, 'height': 1200,
        'content_type': 'image/jpeg', 'size': 4, 'base64': '/9j/2Q=='}}});
    final placeless = QueuedPhoto(clientId: 'p' * 8, assetId: 'a', takenAt: queued, width: 1, height: 1, path: 'p');
    expect((webhook.photoMessage(placeless, [1])['data'] as Map)['photo'], containsPair('place', null));
  });

  test('signs each message, and a retry sends the same webhook-id and body', () async {
    final server = FakeServer((_) => http.Response('', 503));
    final webhook = client(server);
    for (var round = 0; round < 2; round++) {
      await expectLater(webhook.send(note), throwsA(isA<ApiException>().having((error) => error.status, 'status', 503)));
    }
    final [first, second] = server.requests;
    expect([first.url.toString(), first.method, first.headers['webhook-id'], first.headers['webhook-timestamp']],
      [hook.address, 'POST', '$installId:7', '${sent.millisecondsSinceEpoch ~/ 1000}']);
    expect([second.headers['webhook-id'], second.body], [first.headers['webhook-id'], first.body]);
    expect([signed(first), signed(second)], [true, true]);
    expect(first.headers.keys.map((name) => name.toLowerCase()), isNot(contains('authorization')));
  });

  test('counts only 2xx as sent; a 413 drops a file only; 400, 401 and no answer keep the upload', () async {
    Future<Failure?> answer(OutboxItem upload, Object status) async {
      final server = FakeServer((request) => status is int ? http.Response('', status) : throw const SocketException('none'));
      try {
        upload.route == 'attachment' ? await client(server).sendFile(upload, [1]) : await client(server).send(upload);
        return null;
      } on ApiException catch (error) {
        return error.failure;
      }
    }
    expect([await answer(note, 200), await answer(note, 204), await answer(file, 202)], [null, null, null]);
    expect(await answer(file, 413), Failure.rejected);
    for (final status in [413, 400, 401, 404, 500, 503, 'none']) {
      expect(await answer(note, status), Failure.offline, reason: '$status');
    }
    expect(await answer(file, 400), Failure.offline);
  });

  test('Send a test sends a signed webhook.test and gives back the status, or null for no answer', () async {
    final server = FakeServer((_) => http.Response('', 204));
    expect(await client(server).test(), 204);
    final request = server.requests.single;
    expect([signed(request), jsonDecode(request.body)['type']], [true, 'webhook.test']);
    expect(await client(FakeServer((_) => http.Response('', 401))).test(), 401);
    expect(await client(FakeServer((_) => throw const SocketException('none'))).test(), isNull);
  });

  test('makes a secret a Standard Webhooks library takes', () {
    final secret = makeWebhookSecret();
    expect(secret, matches(RegExp(r'^whsec_[A-Za-z0-9+/]{43}=$')));
    expect(makeWebhookSecret(), isNot(secret));
  });

  test('flush in webhook mode: a 503 keeps all in order, a 413 file is dropped and named, a 400 is kept', () async {
    final store = memoryStore();
    addTearDown(store.close);
    final folder = tempFolder();
    File('${folder.path}/f1.jpg').writeAsBytesSync([1, 2]);
    await store.moveOutbox(ownWebhook);
    await store.addNote(LocalNote(clientId: 'n1', text: 'With a file', createdAt: queued, attachments: const [
      Attachment(id: 'f1', name: 'big.jpg', type: 'image/jpeg', size: 2, path: 'f1.jpg')]), send: true);
    await store.addNote(LocalNote(clientId: 'n2', text: 'After', createdAt: queued), send: true);
    expect({for (final upload in await store.outbox()) upload.destination}, {ownWebhook});
    var status = 503;
    final server = FakeServer((request) => http.Response('', jsonDecode(request.body)['type'] == 'note.file' ? 413 : status));
    Future<FlushResult> round() => flush(store, client(server), clock: () => sent, folder: () async => folder);

    expect((await round()).failure, Failure.offline);
    expect([(await store.outbox()).length, jsonDecode((await store.get(webhookProblemKey))!)], [3, {'at': sent.millisecondsSinceEpoch,
      'status': 503}]);
    status = 400;
    expect((await round()).failure, Failure.offline);
    expect((await store.outbox()).length, 3);
    status = 200;
    final result = await round();
    expect([result.sent, result.dropped, result.failure], [2, 1, null]);
    expect([for (final request in server.requests.skip(2)) jsonDecode(request.body)['type']],
      ['note.created', 'note.file', 'note.created']);
    expect(jsonDecode((await store.get(webhookProblemKey))!), {'at': sent.millisecondsSinceEpoch, 'status': 413, 'file': 'big.jpg'});
    expect([for (final kept in await store.notes()) kept.sentAt?.millisecondsSinceEpoch], [for (var i = 0; i < 2; i++) sent.millisecondsSinceEpoch]);
    expect(await store.waiting(), 0);
  });

  test('flush leaves an upload for another place where it is, and sends it once it is moved', () async {
    final store = memoryStore();
    addTearDown(store.close);
    await store.addNote(LocalNote(clientId: 'n1', text: 'Queued for the server', createdAt: queued), send: true);
    final server = FakeServer();
    final skipped = await flush(store, client(server));
    expect([skipped.failure, skipped.sent, server.requests, (await store.outbox()).length], [isNull, 0, isEmpty, 1]);
    await store.moveOutbox(ownWebhook);
    expect((await flush(store, client(server))).sent, 1);
  });

  test('a switch to the webhook in the middle of a round sends nothing more to the server, and keeps the rest', () async {
    final store = memoryStore();
    addTearDown(store.close);
    for (final id in ['n1', 'n2', 'n3']) {
      await store.addNote(LocalNote(clientId: id, text: 'Note $id', createdAt: queued), send: true);
    }
    final server = FakeServer()..hold = Completer<void>();
    // A background round has no keepGoing: only the outbox itself can stop it.
    final round = flush(store, server.api(connection));
    await pumpEventQueue();
    expect(server.requests.length, 1);
    await store.moveOutbox(ownWebhook);
    server.hold!.complete();
    final result = await round;
    expect([result.sent, result.failure], [1, Failure.offline]);
    expect([for (final request in server.requests) jsonDecode(request.body)['clientId']], ['n1']);
    expect([for (final upload in await store.outbox()) (upload.body['clientId'], upload.destination)],
      [('n2', ownWebhook), ('n3', ownWebhook)]);
    final hookServer = FakeServer((_) => http.Response('', 204));
    expect((await flush(store, client(hookServer))).sent, 2);
    expect(await store.waiting(), 0);
  });

  test('flush stops at an upload gone since the round listed it', () async {
    final store = memoryStore();
    addTearDown(store.close);
    await store.moveOutbox(ownWebhook);
    await store.addNote(LocalNote(clientId: 'n1', text: 'First', createdAt: queued), send: true);
    await store.addNote(LocalNote(clientId: 'n2', text: 'Second', createdAt: queued), send: true);
    final second = (await store.outbox()).last.id;
    final server = FakeServer((_) => http.Response('', 204))..hold = Completer<void>();
    final round = flush(store, client(server));
    await pumpEventQueue();
    await store.done(second);
    server.hold!.complete();
    expect([(await round).sent, server.requests.length], [1, 1]);
  });

  // The worker's format.test.ts parses each of these with the server's schema and checks its signature. A change to
  // what the phone sends fails here first: run with WEBHOOK_FIXTURES_WRITE=1 to write them again, then run that test.
  test('writes one of each message to the fixtures the server checks', () async {
    final folder = Directory('test/fixtures/webhook');
    final server = FakeServer((_) => http.Response('', 204));
    final webhook = client(server);
    await webhook.send(note);
    await webhook.send(update);
    await webhook.send(deleted);
    await webhook.sendFile(file, [1, 2, 3, 4]);
    await webhook.send(samples);
    await webhook.send(points);
    await webhook.send(stays);
    await webhook.send(nights);
    await webhook.send(calendar);
    await webhook.sendPhoto(photo, [0xff, 0xd8, 0xff, 0xd9]);
    await webhook.test();
    for (final request in server.requests) {
      final type = jsonDecode(request.body)['type'] as String;
      final fixture = '${const JsonEncoder.withIndent('  ').convert({'secret': fixtureSecret, 'headers': {
        for (final name in ['webhook-id', 'webhook-timestamp', 'webhook-signature']) name: request.headers[name]},
        'body': request.body})}\n';
      final path = File('${folder.path}/$type.json');
      if (Platform.environment['WEBHOOK_FIXTURES_WRITE'] == '1') {
        path
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(fixture);
      }
      expect(path.readAsStringSync(), fixture, reason: '$type changed: run with WEBHOOK_FIXTURES_WRITE=1');
    }
  });
}
