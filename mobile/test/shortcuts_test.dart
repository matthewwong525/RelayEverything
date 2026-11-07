import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/controller.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/shortcuts/bridge.dart';

import 'fakes.dart';

final now = DateTime.fromMillisecondsSinceEpoch(1793797200000);

void main() {
  late Store store;
  late Directory folder;
  late FakeServer server;
  late MemoryStorage storage;
  late FakePlaces places;

  setUp(() {
    store = memoryStore();
    folder = tempFolder();
    server = noNetwork();
    storage = MemoryStorage();
    places = FakePlaces();
  });
  tearDown(() => store.close());

  RelayController controller() => RelayController(store: store, vault: KeyVault(storage), places: places, health: FakeHealth(),
    apiFor: server.api, clock: () => now, folder: () async => folder);

  /// A file a shortcut gave, as Swift copies it into the inbox's folder for its note; its path from the support folder.
  String given(String id, String name, List<int> bytes) {
    File('${folder.path}/shortcuts-inbox/$id/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return 'shortcuts-inbox/$id/$name';
  }

  group('Add a note', () {
    test('keeps words and files as a note, moves the files into the app, and gives the note back', () async {
      final relay = controller();
      await relay.load();
      final bridge = ShortcutsBridge(relay, wait: Duration.zero);
      final id = 'a' * 32;
      final note = await bridge.handle(MethodCall('add', {
        'id': id, 'text': 'bug in checkout', 'createdAt': now.millisecondsSinceEpoch,
        'files': [{'path': given(id, '1-shot.png', [1, 2]), 'name': 'Screenshot.png', 'type': 'image/png'}],
      })) as Map;
      expect([note['id'], note['text'], note['kind'], note['createdAt'], note['place'], note['message']],
        [id, 'bug in checkout', 'typed', now.millisecondsSinceEpoch, null, null]);
      final file = (note['files'] as List).single as Map;
      expect([file['name'], file['type']], ['Screenshot.png', 'image/png']);
      expect(file['path'], startsWith('${folder.path}/attachments/'));
      expect(File(file['path'] as String).readAsBytesSync(), [1, 2]);
      expect(File('${folder.path}/shortcuts-inbox/$id/1-shot.png').existsSync(), isFalse);
      expect(relay.entries.single.files.single.picture, isTrue);
      // The same note again, such as an answer that came late, keeps one note.
      await bridge.handle(MethodCall('add', {'id': id, 'text': 'bug in checkout'}));
      expect(relay.entries, hasLength(1));
      expect(server.requests, isEmpty);
    });

    test('takes words alone or files alone, and refuses nothing at all and keeps nothing', () async {
      final relay = controller();
      await relay.load();
      final bridge = ShortcutsBridge(relay, wait: Duration.zero);
      await bridge.handle(const MethodCall('add', {'text': 'At work'}));
      await bridge.handle(MethodCall('add', {'files': [{'path': given('x', 'a.pdf', [3]), 'name': 'a.pdf', 'type': ''}]}));
      expect([for (final entry in relay.entries) (entry.text, entry.files.length)], unorderedEquals([('At work', 0), ('', 1)]));
      expect(relay.entries.firstWhere((entry) => entry.files.isNotEmpty).files.single.type, 'application/pdf');
      for (final empty in [const <String, Object?>{}, {'text': '  ', 'files': <Object?>[]}]) {
        await expectLater(bridge.handle(MethodCall('add', empty)),
          throwsA(isA<PlatformException>().having((error) => error.message, 'message', 'Give the note words or a file.')));
      }
      expect(relay.entries, hasLength(2));
    });

    test('pins the note as a typed note is pinned, while Pin notes is on', () async {
      final relay = controller();
      await relay.load();
      await relay.setPinNotes(true);
      places.pin = Pin(at: now, lat: 43.65, lon: -79.38, accuracy: 10);
      final note = await ShortcutsBridge(relay).handle(const MethodCall('add', {'text': 'Fed the cat'})) as Map;
      expect(note['text'], 'Fed the cat');
      expect(relay.entries.single.place, 'Pinned');
    });

    test('with sending on, the note and its file go before the action answers', () async {
      server = FakeServer();
      final relay = controller();
      await relay.load();
      expect(await relay.connect(pageCode), isNull);
      await relay.startSending(sendEarlier: false);
      await relay.sync();
      server.requests.clear();
      await ShortcutsBridge(relay).handle(MethodCall('add', {
        'text': 'bug in checkout', 'files': [{'path': given('y', 'shot.png', [1]), 'name': 'shot.png', 'type': 'image/png'}],
      }));
      expect(server.routes, ['notes', 'attachments']);
      expect(relay.entries.single.sent, isTrue);
    });
  });

  group('Get notes', () {
    test('gives the newest notes first, by count, words and start time, and asks no server', () async {
      final relay = controller();
      await relay.load();
      for (final (hour, text) in ['Buy groceries', 'Fed the cat', 'groceries again'].indexed) {
        await relay.keepNote(text, createdAt: now.add(Duration(hours: hour)));
      }
      final bridge = ShortcutsBridge(relay);
      Future<List<String>> texts(Map<String, Object?> arguments) async =>
        [for (final note in await bridge.handle(MethodCall('get', arguments)) as List) (note as Map)['text'] as String];
      expect(await texts({'limit': 2}), ['groceries again', 'Fed the cat']);
      expect(await texts({'query': 'GROCERIES'}), ['groceries again', 'Buy groceries']);
      expect(await texts({'since': now.add(const Duration(hours: 1)).millisecondsSinceEpoch}), ['groceries again', 'Fed the cat']);
      expect(await texts({}), hasLength(3));
      expect(server.requests, isEmpty);
    });
  });

  group('the inbox', () {
    test('a note a shortcut left is kept on the next open, once, with its files, its own time and no place', () async {
      final id = 'b' * 32;
      final made = now.subtract(const Duration(hours: 2));
      final receipt = given(id, '1-receipt.pdf', [7, 7]);
      File('${folder.path}/shortcuts-inbox/$id.json').writeAsStringSync(jsonEncode({
        'id': id, 'text': 'Receipt', 'createdAt': made.millisecondsSinceEpoch,
        'files': [{'path': receipt, 'name': 'receipt.pdf', 'type': 'application/pdf'}],
      }));
      File('${folder.path}/shortcuts-inbox/broken.json').writeAsStringSync('not json');
      await store.set(settingsKey, const Settings(pinNotes: true).encode());
      places.pin = Pin(at: now, lat: 1, lon: 1, accuracy: 1);
      final relay = controller();
      await relay.load();
      final entry = relay.entries.single;
      expect([entry.text, entry.at, entry.place], ['Receipt', made, null]);
      expect(entry.files.single.name, 'receipt.pdf');
      expect(File(entry.files.single.path).readAsBytesSync(), [7, 7]);
      expect(Directory('${folder.path}/shortcuts-inbox').listSync(), isEmpty);
      // The engine's late answer with the same id keeps no second note, and a second open finds nothing left.
      await ShortcutsBridge(relay, wait: Duration.zero).handle(MethodCall('add', {'id': id, 'text': 'Receipt'}));
      await controller().load();
      expect(await store.notes(), hasLength(1));
      expect(server.requests, isEmpty);
    });
  });
}
