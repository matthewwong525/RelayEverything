import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:relay_app/controller.dart';
import 'package:relay_app/data/api.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/sync/health.dart';
import 'package:relay_app/sync/location.dart';
import 'package:relay_app/voice/model.dart';
import 'package:relay_app/voice/recorder.dart';
import 'package:relay_app/voice/transcriber.dart';

const connection = Connection(server: 'https://relay.example.com', clientId: 'phone.access', clientSecret: 'secret-value');
final code = jsonEncode({'relay': 1, 'server': connection.server, 'clientId': connection.clientId, 'clientSecret': connection.clientSecret});

Store memoryStore() => Store(NativeDatabase.memory());

/// A server answering each route with [answer]; every request it saw is kept.
class FakeServer {
  FakeServer([http.Response Function(http.Request request)? answer]) : answer = answer ?? ok;

  http.Response Function(http.Request request) answer;
  final requests = <http.Request>[];
  /// When set, each reply waits for it, so a test can act while a request is still open.
  Completer<void>? hold;

  static http.Response ok(http.Request request) => json(request.url.path.endsWith('/timeline') ? {'notes': [], 'next': null} : {'added': 1});
  static http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  RelayApi api(Connection connection) => RelayApi(connection, MockClient((request) async {
    requests.add(request);
    await hold?.future;
    return answer(request);
  }));

  List<String> get routes => [for (final request in requests) request.url.path.split('/').last];
}

/// A server for sending off: it answers every call with an error, and the test checks that [FakeServer.requests]
/// stays empty.
FakeServer noNetwork() => FakeServer((_) => FakeServer.json({'error': 'no call may reach the network'}, 500));

class MemoryStorage extends Fake implements FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<Map<String, String>> readAll({AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
    WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async => Map.of(values);

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions,
    LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async => values[key] = value!;

  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
    WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async => values.remove(key);
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

HealthDataPoint reading(HealthDataType type, DateTime from, DateTime to, {num value = 0, String sourceId = 'com.apple.health'}) =>
  HealthDataPoint(
    uuid: '${type.name}-${from.millisecondsSinceEpoch}', type: type, unit: HealthDataUnit.COUNT, dateFrom: from, dateTo: to,
    value: type == HealthDataType.WORKOUT
      ? WorkoutHealthValue(workoutActivityType: HealthWorkoutActivityType.RUNNING)
      : NumericHealthValue(numericValue: value),
    sourcePlatform: HealthPlatformType.appleHealth, sourceDeviceId: 'device', sourceId: sourceId, sourceName: 'Health',
  );

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

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> cancel() async => calls.add('cancel');
}

/// Writes [answer] as every recording's words, or waits for [hold] when set.
class FakeTranscriber extends Transcriber {
  String answer = 'Ask the fab if the flex stiffener can be 0.2 mm';
  Completer<String>? hold;
  Exception? error;
  final heard = <String>[];
  int closed = 0;

  @override
  Future<String> words(File wav) async {
    heard.add(wav.uri.pathSegments.last);
    if (error != null) throw error!;
    return hold == null ? answer : hold!.future;
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
