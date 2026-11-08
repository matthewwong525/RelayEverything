import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:relay_app/controller.dart';
import 'package:relay_app/data/api.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/data/webhook.dart';
import 'package:relay_app/sync/calendar.dart';
import 'package:relay_app/sync/health.dart';
import 'package:relay_app/sync/location.dart';
import 'package:relay_app/sync/native.dart';
import 'package:relay_app/sync/photos.dart';
import 'package:relay_app/voice/model.dart';
import 'package:relay_app/voice/recorder.dart';
import 'package:relay_app/voice/transcriber.dart';

const connection = Connection(server: 'https://relay.example.com', clientId: 'phone.access', clientSecret: 'secret-value');
final code = jsonEncode({'relay': 1, 'server': connection.server, 'clientId': connection.clientId, 'clientSecret': connection.clientSecret});
/// A key from the Relay Everything page: `rek_` and 43 base64url characters.
const pageKey = 'rek_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';
const bearer = Connection.bearer(server: 'https://relay.example.com', key: pageKey);
final pageCode = jsonEncode({'relay': 1, 'server': bearer.server, 'key': pageKey});

/// A made-up secret, fixed so the webhook fixtures stay the same: the worker's test checks them with it.
const fixtureSecret = 'whsec_cmVsYXktZXZlcnl0aGluZy13ZWJob29rLWZpeHR1cmU=';
const hook = Webhook(address: 'https://db.example.com/relay', secret: fixtureSecret);
const installId = '0f5c2a64-1d6e-4b7a-9c3e-2a8d5b7f6e10';

/// A store in memory, with a folder of its own for photo copies, deleted after the test.
Store memoryStore() {
  final folder = tempFolder();
  return Store(NativeDatabase.memory(), folder: () async => folder);
}

/// A server answering each route with [answer]; every request it saw is kept.
class FakeServer {
  FakeServer([http.Response Function(http.Request request)? answer]) : answer = answer ?? ok;

  http.Response Function(http.Request request) answer;
  final requests = <http.Request>[];
  /// When set, each reply waits for it, so a test can act while a request is still open.
  Completer<void>? hold;

  static http.Response ok(http.Request request) => json(switch (request.url.path) {
    '/apps/relay/sign-in/phone/key' => {'server': request.url.origin, 'key': pageKey},
    final path when path.endsWith('/key') => {'device': 'Android phone'},
    final path when path.endsWith('/connections') => {'aiApps': [{'name': 'Claude'}], 'webhooks': [{'name': 'Home server'}]},
    _ => {'added': 1},
  });
  static http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  RelayApi api(Connection connection) => RelayApi(connection, client());

  /// The person's own receiver, at [Webhook.address].
  WebhookClient webhook(Webhook webhook, String installId) => WebhookClient(webhook, installId: installId, client: client());

  /// The plain client the sign-in's trade uses, with no key.
  http.Client client() => MockClient((request) async {
    requests.add(request);
    await hold?.future;
    return answer(request);
  });

  List<String> get routes => [for (final request in requests) request.url.path.split('/').last];
}

/// A server for sending off: it answers every call with an error, and the test checks that [FakeServer.requests]
/// stays empty.
FakeServer noNetwork() => FakeServer((_) => FakeServer.json({'error': 'no call may reach the network'}, 500));

/// One note as `GET notes` gives it: from elsewhere unless [mine], when this phone sent it as [clientId].
Map<String, dynamic> pulledNote(String id, {String? clientId, bool mine = false, String text = 'Flight moved to 9:40',
  DateTime? recordedAt, DateTime? editedAt, String device = 'Email', String source = 'typed', bool audio = false,
  List<Map<String, dynamic>> files = const []}) => {
  'id': id, 'clientId': clientId, 'mine': mine, 'source': source, 'text': text,
  'recordedAt': (recordedAt ?? DateTime(2026, 11, 5, 8, 2)).millisecondsSinceEpoch,
  'editedAt': editedAt?.millisecondsSinceEpoch, 'device': device, 'audio': audio, 'place': null, 'attachments': files,
};

/// A page of `GET notes`.
http.Response notesPage(List<Map<String, dynamic>> notes, {required int next, bool more = false}) =>
  FakeServer.json({'notes': notes, 'next': next, 'more': more});

class MemoryStorage extends Fake implements FlutterSecureStorage {
  /// The app's own Keychain group, or Android's one home.
  final values = <String, String>{};
  /// Each item's iPhone Keychain access, as last written; null for the plugin's default, open only while unlocked.
  final access = <String, KeychainAccessibility?>{};
  /// The App Group's Keychain group: items written with a `groupId`.
  final shared = <String, String>{};
  /// The iPhone options of each read, write and delete.
  final options = <AppleOptions?>[];
  /// When true, the App Group's group answers as in a build with no App Group.
  bool noGroup = false;
  /// When set, the write after this many writes throws, as when the app stops part way.
  int? stopAfterWrites;
  var _writes = 0;

  Map<String, String> _home(AppleOptions? iOptions) {
    if (iOptions?.groupId == null) return values;
    if (noGroup) throw PlatformException(code: 'Unexpected security result code', message: 'Code: -34018');
    return shared;
  }

  @override
  Future<Map<String, String>> readAll({AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
    WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    options.add(iOptions);
    return Map.of(_home(iOptions));
  }

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions,
    LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    options.add(iOptions);
    if (stopAfterWrites != null && _writes >= stopAfterWrites!) throw StateError('stopped');
    _writes++;
    _home(iOptions)[key] = value!;
    if (iOptions?.groupId == null) access[key] = iOptions?.accessibility;
  }

  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
    WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    options.add(iOptions);
    _home(iOptions).remove(key);
    if (iOptions?.groupId == null) access.remove(key);
  }
}

class FakePlaces implements Places {
  bool allowed = true;
  Pin? pin;
  /// When set, a note's fix waits for it, as a real fix can take seconds.
  Completer<Pin?>? fix;
  /// Each ask for location, by whether it was for all the time.
  final asked = <bool>[];
  /// Each fix for a note, by whether it asked for the place's name: a network lookup.
  final named = <bool>[];
  final points = StreamController<Pin>.broadcast();

  @override
  Future<bool> allow({required bool always}) async {
    asked.add(always);
    return allowed;
  }

  @override
  Future<Pin?> here({required bool name}) async {
    named.add(name);
    final found = await (fix == null ? Future.value(pin) : fix!.future);
    // As on a phone: with no name asked for, the pin has none.
    return found == null || name ? found : Pin(at: found.at, lat: found.lat, lon: found.lon, accuracy: found.accuracy);
  }

  @override
  Stream<Pin> history() => points.stream;

  /// Each place name looked up, by its point.
  final lookups = <(double, double)>[];

  @override
  Future<String?> nameOf(double lat, double lon) async {
    lookups.add((lat, lon));
    return 'Place ${lookups.length}';
  }
}

/// The iPhone's Swift side: it keeps each flag it was told, and hands back [lines] once per drain.
class FakeBackground implements NativeBackground {
  final flags = <({bool health, bool history, LocationMode mode})>[];
  List<String> lines = [];
  int drains = 0;

  @override
  Future<void> set({required bool health, required bool history, required LocationMode mode}) async =>
    flags.add((health: health, history: history, mode: mode));

  @override
  Future<List<String>> drain() async {
    drains++;
    final kept = lines;
    lines = [];
    return kept;
  }
}

/// A point as Swift writes it.
String swiftPoint(DateTime at, double lat, double lon, {double accuracy = 12}) =>
  jsonEncode({'at': at.millisecondsSinceEpoch, 'lat': lat, 'lon': lon, 'accuracy': accuracy});

/// The sign-in sheet: it keeps each page it opened, and comes back to [back], or to a code for the page's challenge.
class FakeWebAuth {
  final opened = <Uri>[];
  /// Null: the person closed the sheet.
  Uri? Function(Uri url) back = (_) => Uri.parse('relayeverything://connected?code=one-time-code');

  Future<Uri?> call(Uri url) async {
    opened.add(url);
    return back(url);
  }
}

class FakeHealth implements HealthSource {
  bool allowed = true;
  List<HealthDataPoint> readings = [];
  Object? error;
  final reads = <(DateTime, DateTime)>[];

  @override
  Future<bool> allow() async => allowed;

  @override
  Future<List<HealthDataPoint>> read(DateTime from, DateTime to) async {
    reads.add((from, to));
    if (error != null) throw error!;
    return readings;
  }
}

HealthDataPoint reading(HealthDataType type, DateTime from, DateTime to, {num value = 0, String sourceId = 'com.apple.health',
  HealthValue? as}) =>
  HealthDataPoint(
    uuid: '${type.name}-${from.millisecondsSinceEpoch}', type: type, unit: HealthDataUnit.COUNT, dateFrom: from, dateTo: to,
    value: as ?? (type == HealthDataType.WORKOUT
      ? WorkoutHealthValue(workoutActivityType: HealthWorkoutActivityType.RUNNING)
      : NumericHealthValue(numericValue: value)),
    sourcePlatform: HealthPlatformType.appleHealth, sourceDeviceId: 'device', sourceId: sourceId, sourceName: 'Health',
  );

/// The phone's photo library: [take] adds a photo, and each look, ask and copy is kept.
class FakePhotos implements PhotoSource {
  bool allowed = true;
  int asked = 0;
  final library = <LibraryPhoto>[];
  /// A photo's JPEG copy, when it is not the usual 1,600 by 1,200 one; null for a photo the phone can not copy.
  final jpegs = <String, Uint8List?>{};
  /// Photos kept only in iCloud.
  final cloudOnly = <String>{};
  /// When a photo came into the library, when not when it was taken: Android looks by this time, so a photo saved
  /// today from an old trip is found as new.
  final added = <String, DateTime>{};
  /// Each look at the library: from when, and how many at most.
  final finds = <(DateTime, int)>[];
  final copied = <String>[];
  /// Runs while each copy is made: it can throw, such as for an iCloud download that failed, or act meanwhile.
  Future<void> Function(LibraryPhoto photo)? whileCopying;

  LibraryPhoto take(String id, DateTime at, {double? lat, double? lon, DateTime? addedAt}) {
    final photo = LibraryPhoto(id: id, takenAt: at, lat: lat, lon: lon);
    library.add(photo);
    if (addedAt != null) added[id] = addedAt;
    return photo;
  }

  DateTime _addedOf(LibraryPhoto photo) => added[photo.id] ?? photo.takenAt;

  @override
  Future<bool> allow() async {
    asked++;
    return allowed;
  }

  @override
  Future<List<LibraryPhoto>> find(DateTime from, {required int limit}) async {
    finds.add((from, limit));
    final found = [for (final photo in library) if (!_addedOf(photo).isBefore(from)) photo]
      ..sort((a, b) => _addedOf(a).compareTo(_addedOf(b)));
    return found.take(limit).toList();
  }

  @override
  Future<bool> onPhone(LibraryPhoto photo) async => !cloudOnly.contains(photo.id);

  @override
  Future<Uint8List?> jpeg(LibraryPhoto photo) async {
    copied.add(photo.id);
    await whileCopying?.call(photo);
    return jpegs.containsKey(photo.id) ? jpegs[photo.id] : jpegOf(1600, 1200);
  }
}

/// The network the phone is on; Wi-Fi unless a test says otherwise.
class FakeNetwork implements Network {
  Link current = Link.wifi;

  @override
  Future<Link> link() async => current;
}

/// The start of a JPEG of [width] by [height]: enough for its frame header to be read.
Uint8List jpegOf(int width, int height) => Uint8List.fromList([
  0xFF, 0xD8, // start of image
  0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // JFIF
  0xFF, 0xC0, 0x00, 0x11, 0x08, height >> 8, height & 0xFF, width >> 8, width & 0xFF, 0x03, // frame header
  0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
  0xFF, 0xD9, // end of image
]);

/// The parts of a multipart body, by name: each part's content type, when it has one, and its value.
Map<String, (String?, String)> formParts(http.Request request) {
  final boundary = RegExp(r'boundary=(.+)$').firstMatch(request.headers['content-type']!)!.group(1)!;
  final parts = <String, (String?, String)>{};
  for (final part in latin1.decode(request.bodyBytes).split('--$boundary')) {
    final split = part.indexOf('\r\n\r\n');
    if (split < 0) continue;
    final head = part.substring(0, split);
    final name = RegExp(r'name="([^"]+)"').firstMatch(head)?.group(1);
    if (name == null) continue;
    var value = part.substring(split + 4);
    if (value.endsWith('\r\n')) value = value.substring(0, value.length - 2);
    parts[name] = (RegExp(r'content-type: *(.+)', caseSensitive: false).firstMatch(head)?.group(1)?.trim(), value);
  }
  return parts;
}

/// The phone's calendars: [list] and [items], read only through the [CalendarSource] calls, each kept.
class FakeCalendar implements CalendarSource {
  bool allowed = true;
  int asked = 0;
  List<PhoneCalendar> list = const [PhoneCalendar(id: 'work', name: 'Work', account: 'sam@example.com'),
    PhoneCalendar(id: 'holidays', name: 'US Holidays')];
  List<PhoneEvent> items = [];
  Object? error;
  final reads = <(DateTime, DateTime, Set<String>)>[];
  int listed = 0;

  @override
  Future<bool> allow() async {
    asked++;
    return allowed;
  }

  @override
  Future<List<PhoneCalendar>> calendars() async {
    listed++;
    if (error != null) throw error!;
    return list;
  }

  @override
  Future<List<PhoneEvent>> events(DateTime from, DateTime to, Set<String> calendarIds) async {
    reads.add((from, to, calendarIds));
    if (error != null) throw error!;
    return [for (final event in items) if (calendarIds.contains(event.calendarId)) event];
  }
}

/// An event on the work calendar, one hour long.
PhoneEvent meeting(String id, DateTime start, {String title = 'Board meeting', String calendar = 'work'}) =>
  PhoneEvent(calendarId: calendar, eventId: id, title: title, start: start, end: start.add(const Duration(hours: 1)),
    people: const [EventPerson(name: 'Sam', email: 'sam@example.com', organizer: true)]);

/// A folder of its own for one test's recordings and model, deleted after it.
Directory tempFolder() {
  final folder = Directory.systemTemp.createTempSync('relay-voice-');
  addTearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });
  return folder;
}

/// Stands in for whisper.cpp's model file: small, with its own checksum.
final modelFile = List<int>.generate(4096, (i) => i * 7 % 256);
final modelFileSha = sha256.convert(modelFile).toString();

/// Hugging Face, for the speech model: it serves [file], resumes from a `Range`, and can drop the connection after
/// [dropAfter] bytes. Every request it saw is kept.
class ModelServer {
  ModelServer([List<int>? file]) : file = file ?? modelFile;

  List<int> file;
  int? dropAfter;
  bool offline = false;
  final requests = <http.BaseRequest>[];

  http.Client client() => MockClient.streaming((request, _) async {
    requests.add(request);
    if (offline) throw http.ClientException('No connection', request.url);
    final range = RegExp(r'^bytes=(\d+)-$').firstMatch(request.headers['Range'] ?? '');
    final from = range == null ? 0 : int.parse(range.group(1)!);
    final body = file.sublist(from);
    final drop = dropAfter;
    dropAfter = null;
    final controller = StreamController<List<int>>();
    if (drop == null) {
      controller.add(body);
    } else {
      controller.add(body.sublist(0, drop));
      controller.addError(http.ClientException('Connection dropped', request.url));
    }
    unawaited(controller.close());
    return http.StreamedResponse(controller.stream, range == null ? 200 : 206, contentLength: drop == null ? body.length : null);
  });
}

SpeechModel speechModel(Directory folder, ModelServer server) =>
  SpeechModel(folder: () async => folder, client: server.client, sha256: modelFileSha, bytes: modelFile.length);

/// Puts the model where [SpeechModel] keeps it, as after a download.
Future<void> placeModel(Directory folder) async {
  final file = File('${folder.path}/speech-model/$modelName');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(modelFile);
}

/// A microphone that writes a few bytes as its recording.
class FakeMicrophone implements Microphone {
  bool allowed = true;
  /// Thrown by the next [start], as by a microphone another app holds; it is cleared then.
  Exception? startError;
  final calls = <String>[];

  @override
  Future<bool> allow() async => allowed;

  @override
  Future<void> start(String path) async {
    calls.add('start');
    final error = startError;
    if (error != null) {
      startError = null;
      throw error;
    }
    await File(path).writeAsBytes([82, 73, 70, 70]);
  }

  /// Thrown by the next [stop], as by a microphone that fails to end its file; it is cleared then.
  Exception? stopError;

  @override
  Future<void> stop() async {
    calls.add('stop');
    final error = stopError;
    if (error != null) {
      stopError = null;
      throw error;
    }
  }

  @override
  Future<void> cancel() async => calls.add('cancel');
}

/// Writes [answer] as every recording's words, or waits for [hold] when set, or throws [error], an Exception or an
/// Error. It runs one recording at a time, as the app's does; a time limit counts [cancelled] and fails the held words,
/// unless [cancelStops] is false, as with a stuck engine.
class FakeTranscriber extends Transcriber {
  String answer = 'Ask the fab if the flex stiffener can be 0.2 mm';
  Completer<String>? hold;
  bool cancelStops = true;
  Object? error;
  final heard = <String>[];
  int closed = 0;
  int cancelled = 0;

  @override
  Future<String> write(File wav, WordsJob job) async {
    heard.add(wav.uri.pathSegments.last);
    if (error != null) throw error!;
    final held = hold;
    if (held == null) return answer;
    job.onCancel(() {
      cancelled++;
      if (cancelStops && !held.isCompleted) held.completeError(StateError('Cancelled at the time limit'));
    });
    return held.future;
  }

  @override
  Future<void> close() async => closed++;
}

class FakePlayer implements VoicePlayer {
  final played = <String>[];

  @override
  Future<void> play(File file) async => played.add(file.path);
}

/// Voice notes on a fake microphone, words and player, with the model from [server] in [folder].
VoiceParts fakeVoice(Directory folder, ModelServer server, {required DateTime Function() clock, FakeMicrophone? microphone,
  FakeTranscriber? transcriber, FakePlayer? player}) => VoiceParts(
  model: speechModel(folder, server),
  recorder: VoiceRecorder(microphone: microphone ?? FakeMicrophone(), folder: () async => folder, clock: clock),
  transcriber: transcriber ?? FakeTranscriber(),
  player: player ?? FakePlayer(),
);
