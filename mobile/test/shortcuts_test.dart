import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/controller.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/shortcuts/bridge.dart';
import 'package:relay_app/shortcuts/inbox.dart';
import 'package:relay_app/voice/recorder.dart';

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

  group('a recording', () {
    late FakeTranscriber transcriber;
    late List<String> notices;
    setUp(() async {
      transcriber = FakeTranscriber()..answer = 'Call the plumber about the kitchen tap';
      notices = [];
      await placeModel(folder);
    });

    /// The app's own engine, with the speech model and the words.
    RelayController app() {
      final relay = RelayController(store: store, vault: KeyVault(storage), places: places, health: FakeHealth(),
        apiFor: server.api, clock: () => now, folder: () async => folder,
        voice: fakeVoice(folder, ModelServer(), clock: () => now, transcriber: transcriber));
      relay.notices.listen(notices.add);
      return relay;
    }

    /// A recording as Swift writes it for note [id]: a WAV in the inbox's folder for the note; its path from the support
    /// folder.
    String recorded(String id) => given(id, 'voice.wav', [82, 73, 70, 70]);

    List<String> recordings() => [
      if (Directory('${folder.path}/voice').existsSync())
        for (final file in Directory('${folder.path}/voice').listSync()) file.uri.pathSegments.last,
    ];

    test('with the app closed, it is kept as a voice note with the typed words, and the next open writes its words after them',
      () async {
      // The background engine has no speech parts.
      final engine = controller();
      await engine.load();
      final id = 'c' * 32;
      final note = await ShortcutsBridge(engine, wait: Duration.zero).handle(MethodCall('add', {
        'id': id, 'text': ' Note @ 7:07 PM ', 'createdAt': now.millisecondsSinceEpoch, 'files': <Object?>[],
        'recording': {'path': recorded(id), 'durationMs': 12000},
      })) as Map;
      expect([note['id'], note['text'], note['kind'], note['files']], [id, 'Note @ 7:07 PM', 'voice', isEmpty]);
      final waiting = engine.entries.single;
      expect([waiting.voice, waiting.writing, waiting.text, waiting.length, waiting.recording],
        [true, true, 'Note @ 7:07 PM', const Duration(seconds: 12), 'voice/$id.wav']);
      final relay = app();
      await relay.load();
      await relay.wordsWritten();
      final written = relay.entries.single;
      expect([written.voice, written.writing, written.text],
        [true, false, 'Note @ 7:07 PM\nCall the plumber about the kitchen tap']);
      expect([transcriber.heard, recordings()], [['$id.wav'], ['$id.wav']]);
      expect(File('${folder.path}/$inboxFolder/$id/voice.wav').existsSync(), isFalse);
      expect(server.requests, isEmpty);
    });

    test('with the app open, its words are written at once, and a second run of the same id keeps one note', () async {
      final relay = app();
      await relay.load();
      final bridge = ShortcutsBridge(relay, wait: Duration.zero);
      final id = 'd' * 32;
      final request = {'id': id, 'text': '', 'recording': {'path': recorded(id), 'durationMs': 3000}};
      await bridge.handle(MethodCall('add', request));
      await relay.wordsWritten();
      await bridge.handle(MethodCall('add', request));
      await relay.wordsWritten();
      expect([for (final entry in relay.entries) (entry.voice, entry.text)], [(true, 'Call the plumber about the kitchen tap')]);
      expect(transcriber.heard, ['$id.wav']);
    });

    test('with no speech, typed words keep the note and its recording; with none, the note goes', () async {
      transcriber.answer = '';
      final relay = app();
      await relay.load();
      final bridge = ShortcutsBridge(relay, wait: Duration.zero);
      final labelled = 'e' * 32, bare = 'f' * 32;
      await bridge.handle(MethodCall('add', {'id': labelled, 'text': 'Note @ 7:07 PM',
        'recording': {'path': recorded(labelled), 'durationMs': 2000}}));
      await bridge.handle(MethodCall('add', {'id': bare, 'recording': {'path': recorded(bare), 'durationMs': 2000}}));
      await relay.wordsWritten();
      final kept = relay.entries.single;
      expect([kept.voice, kept.writing, kept.failed, kept.text, kept.recording],
        [true, false, false, 'Note @ 7:07 PM', 'voice/$labelled.wav']);
      expect(recordings(), ['$labelled.wav']);
      await pumpEventQueue();
      expect(notices, ['No speech heard. Nothing was saved.']);
    });

    test('with sending and pins on, the note goes once, with its place and its words after the typed ones', () async {
      server = FakeServer();
      final relay = app();
      await relay.load();
      expect(await relay.connect(pageCode), isNull);
      await relay.startSending(sendEarlier: false);
      await relay.setPinNotes(true);
      await relay.sync();
      server.requests.clear();
      places.pin = Pin(at: now, lat: 43.65, lon: -79.38, accuracy: 10, place: 'Ossington Ave');
      transcriber.hold = Completer();
      final id = 'a1' * 16;
      await ShortcutsBridge(relay, wait: const Duration(seconds: 1)).handle(MethodCall('add', {
        'id': id, 'text': 'Note @ 7:07 PM', 'recording': {'path': recorded(id), 'durationMs': 4000}}));
      // The pin is in, but the words are not: nothing goes yet.
      expect(server.routes, isEmpty);
      transcriber.hold!.complete('Call the plumber');
      await relay.wordsWritten();
      final sent = [
        for (final request in server.requests) if (request.url.path.endsWith('notes')) jsonDecode(request.body) as Map,
      ];
      expect([for (final note in sent) (note['clientId'], note['text'], note['place'])],
        [(id, 'Note @ 7:07 PM\nCall the plumber', 'Ossington Ave')]);
      expect(relay.entries.single.sent, isTrue);
    });

    test('left in the inbox, it becomes a voice note on the next open, with its recording', () async {
      final id = 'a2' * 16;
      final made = now.subtract(const Duration(hours: 1));
      File('${folder.path}/shortcuts-inbox/$id.json').writeAsStringSync(jsonEncode({
        'id': id, 'text': 'Note @ 6:07 PM', 'createdAt': made.millisecondsSinceEpoch, 'files': <Object?>[],
        'recording': {'path': recorded(id), 'durationMs': 5000},
      }));
      final relay = app();
      await relay.load();
      await relay.wordsWritten();
      final entry = relay.entries.single;
      expect([entry.voice, entry.text, entry.at, entry.place, entry.recording],
        [true, 'Note @ 6:07 PM\nCall the plumber about the kitchen tap', made, null, 'voice/$id.wav']);
      expect(recordings(), ['$id.wav']);
      expect(Directory('${folder.path}/shortcuts-inbox').listSync(), isEmpty);
    });

    test('kept while the app sweeps for stray recordings, its recording is not deleted as stray', () async {
      final id = 'a7' * 16;
      late RelayController relay;
      // The shortcut runs after the sweep reads the kept recordings, and before it lists the folder.
      final recorder = _SweepRecorder(folder, clock: () => now, beforeSweep: () async {
        await relay.keepRecording('Note @ 7:07 PM', recording: recorded(id), durationMs: 2000, clientId: id, pin: false);
      });
      relay = RelayController(store: store, vault: KeyVault(storage), places: places, health: FakeHealth(),
        apiFor: server.api, clock: () => now, folder: () async => folder,
        voice: VoiceParts(model: speechModel(folder, ModelServer()), recorder: recorder, transcriber: transcriber,
          player: FakePlayer()));
      await relay.load();
      await relay.wordsWritten();
      expect(recorder.swept, isTrue);
      expect(recordings(), ['$id.wav']);
      final entry = relay.entries.single;
      expect([entry.voice, entry.text, entry.recording],
        [true, 'Note @ 7:07 PM\nCall the plumber about the kitchen tap', 'voice/$id.wav']);
    });

    test('a recording with a photo stays plain files, as Swift gives it, and so does one with a stray recording too',
      () async {
      final relay = app();
      await relay.load();
      final bridge = ShortcutsBridge(relay, wait: Duration.zero);
      final id = 'a3' * 16, other = 'a4' * 16;
      await bridge.handle(MethodCall('add', {'id': id, 'text': 'Kitchen', 'files': [
        {'path': given(id, '1-Recording.m4a', [1]), 'name': 'Recording.m4a', 'type': 'audio/mp4'},
        {'path': given(id, '2-tap.png', [2]), 'name': 'tap.png', 'type': 'image/png'},
      ]}));
      await bridge.handle(MethodCall('add', {'id': other, 'text': 'Both',
        'files': [{'path': given(other, '1-tap.png', [3]), 'name': 'tap.png', 'type': 'image/png'}],
        'recording': {'path': recorded(other), 'durationMs': 1000}}));
      await relay.wordsWritten();
      expect([for (final entry in relay.entries) '${entry.voice} ${entry.text}: ${entry.files.map((file) => file.name).join(', ')}'],
        unorderedEquals(['false Kitchen: Recording.m4a, tap.png', 'false Both: tap.png']));
      expect(transcriber.heard, isEmpty);
    });

    test('a recording that is not there keeps the typed words alone, or nothing', () async {
      final relay = app();
      await relay.load();
      final bridge = ShortcutsBridge(relay, wait: Duration.zero);
      final id = 'a5' * 16;
      final note = await bridge.handle(MethodCall('add', {'id': id, 'text': 'Kept',
        'recording': {'path': '$inboxFolder/$id/voice.wav', 'durationMs': 1000}})) as Map;
      expect([note['kind'], note['text']], ['typed', 'Kept']);
      await expectLater(bridge.handle(MethodCall('add', {'id': 'a6' * 16,
        'recording': {'path': '$inboxFolder/${'a6' * 16}/voice.wav', 'durationMs': 1000}})), throwsA(isA<PlatformException>()));
      expect(relay.entries, hasLength(1));
    });
  });
}

/// A recorder that runs [beforeSweep] once, when the sweep for stray recordings asks for the voice folder: after it reads
/// the kept recordings, before it lists the folder.
class _SweepRecorder extends VoiceRecorder {
  _SweepRecorder(Directory folder, {required DateTime Function() clock, required this.beforeSweep})
    : super(microphone: FakeMicrophone(), folder: () async => folder, clock: clock);

  final Future<void> Function() beforeSweep;
  bool swept = false;

  @override
  Future<File> fileOf(String audioPath) async {
    if (audioPath == VoiceRecorder.pathOf('x') && !swept) {
      swept = true;
      await beforeSweep();
    }
    return super.fileOf(audioPath);
  }
}
