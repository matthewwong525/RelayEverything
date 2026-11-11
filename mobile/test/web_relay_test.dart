import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/web/space.dart';
import 'package:relay_app/web/web_relay.dart';

import 'fakes.dart' show FakePlayer;

final base = Uri.parse('https://relay.example.com/apps/relay/');

Map<String, dynamic> note(String id, {String? clientId, bool mine = false, String text = 'Words', int at = 1000,
  String device = 'iPhone', bool audio = false, String source = 'typed', List<Map<String, Object>> files = const []}) => {
  'id': id, 'clientId': clientId, 'mine': mine, 'source': source, 'text': text, 'recordedAt': at, 'editedAt': null,
  'device': device, 'audio': audio, 'place': {'lat': 1.0, 'lon': 2.0, 'accuracy': null, 'name': 'Home', 'from': 'phone'},
  'attachments': files,
};

/// A server that answers each route from [routes], keyed by method and route, and keeps each request.
class Server {
  Server(this.routes);

  final Map<String, Object Function(http.Request request)> routes;
  final requests = <http.Request>[];

  http.Client get client => MockClient((request) async {
    requests.add(request);
    final route = '${request.method} ${request.url.path.replaceFirst('/apps/relay/', '')}';
    final answer = routes[route]?.call(request) ?? {'error': {'message': 'No route $route'}};
    if (answer is http.Response) return answer;
    return http.Response(jsonEncode(answer), routes.containsKey(route) ? 200 : 404, headers: {'content-type': 'application/json'});
  });

  List<String> get calls => [for (final request in requests) '${request.method} ${request.url.path.split('/').last}'];
}

void main() {
  late Server server;
  late WebRelay relay;
  final opened = <Uri>[];
  late FakePlayer player;
  final lastSends = <(String, Uri, String?)>[];

  WebRelay make() {
    late final WebRelay made;
    made = WebRelay(client: SpaceClient(base: base, client: server.client, onSignedOut: () => made.signedOut()),
      opener: (address) async {
        opened.add(address);
        return true;
      },
      player: player = FakePlayer(), clock: () => DateTime.fromMillisecondsSinceEpoch(5000),
      lastSend: (method, address, [json]) => lastSends.add((method, address, json)));
    return made;
  }

  setUp(() {
    opened.clear();
    lastSends.clear();
    server = Server({
      'GET api/account': (_) => {'email': 'ana@example.com'},
      'GET api/notes': (request) => request.url.queryParameters['since'] == '0'
        ? {'notes': [note('n1', at: 1000), note('n2', clientId: 'web-note-1', mine: true, device: 'Web', at: 2000)], 'next': 7, 'more': true}
        : {'notes': [note('n3', source: 'ring', audio: true, device: 'Email', at: 3000, files: [
            {'id': 'file-0001', 'name': 'card.png', 'type': 'image/png', 'size': 10, 'ready': true},
            {'id': 'file-0002', 'name': 'late.pdf', 'type': 'application/pdf', 'size': 10, 'ready': false},
          ])], 'next': 9, 'more': false},
      'POST api/notes': (_) => {'id': 'n9', 'added': true},
      'PATCH api/notes': (_) => {'id': 'n1', 'updated': true},
      'DELETE api/notes': (_) => {'id': 'n1', 'deleted': true},
      'POST api/attachments': (_) => {'ok': true, 'added': true},
      'POST sign-in/out': (_) => <String, Object>{},
    });
    relay = make();
  });

  test('is the web platform, signs in by the cookie, and reads every page of notes, newest first', () async {
    expect(relay.platform, RelayPlatform.web);
    expect(relay.signInState, WebSignIn.checking);
    await relay.start();
    expect(relay.signInState, WebSignIn.signedIn);
    expect(relay.email, 'ana@example.com');
    expect(relay.connected, isTrue);
    expect([for (final entry in relay.entries) entry.id], ['n3', 'web-note-1', 'n1']);
    expect(server.requests[1].url.queryParameters, {'since': '0'});
    expect(server.requests[2].url.queryParameters, {'since': '7'});
    final ring = relay.entries.first;
    expect(ring.voice, isTrue);
    expect(ring.from, 'Email');
    expect(ring.place, 'Home');
    expect(ring.recording, 'https://relay.example.com/apps/relay/api/audio?id=n3');
    expect(ring.files.first.url, 'https://relay.example.com/apps/relay/api/attachment?id=file-0001');
    expect(ring.files.first.ready, isTrue);
    expect(ring.files.last.ready, isFalse);
    expect(relay.entries[1].from, isNull, reason: 'the Web device wrote it here');
    expect(relay.entries.last.from, 'iPhone');
    expect(relay.status, SyncStatus.synced);
  });

  test('a later read asks from the last change and drops a deleted note', () async {
    await relay.start();
    server.routes['GET api/notes'] = (_) => {'notes': [{'id': 'n1', 'clientId': null, 'deleted': true}], 'next': 10, 'more': false};
    await relay.pullNotes();
    expect(server.requests.last.url.queryParameters, {'since': '9', 'deleted': '1'});
    expect([for (final entry in relay.entries) entry.id], ['n3', 'web-note-1']);
  });

  test('a 401 shows the sign-in, and the notes leave memory', () async {
    server.routes['GET api/account'] = (_) => http.Response('{"error":"Sign in"}', 401);
    await relay.start();
    expect(relay.signInState, WebSignIn.signedOut);
    expect(relay.entries, isEmpty);
    expect(server.calls, ['GET account']);
  });

  test('adds a note as the Web device, shows it at once, and sends its files after it', () async {
    await relay.start();
    final adding = relay.addNote('# Plan', id: 'new-note-01', files: const [
      NewFile(name: 'plan.pdf', size: 3, bytes: [1, 2, 3]),
    ]);
    expect(relay.entries.any((entry) => entry.id == 'new-note-01'), isTrue, reason: 'it shows before the server answers');
    expect(await adding, isNull);
    final post = server.requests.firstWhere((request) => request.method == 'POST' && request.url.path.endsWith('/notes'));
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['clientId'], 'new-note-01');
    expect(body['text'], '# Plan');
    expect(body['createdAt'], 5000);
    final listed = (body['attachments'] as List).single as Map<String, dynamic>;
    expect(listed['name'], 'plan.pdf');
    expect(listed['type'], 'application/pdf');
    final upload = server.requests.last;
    expect(upload.url.path, '/apps/relay/api/attachments');
    expect(upload.headers['X-Note-Client-Id'], 'new-note-01');
    expect(upload.headers['X-Attachment-Id'], listed['id']);
    expect(upload.bodyBytes, [1, 2, 3]);
    final added = relay.entries.firstWhere((entry) => entry.id == 'new-note-01');
    expect(added.files.single.ready, isTrue);
    expect(added.waiting, isFalse);
  });

  test('a refused add takes the note back and says why; a file over 25 MB is left out', () async {
    await relay.start();
    server.routes['POST api/notes'] = (_) => http.Response('{"error":{"message":"Give the note words or a file."}}', 400);
    expect(await relay.addNote('Hi', id: 'new-note-02'), 'Give the note words or a file.');
    expect(relay.entries.any((entry) => entry.id == 'new-note-02'), isFalse);
    server.routes['POST api/notes'] = (_) => {'id': 'n10', 'added': true};
    final problem = await relay.addNote('Hi', id: 'new-note-03', files: const [NewFile(name: 'huge.mov', size: 26 * 1024 * 1024)]);
    expect(problem, 'huge.mov is over 25 MB, so it was not added.');
    expect(server.calls.where((call) => call == 'POST attachments'), isEmpty);
  });

  test('edits by clientId for its own note and by id for one from elsewhere', () async {
    await relay.start();
    expect(await relay.editNote('web-note-1', 'Changed'), isNull);
    var body = jsonDecode(server.requests.last.body) as Map<String, dynamic>;
    expect(body, {'clientId': 'web-note-1', 'text': 'Changed', 'editedAt': 5000});
    expect(relay.entries.firstWhere((entry) => entry.id == 'web-note-1').text, 'Changed');
    expect(await relay.editNote('n1', 'From the phone, changed'), isNull);
    body = jsonDecode(server.requests.last.body) as Map<String, dynamic>;
    expect(body['id'], 'n1');
  });

  String textOf(String id) => relay.entries.firstWhere((entry) => entry.id == id).text;
  List<String?> sinces() => [for (final request in server.requests)
    if (request.method == 'GET' && request.url.path.endsWith('/notes')) request.url.queryParameters['since']];
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test("a newer change elsewhere wins: the open note keeps the person's words, and the newer ones show once it closes",
      () async {
    await relay.start();
    relay.openNote = 'n1';
    server.routes['PATCH api/notes'] = (_) => http.Response('{"error":{"code":"older","message":"The note changed after this."}}', 409);
    server.routes['GET api/notes'] = (_) => {'notes': [note('n1', text: 'Newer, from the phone', at: 1000)], 'next': 10, 'more': false};
    expect(await relay.editNote('n1', 'Old'), 'The note changed after this.');
    await settle();
    expect(server.calls.last, 'GET notes');
    expect(textOf('n1'), 'Words', reason: 'the open note is not changed under the person');
    relay.openNote = null;
    await settle();
    expect(textOf('n1'), 'Newer, from the phone');
    expect(sinces(), ['0', '7', '9', '9'], reason: 'the read after the note closes starts before the held change');
  });

  test("a phone's edit or delete of the open note waits, and shows once the note closes", () async {
    await relay.start();
    relay.openNote = 'n1';
    server.routes['GET api/notes'] = (_) => {'notes': [note('n1', text: 'Edited on the phone'),
      {'id': 'n3', 'clientId': null, 'deleted': true}], 'next': 10, 'more': false};
    await relay.pullNotes();
    expect(textOf('n1'), 'Words');
    expect(relay.entries.any((entry) => entry.id == 'n3'), isFalse, reason: 'a note not open changes at once');
    await relay.pullNotes();
    expect(textOf('n1'), 'Words');
    relay.openNote = 'web-note-1';
    await settle();
    expect(textOf('n1'), 'Edited on the phone');
    server.routes['GET api/notes'] = (_) => {'notes': [{'id': 'n2', 'clientId': 'web-note-1', 'deleted': true}], 'next': 11,
      'more': false};
    await relay.pullNotes();
    expect(relay.entries.any((entry) => entry.id == 'web-note-1'), isTrue);
    relay.openNote = null;
    await settle();
    expect(relay.entries.any((entry) => entry.id == 'web-note-1'), isFalse);
    expect(sinces(), ['0', '7', '9', '9', '9', '10', '10']);
  });

  test('with no answer, the typed words stay and go again at the next save, on leave, and at a sync', () async {
    await relay.start();
    relay.openNote = 'n1';
    server.routes['PATCH api/notes'] = (_) => http.Response('{"error":{"message":"Try later."}}', 503);
    final problem = await relay.editNote('n1', 'Typed offline');
    expect(problem, startsWith('Try later. Your change stays here'));
    expect(textOf('n1'), 'Typed offline');
    // A read meanwhile keeps the typed words, not the server's older ones.
    server.routes['GET api/notes'] = (_) => {'notes': [note('n1', text: 'Words')], 'next': 10, 'more': false};
    relay.openNote = null;
    await settle();
    expect(textOf('n1'), 'Typed offline');
    final patches = server.requests.where((request) => request.method == 'PATCH').toList();
    expect(patches, hasLength(2), reason: 'leaving the note sent it again');
    expect((jsonDecode(patches.last.body) as Map)['text'], 'Typed offline');
    server.routes['PATCH api/notes'] = (_) => {'id': 'n1', 'updated': true};
    server.routes['GET api/notes'] = (_) => {'notes': [note('n1', text: 'Typed offline')], 'next': 11, 'more': false};
    await relay.sync();
    expect((jsonDecode(server.requests.lastWhere((request) => request.method == 'PATCH').body) as Map)['text'], 'Typed offline');
    expect(server.calls.last, 'GET notes');
    expect(textOf('n1'), 'Typed offline');
    final count = server.requests.where((request) => request.method == 'PATCH').length;
    await relay.sync();
    expect(server.requests.where((request) => request.method == 'PATCH').length, count, reason: 'nothing waits now');
  });

  test('a refused change takes the note back to its words before', () async {
    await relay.start();
    server.routes['PATCH api/notes'] = (_) => http.Response('{"error":{"message":"Give the note words or a file."}}', 400);
    expect(await relay.editNote('n1', ''), 'Give the note words or a file.');
    expect(textOf('n1'), 'Words');
    await relay.sync();
    expect(server.requests.where((request) => request.method == 'PATCH'), hasLength(1));
  });

  test('a file that did not upload shows as on its way and goes again; one the server refuses leaves the note', () async {
    await relay.start();
    server.routes['POST api/attachments'] = (_) => http.Response('{"error":{"message":"Try later."}}', 503);
    final problem = await relay.addNote('Plan', id: 'new-note-04', files: const [
      NewFile(name: 'plan.pdf', size: 3, bytes: [1, 2, 3]),
    ]);
    expect(problem, 'plan.pdf did not upload. Try later. It goes again at the next save.');
    var added = relay.entries.firstWhere((entry) => entry.id == 'new-note-04');
    expect(added.files.single.url, isNull, reason: 'the server does not have it');
    expect(added.waiting, isTrue);
    final fileId = added.files.single.id;
    server.routes['POST api/attachments'] = (_) => {'ok': true, 'added': true};
    server.routes['GET api/notes'] = (_) => {'notes': <Object>[], 'next': 9, 'more': false};
    await relay.sync();
    final upload = server.requests.lastWhere((request) => request.url.path.endsWith('/attachments'));
    expect(upload.headers['X-Attachment-Id'], fileId);
    expect(upload.headers['X-Note-Client-Id'], 'new-note-04');
    expect(upload.bodyBytes, [1, 2, 3]);
    added = relay.entries.firstWhere((entry) => entry.id == 'new-note-04');
    expect(added.files.single.url, 'https://relay.example.com/apps/relay/api/attachment?id=$fileId');
    expect(added.waiting, isFalse);

    server.routes['POST api/attachments'] = (_) => http.Response('{"error":{"message":"This file is not on the note."}}', 404);
    expect(await relay.editNote('web-note-1', 'With a file', files: const [NewFile(name: 'late.png', size: 1, bytes: [9])]),
      'late.png did not upload. This file is not on the note.');
    expect(relay.entries.firstWhere((entry) => entry.id == 'web-note-1').files, isEmpty);
  });

  test('deletes after the Undo time, and Undo keeps the note', () async {
    await relay.start();
    await relay.deleteNote('n1');
    expect(relay.entries.any((entry) => entry.id == 'n1'), isFalse);
    await relay.undoDelete('n1');
    expect(relay.entries.any((entry) => entry.id == 'n1'), isTrue);
    expect(server.calls, isNot(contains('DELETE notes')));
    await relay.deleteNote('web-note-1');
    await relay.endUndo('web-note-1');
    expect(server.requests.last.method, 'DELETE');
    expect(server.requests.last.url.queryParameters, {'clientId': 'web-note-1'});
  });

  test('Sign out sends the deletes under Undo before the notes leave memory', () async {
    await relay.start();
    await relay.deleteNote('n1');
    await relay.disconnect();
    expect(server.calls.sublist(server.calls.length - 2), ['DELETE notes', 'POST out']);
    expect(server.requests.firstWhere((request) => request.method == 'DELETE').url.queryParameters, {'id': 'n1'});
    expect(relay.entries, isEmpty);
  });

  test('a closing page sends the deletes under Undo and the words that did not go', () async {
    await relay.start();
    await relay.deleteNote('n1');
    server.routes['PATCH api/notes'] = (_) => http.Response('', 502);
    await relay.editNote('web-note-1', 'Typed before closing');
    relay.pageClosing();
    expect([for (final (method, address, _) in lastSends) '$method $address'], [
      'DELETE https://relay.example.com/apps/relay/api/notes?id=n1',
      'PATCH https://relay.example.com/apps/relay/api/notes',
    ]);
    expect(jsonDecode(lastSends.last.$3!), {'clientId': 'web-note-1', 'text': 'Typed before closing', 'editedAt': 5000});
    await relay.endUndo('n1');
    expect(server.calls, isNot(contains('DELETE notes')), reason: 'it went as the page closed');
  });

  test("a closing page sends the open note's words that the editor did not save yet", () async {
    await relay.start();
    relay.editorWords = () => (id: 'n1', text: 'Words');
    relay.pageClosing();
    expect(lastSends, isEmpty, reason: 'the words did not change');
    relay.editorWords = () => (id: 'web-note-1', text: 'Typed just now');
    relay.pageClosing();
    expect([for (final (method, address, _) in lastSends) '$method $address'], ['PATCH https://relay.example.com/apps/relay/api/notes']);
    expect(jsonDecode(lastSends.single.$3!), {'clientId': 'web-note-1', 'text': 'Typed just now', 'editedAt': 5000});
    lastSends.clear();
    relay.editorWords = () => (id: 'new-note-07', text: 'A new note');
    relay.pageClosing();
    expect(lastSends.first.$1, 'POST');
    expect(jsonDecode(lastSends.first.$3!), {'clientId': 'new-note-07', 'text': 'A new note', 'createdAt': 5000});
    lastSends.clear();
    relay.editorWords = () => (id: 'new-note-08', text: '');
    relay.pageClosing();
    expect([for (final (method, _, _) in lastSends) method], isNot(contains('POST')), reason: 'blank words are never sent');
  });

  test('a new note with no answer stays with its file, goes again on leave and at a sync, and its file after', () async {
    await relay.start();
    server.routes['POST api/notes'] = (_) => http.Response('{"error":{"message":"Try later."}}', 503);
    final problem = await relay.addNote('Offline plan', id: 'new-note-05', files: const [
      NewFile(name: 'plan.pdf', size: 3, bytes: [1, 2, 3]),
    ]);
    expect(problem, startsWith('Try later. Your change stays here'));
    var added = relay.entries.firstWhere((entry) => entry.id == 'new-note-05');
    expect(added.waiting, isTrue);
    expect(added.files.single.url, isNull);
    expect(server.calls, isNot(contains('POST attachments')), reason: 'the server has no note for the file yet');
    final fileId = added.files.single.id;

    relay.pageClosing();
    expect([for (final (method, _, _) in lastSends) method], ['POST', 'PATCH']);
    expect(jsonDecode(lastSends.first.$3!), {'clientId': 'new-note-05', 'text': 'Offline plan', 'createdAt': 5000});

    List<Map<String, dynamic>> posts() => [for (final request in server.requests)
      if (request.method == 'POST' && request.url.path.endsWith('/notes')) jsonDecode(request.body) as Map<String, dynamic>];
    relay.openNote = 'new-note-05';
    relay.openNote = null;
    await settle();
    expect(posts(), hasLength(2), reason: 'leaving the note sent it again');
    server.routes['POST api/notes'] = (_) => {'id': 'n11', 'added': true};
    server.routes['GET api/notes'] = (_) => {'notes': <Object>[], 'next': 9, 'more': false};
    await relay.sync();
    expect(posts(), hasLength(3));
    expect({for (final body in posts()) body['clientId']}, {'new-note-05'}, reason: 'the server keeps it once');
    expect(((posts().last['attachments'] as List).single as Map)['id'], fileId);
    final upload = server.requests.lastWhere((request) => request.url.path.endsWith('/attachments'));
    expect(upload.headers['X-Attachment-Id'], fileId);
    added = relay.entries.firstWhere((entry) => entry.id == 'new-note-05');
    expect(added.waiting, isFalse);
    expect(added.files.single.url, isNotNull);
    await relay.sync();
    expect(posts(), hasLength(3), reason: 'nothing waits now');
  });

  test('a new note sent again after its first send got there unanswered goes on as an edit', () async {
    await relay.start();
    server.routes['POST api/notes'] = (_) => http.Response('', 504);
    await relay.addNote('First words', id: 'new-note-09');
    expect(await relay.editNote('new-note-09', 'Second words'), contains('Your change stays here'));
    server.routes['POST api/notes'] = (_) => {'id': 'n12', 'added': false};
    server.routes['GET api/notes'] = (_) => {'notes': <Object>[], 'next': 9, 'more': false};
    await relay.sync();
    final patch = server.requests.lastWhere((request) => request.method == 'PATCH');
    expect(jsonDecode(patch.body), {'clientId': 'new-note-09', 'text': 'Second words', 'editedAt': 5000});
    expect(relay.entries.firstWhere((entry) => entry.id == 'new-note-09').waiting, isFalse);
  });

  test('only a refusal takes a new note away; with no answer it stays', () async {
    await relay.start();
    final notices = <String>[];
    final listening = relay.notices.listen(notices.add);
    server.routes['POST api/notes'] = (_) => throw http.ClientException('offline');
    await relay.addNote('Kept offline', id: 'new-note-06');
    expect(relay.entries.any((entry) => entry.id == 'new-note-06'), isTrue);
    server.routes['POST api/notes'] = (_) => http.Response('{"error":{"message":"This note is too long."}}', 400);
    server.routes['GET api/notes'] = (_) => {'notes': <Object>[], 'next': 9, 'more': false};
    await relay.sync();
    await Future<void>.delayed(Duration.zero);
    expect(relay.entries.any((entry) => entry.id == 'new-note-06'), isFalse);
    expect(notices, ['A new note did not go. This note is too long.']);
    final count = server.calls.where((call) => call == 'POST notes').length;
    await relay.sync();
    expect(server.calls.where((call) => call == 'POST notes').length, count);
    await listening.cancel();
  });

  test('a refused delete brings the note back with a notice', () async {
    await relay.start();
    server.routes['DELETE api/notes'] = (_) => http.Response('{"error":{"message":"Try later."}}', 500);
    final notices = <String>[];
    final listening = relay.notices.listen(notices.add);
    await relay.deleteNote('n1');
    await relay.endUndo('n1');
    await Future<void>.delayed(Duration.zero);
    expect(relay.entries.any((entry) => entry.id == 'n1'), isTrue);
    expect(notices, ['The note was not deleted. Try later.']);
    await listening.cancel();
  });

  test('an empty note on the server is deleted with Undo; one with a recording or files stays', () async {
    await relay.start();
    expect(await relay.dropEmptyNote('n1'), Emptied.deleting);
    expect(relay.entries.any((entry) => entry.id == 'n1'), isFalse);
    expect(await relay.dropEmptyNote('n3'), Emptied.kept);
    await relay.undoDelete('n1');
  });

  test('opens a file in a new tab, plays a recording from its route, and says when a file is not ready', () async {
    await relay.start();
    final notices = <String>[];
    final listening = relay.notices.listen(notices.add);
    final ring = relay.entries.first;
    await relay.openFile(ring.files.first);
    expect(opened.single.toString(), 'https://relay.example.com/apps/relay/api/attachment?id=file-0001');
    await relay.openFile(ring.files.last);
    await relay.play(ring.recording!);
    expect(player.played.single, 'https://relay.example.com/apps/relay/api/audio?id=n3');
    // Pause and seek go to the same player, and the browser reads no waves: it keeps no copy of the recording.
    await relay.pause();
    await relay.seek(const Duration(seconds: 3));
    expect([player.calls, relay.playback.value?.at, relay.playback.value?.playing, await relay.waveOf(ring.recording!)],
      [['play', 'pause', 'seek 3000'], const Duration(seconds: 3), false, isEmpty]);
    await Future<void>.delayed(Duration.zero);
    expect(notices, ['This file is still on its way. Try again soon.']);
    await listening.cancel();
  });

  test('sign out ends the sign-in even when the server does not answer, and keeps nothing', () async {
    await relay.start();
    server.routes['POST sign-in/out'] = (_) => throw http.ClientException('offline');
    await relay.disconnect();
    expect(relay.signInState, WebSignIn.signedOut);
    expect(relay.entries, isEmpty);
    expect(relay.email, isNull);
  });

  test('the phone-only parts answer that the phone does them', () async {
    expect(await relay.setHealth(true), onlyOnPhone);
    expect(await relay.startVoiceNote(), onlyOnPhone);
    expect(relay.speechModel, ModelState.missing);
    expect(relay.calendars, isEmpty);
    await relay.setAppearance(Appearance.dark);
    expect(relay.settings.appearance, Appearance.dark);
  });
}
