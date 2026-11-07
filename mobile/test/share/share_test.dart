import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:relay_app/controller.dart';
import 'package:relay_app/data/attachments.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/sender.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/share/draft.dart';
import 'package:relay_app/share/inbox.dart';
import 'package:relay_app/share/share_card.dart';
import 'package:relay_app/share/share_main.dart';
import 'package:relay_app/sync/background.dart';

import '../fakes.dart';

final now = DateTime.fromMillisecondsSinceEpoch(1793797200000);
const mb = 1024 * 1024;

NewFile file(String name, [int size = 1000]) => NewFile(path: '/shared/$name', name: name, size: size);

class FakeShareGroup implements ShareGroup {
  FakeShareGroup([this.group]);

  final Directory? group;
  final told = <Object?>[];

  @override
  Future<void> setSending(bool on) async => told.add(on);

  @override
  Future<Directory?> folder() async => group;
}

/// Leaves a note in [group]'s share inbox as the iPhone's card writes it, with each file's bytes.
Directory leave(Directory group, String id, {String text = 'read later', Map<String, List<int>> files = const {},
  bool sentNote = false, List<String> sentFiles = const []}) {
  final entry = Directory('${group.path}/$shareInboxFolder/$id')..createSync(recursive: true);
  var index = 0;
  final listed = <Map<String, Object?>>[];
  files.forEach((name, bytes) {
    index++;
    File('${entry.path}/$index-$name').writeAsBytesSync(bytes);
    listed.add({'id': '$index' * 32, 'name': name, 'type': '', 'size': bytes.length, 'file': '$index-$name'});
  });
  File('${entry.path}/note.json').writeAsStringSync(jsonEncode({'v': 1, 'clientId': id, 'text': text,
    'createdAt': now.millisecondsSinceEpoch, 'files': listed, 'sentNote': sentNote, 'sentFiles': sentFiles}));
  return entry;
}

void main() {
  group('a shared draft', () {
    test('a web page becomes your words, then its title and link', () {
      final draft = ShareDraft.of(subject: 'Ten rules for slow travel', url: 'https://example.com/slow-travel');
      expect(draft.noteText(' read later '), 'read later\nTen rules for slow travel\nhttps://example.com/slow-travel');
      // Android browsers share the address as the text, with the title as the subject.
      final android = ShareDraft.of(text: 'https://example.com/slow-travel', subject: 'Ten rules for slow travel');
      expect(android.noteText(''), 'Ten rules for slow travel\nhttps://example.com/slow-travel');
    });

    test('text becomes the note text, after your words', () {
      final draft = ShareDraft.of(text: 'Buy oat milk');
      expect([draft.noteText('from Sam'), draft.leftOut], ['from Sam\nBuy oat milk', null]);
    });

    test('photos and a file become files', () {
      final draft = ShareDraft.of(files: [file('IMG_2041.jpg'), file('IMG_2042.jpg')]);
      expect([for (final file in draft.files) file.name], ['IMG_2041.jpg', 'IMG_2042.jpg']);
      expect(draft.noteText('Paint colours for the hall'), 'Paint colours for the hall');
      expect(ShareDraft.of(files: [file('receipt.pdf')]).canSave(''), isTrue);
    });

    test('12 photos keep the first 10, and say so', () {
      final draft = ShareDraft.of(files: [for (var i = 1; i <= 12; i++) file('IMG_$i.jpg')]);
      expect([draft.files.length, draft.files.last.name], [10, 'IMG_10.jpg']);
      expect(draft.leftOut, 'A note holds up to 10 files. 2 files were not added.');
    });

    test('a video over 25 MB is left out, and Save is off with nothing else', () {
      final draft = ShareDraft.of(files: [file('clip.mov', 40 * mb)]);
      expect([draft.files, draft.leftOut], [isEmpty, 'clip.mov is over 25 MB, so it was not added.']);
      expect([draft.canSave('  '), draft.canSave('the clip from the party')], [false, true]);
    });

    test('Android hands over what it shared through relay/share', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('relay/share/test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
        'text': 'https://example.com/slow-travel', 'subject': 'Ten rules for slow travel',
        'files': [{'path': '/cache/shared/1-a.jpg', 'name': 'a.jpg', 'type': 'image/jpeg', 'size': 10},
          {'path': null, 'name': 'clip.mov', 'type': 'video/quicktime', 'size': 40 * mb}],
      });
      final draft = await sharedDraft(channel: channel);
      expect([draft.title, draft.url, draft.files.single.path, draft.files.single.move],
        ['Ten rules for slow travel', 'https://example.com/slow-travel', '/cache/shared/1-a.jpg', true]);
      expect(draft.leftOut, 'clip.mov is over 25 MB, so it was not added.');
    });
  });

  test('a shared note\'s body is the one in test/fixtures/shared-note.json, which the Swift tests read too', () {
    final note = LocalNote(clientId: '0f1e2d3c4b5a69788796a5b4c3d2e1f0',
      text: 'read on the train\nTen rules for slow travel\nhttps://example.com/slow-travel', createdAt: now, attachments: const [
        Attachment(id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90', name: 'IMG_2041.jpg', type: 'image/jpeg', size: 2202009,
          path: 'attachments/a1b2c3d4e5f60718293a4b5c6d7e8f90.jpg'),
        Attachment(id: '0918273645546372819aabbccddeeff0', name: 'receipt.pdf', type: 'application/pdf', size: 48213,
          path: 'attachments/0918273645546372819aabbccddeeff0.pdf'),
      ]);
    expect(note.toJson(), jsonDecode(File('test/fixtures/shared-note.json').readAsStringSync()));
  });

  group('the share inbox', () {
    late Store store;
    late Directory group;
    late Directory root;
    final id = 'c' * 32;

    setUp(() {
      store = memoryStore();
      group = tempFolder();
      root = tempFolder();
    });
    tearDown(() => store.close());

    Future<List<String>> routes() async => [for (final item in await store.outbox()) item.route];

    test('a note the card sent whole is kept as sent, with its files moved in, and nothing queued', () async {
      final entry = leave(group, id, files: {'a.jpg': [1, 2]}, sentNote: true, sentFiles: ['1' * 32]);
      expect(await drainShareInbox(group, root.path, store, send: true), 1);
      final note = (await store.notes()).single;
      expect([note.text, note.pin, note.sentAt, note.attachments.single.sentAt], ['read later', null, isNotNull, isNotNull]);
      expect(File('${root.path}/${note.attachments.single.path}').readAsBytesSync(), [1, 2]);
      expect([await routes(), entry.existsSync()], [isEmpty, false]);
    });

    test('a half-sent note queues only the files the card did not send', () async {
      leave(group, id, files: {'a.jpg': [1], 'b.pdf': [2]}, sentNote: true, sentFiles: ['1' * 32]);
      await drainShareInbox(group, root.path, store, send: true);
      expect(await routes(), ['attachment']);
      expect((await store.outbox()).single.body['id'], '2' * 32);
    });

    test('with sending off, a note stays on this phone, queued for nothing', () async {
      leave(group, id, files: {'a.jpg': [1]});
      await drainShareInbox(group, root.path, store, send: false);
      final note = (await store.notes()).single;
      expect([note.sentAt, note.queued, note.pin, await routes()], [null, false, null, isEmpty]);
      expect(await store.earlierCount(), 1);
    });

    test('with sending on, an unsent note queues the note, then its files', () async {
      leave(group, id, files: {'a.jpg': [1]});
      await drainShareInbox(group, root.path, store, send: true);
      expect(await routes(), ['notes', 'attachment']);
    });

    test('an entry it can not read moves to .bad, and a note it keeps already is kept once', () async {
      final bad = Directory('${group.path}/$shareInboxFolder/${'d' * 32}')..createSync(recursive: true);
      File('${bad.path}/note.json').writeAsStringSync('not a note');
      // A card still copying files is left alone.
      final copying = Directory('${group.path}/$shareInboxFolder/.tmp-${'e' * 32}')..createSync(recursive: true);
      leave(group, id);
      expect(await drainShareInbox(group, root.path, store, send: false, clock: () => now), 1);
      expect(Directory('${group.path}/$shareInboxFolder/.bad/${'d' * 32}-${now.millisecondsSinceEpoch}').existsSync(), isTrue);
      expect([bad.existsSync(), copying.existsSync()], [false, true]);
      leave(group, id);
      expect(await drainShareInbox(group, root.path, store, send: false), 0);
      expect(await store.notes(), hasLength(1));
    });

    test('a share taken just now is left to the drain that took it, however old the share is', () async {
      // A rename keeps the folder's own modified time: by that time, this share made 15 minutes ago looks abandoned.
      final later = DateTime.now().add(const Duration(minutes: 15));
      final taken = '${group.path}/$shareInboxFolder/.taking-$id-${later.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch}';
      leave(group, id).renameSync(taken);
      expect(await drainShareInbox(group, root.path, store, send: false, clock: () => later), 0);
      expect([Directory(taken).existsSync(), await store.notes()], [true, isEmpty]);
      // Ten minutes after the take, the drain that took it is gone: another takes it over and keeps it once.
      expect(await drainShareInbox(group, root.path, store, send: false,
        clock: () => later.add(const Duration(minutes: 10))), 1);
      expect([Directory(taken).existsSync(), await store.notes()], [false, hasLength(1)]);
    });

    test('a drain takes an entry under a name that holds the time of the take', () async {
      final bad = Directory('${group.path}/$shareInboxFolder/$id')..createSync(recursive: true);
      File('${bad.path}/note.json').writeAsStringSync(jsonEncode({'v': 1, 'clientId': 'd' * 32, 'text': 'x',
        'createdAt': 0, 'files': []}));
      expect(await drainShareInbox(group, root.path, store, send: false, clock: () => now), 0);
      // The entry's id comes from the taken name without its time, so .bad names it as the card did.
      expect(Directory('${group.path}/$shareInboxFolder/.bad/$id-${now.millisecondsSinceEpoch}').existsSync(), isTrue);
    });

    test('the hourly round keeps the inbox, then sends it', () async {
      final server = FakeServer();
      await store.set(settingsKey, const Settings(sending: true).encode());
      leave(group, id, files: {'a.jpg': [1]});
      expect(await backgroundRound(store, connection: connection, health: FakeHealth(), sender: Sender(server.api),
        share: FakeShareGroup(group), folder: () async => root), isTrue);
      expect(server.routes, ['notes', 'attachments']);
      expect((await store.notes()).single.sentAt, isNotNull);
    });
  });

  group('the app with a share card', () {
    late Store store;
    late MemoryStorage storage;
    late FakeServer server;
    late FakePlaces places;
    late FakeShareGroup share;
    late Directory inbox;
    late Directory root;

    setUp(() {
      store = memoryStore();
      storage = MemoryStorage();
      server = FakeServer();
      places = FakePlaces()..pin = Pin(at: now, lat: 43.6, lon: -79.3, accuracy: 10);
      inbox = tempFolder();
      root = tempFolder();
      share = FakeShareGroup(inbox);
    });
    tearDown(() => store.close());

    RelayController controller() => RelayController(store: store, vault: KeyVault(storage), places: places,
      health: FakeHealth(), apiFor: server.api, clock: () => now, folder: () async => root, share: share);

    test('tells the card whether it may send on load and each change, and never the key', () async {
      final relay = controller();
      await relay.load();
      expect(await relay.connect(code), isNull);
      expect(await relay.startSending(sendEarlier: false), isNull);
      expect(await relay.setServer('https://other.example.com'), isNull);
      await relay.disconnect();
      expect(share.told, [false, false, true, true, false, false]);
      expect(share.told.every((told) => told is bool), isTrue);
    });

    test('a shared note gets no place, even with Pin notes on', () async {
      final relay = controller();
      await relay.load();
      await relay.setPinNotes(true);
      await relay.keepNote('from the share card', pin: false);
      await relay.settled();
      expect([places.named, relay.entries.single.place], [isEmpty, null]);
    });

    test('keeps what the card left on load and on each return to the app', () async {
      leave(inbox, 'c' * 32, text: 'first');
      final relay = controller();
      await relay.load();
      expect([for (final entry in relay.entries) entry.text], ['first']);
      leave(inbox, 'd' * 32, text: 'second');
      await relay.resume();
      expect([for (final entry in relay.entries) entry.text], unorderedEquals(['first', 'second']));
      expect(server.requests, isEmpty);
    });

    test('on each return to the app, shows a note another engine kept, such as the Android share window', () async {
      server = noNetwork();
      final relay = controller();
      await relay.load();
      expect(relay.entries, isEmpty);
      // The Android share window saves through its own engine and controller, on the same store.
      final window = RelayController(store: store, vault: KeyVault(storage), places: places, health: FakeHealth(),
        apiFor: server.api, clock: () => now, folder: () async => root);
      await window.load(watch: false);
      await window.keepNote('from the share window', pin: false);
      await window.settled();
      expect(relay.entries, isEmpty);
      await relay.resume();
      expect([for (final entry in relay.entries) entry.text], ['from the share window']);
      expect(server.requests, isEmpty);
    });

    group('Save on Android', () {
      final draft = ShareDraft.of(subject: 'Ten rules for slow travel', url: 'https://example.com/slow-travel');

      test('with sending off keeps the note on this phone and sends nothing', () async {
        server = noNetwork();
        final relay = controller();
        await relay.load();
        expect(await saveShare(relay, draft, 'read later'), ShareOutcome.kept);
        expect([relay.entries.single.text, server.requests], [startsWith('read later\nTen rules'), isEmpty]);
      });

      test('with sending on sends the note before the card closes', () async {
        final relay = controller();
        await relay.load();
        await relay.connect(code);
        await relay.startSending(sendEarlier: false);
        await relay.settled();
        server.requests.clear();
        expect(await saveShare(relay, draft, ''), ShareOutcome.sent);
        expect(server.routes, ['notes']);
      });

      test('with no signal keeps the note, and the app sends it later', () async {
        server = FakeServer((_) => throw http.ClientException('no signal'));
        final relay = controller();
        await relay.load();
        await relay.connect(code);
        await relay.startSending(sendEarlier: false);
        expect(await saveShare(relay, draft, '', wait: const Duration(seconds: 2)), ShareOutcome.later);
        expect((await store.notes()).single.queued, isTrue);
      });
    });
  });

  group('the share card', () {
    Future<List<String>> pump(WidgetTester tester, ShareDraft draft, {required bool sending, ShareOutcome? outcome}) async {
      final closed = <String>[];
      await tester.pumpWidget(MaterialApp(home: ShareCard(draft: draft, sending: sending, linger: Duration.zero,
        save: (words) async => outcome!, close: () => closed.add('closed'))));
      return closed;
    }

    final page = ShareDraft.of(subject: 'Ten rules for slow travel', url: 'https://example.com/slow-travel');

    testWidgets('with sending on says it sends, then Sent, then closes', (tester) async {
      final closed = await pump(tester, page, sending: true, outcome: ShareOutcome.sent);
      expect(find.text(sendingOn), findsOneWidget);
      expect(find.text('Ten rules for slow travel'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text(sentNow), findsOneWidget);
      await tester.pumpAndSettle();
      expect(closed, ['closed']);
    });

    testWidgets('with sending off says the note stays on this phone', (tester) async {
      final closed = await pump(tester, page, sending: false, outcome: ShareOutcome.kept);
      expect(find.text(sendingOff), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect([find.text(sendingOff).evaluate().length, closed], [1, ['closed']]);
    });

    testWidgets('with no signal says the app sends it later', (tester) async {
      await pump(tester, page, sending: true, outcome: ShareOutcome.later);
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text(sendsLater), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('names a file it left out, and Save is off until you add words', (tester) async {
      final closed = await pump(tester, ShareDraft.of(files: [file('clip.mov', 40 * mb)]), sending: false);
      expect(find.text('clip.mov is over 25 MB, so it was not added.'), findsOneWidget);
      FilledButton save() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
      expect(save().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'the clip from the party');
      await tester.pump();
      expect(save().onPressed, isNotNull);
      await tester.tap(find.text('Cancel'));
      expect(closed, ['closed']);
    });
  });
}
