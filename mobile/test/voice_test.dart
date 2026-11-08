import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/voice/model.dart';
import 'package:relay_app/voice/recorder.dart';
import 'package:relay_app/voice/transcriber.dart';

import 'fakes.dart';

void main() {
  group('the words', () {
    test('drop whisper.cpp\'s marks for sounds with no speech', () {
      expect(cleanWords([' [BLANK_AUDIO]']), '');
      expect(cleanWords([' (music)', ' [ Silence ]']), '');
      expect(cleanWords(['(wind blowing) (birds chirping)']), '');
      expect(cleanWords(['', '   ', ' ...']), '');
      expect(cleanWords([]), '');
    });

    test('keep real words, one space apart, with a mark taken out of their segment', () {
      expect(cleanWords([' Ask the fab if the flex stiffener', ' can be 0.2 mm.']), 'Ask the fab if the flex stiffener can be 0.2 mm.');
      expect(cleanWords([' [BLANK_AUDIO]', ' Order more switches.', ' (music)']), 'Order more switches.');
      expect(cleanWords([' Order more [inaudible] switches.']), 'Order more switches.');
      // Round brackets inside spoken words stay: only a segment wholly in them is a sound.
      expect(cleanWords([' Buy milk (two liters).']), 'Buy milk (two liters).');
    });
  });

  test('the transcriber reads a WAV in a background isolate: a silent one has no words and loads no model', () async {
    final folder = tempFolder();
    final wav = File('${folder.path}/silent.wav');
    // A 16 kHz mono 16-bit header with no samples.
    final header = ByteData(44)
      ..setUint32(0, 0x46464952, Endian.little)..setUint32(4, 36, Endian.little)..setUint32(8, 0x45564157, Endian.little)
      ..setUint32(12, 0x20746d66, Endian.little)..setUint32(16, 16, Endian.little)..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)..setUint32(24, 16000, Endian.little)..setUint32(28, 32000, Endian.little)
      ..setUint16(32, 2, Endian.little)..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x61746164, Endian.little)..setUint32(40, 0, Endian.little);
    await wav.writeAsBytes(header.buffer.asUint8List());
    var asked = 0;
    final transcriber = WhisperTranscriber(() async {
      asked++;
      return '${folder.path}/model.bin';
    });
    expect(await transcriber.words(wav), '');
    expect(await transcriber.words(wav), '');
    expect(asked, 0);
  });

  group('the speech model', () {
    late Directory folder;
    late ModelServer server;
    late SpeechModel model;
    setUp(() {
      folder = tempFolder();
      server = ModelServer();
      model = speechModel(folder, server);
    });

    Future<File> file() => model.file;

    test('is missing until the person says yes, and *Not now* gets nothing', () async {
      await model.load();
      expect(model.state, ModelState.missing);
      model.ask();
      expect(model.state, ModelState.asking);
      model.notNow();
      expect(model.state, ModelState.missing);
      expect(server.requests, isEmpty);
    });

    test('downloads, checks its checksum, and is ready; the request carries no key', () async {
      final progress = <double>[];
      model.addListener(() => progress.add(model.progress));
      model.ask();
      expect(await model.download(), isTrue);
      expect(model.state, ModelState.ready);
      expect(await (await file()).readAsBytes(), modelFile);
      expect(await File('${(await file()).path}.part').exists(), isFalse);
      expect(progress.last, 1);
      final request = server.requests.single;
      expect(request.url, modelUrl);
      expect(request.method, 'GET');
      expect(request.headers.keys.map((key) => key.toLowerCase()), isNot(contains(startsWith('cf-access'))));
      expect(request.headers.keys, isNot(contains('Range')));
      // A second open finds it, with no request.
      final again = speechModel(folder, server);
      await again.load();
      expect([again.state, server.requests.length], [ModelState.ready, 1]);
    });

    test('a dropped download fails, and *Try again* goes on from where it stopped', () async {
      server.dropAfter = 1000;
      expect(await model.download(), isFalse);
      expect([model.state, model.problem], [ModelState.failed, ModelProblem.offline]);
      expect(await File('${(await file()).path}.part').length(), 1000);
      expect(await (await file()).exists(), isFalse);
      expect(await model.download(), isTrue);
      expect(server.requests.last.headers['Range'], 'bytes=1000-');
      expect(await (await file()).readAsBytes(), modelFile);
      expect(model.state, ModelState.ready);
    });

    test('a file with the wrong checksum is deleted, and voice notes stay off', () async {
      server.file = List<int>.filled(modelFile.length, 1);
      expect(await model.download(), isFalse);
      expect([model.state, model.problem], [ModelState.failed, ModelProblem.damaged]);
      expect(await (await file()).exists(), isFalse);
      expect(await File('${(await file()).path}.part').exists(), isFalse);
    });

    test('with no connection, it fails and offers to try again', () async {
      server.offline = true;
      expect(await model.download(), isFalse);
      expect([model.state, model.problem], [ModelState.failed, ModelProblem.offline]);
    });

    test('is kept out of the phone\'s backup', () async {
      final marked = <String>[];
      final kept = SpeechModel(folder: () async => folder, client: server.client, sha256: modelFileSha, bytes: modelFile.length,
        excludeFromBackup: (file) async => marked.add(file.path));
      expect(await kept.download(), isTrue);
      expect(marked, [(await kept.file).path]);
    });

    test('remove deletes it, and the next voice note asks again', () async {
      expect(await model.download(), isTrue);
      await model.remove();
      expect(model.state, ModelState.missing);
      expect(await (await file()).exists(), isFalse);
      model.ask();
      expect(model.state, ModelState.asking);
    });

    test('is the English base model, 57 MB, at a fixed revision of whisper.cpp\'s page', () {
      expect(modelUrl.host, 'huggingface.co');
      expect(modelUrl.path, endsWith('/ggml-base.en-q5_1.bin'));
      expect(modelUrl.path, isNot(contains('/main/')));
      expect(megabytes(modelSize), '57 MB');
      expect(modelSha256, hasLength(64));
    });
  });

  group('the recorder', () {
    late Directory folder;
    late FakeMicrophone microphone;
    late DateTime now;
    late List<(Duration, void Function())> timers;
    late VoiceRecorder recorder;

    setUp(() {
      folder = tempFolder();
      microphone = FakeMicrophone();
      now = DateTime(2026, 11, 5, 9, 41);
      timers = [];
      recorder = VoiceRecorder(microphone: microphone, folder: () async => folder, clock: () => now,
        timer: (length, callback) {
          timers.add((length, callback));
          return Timer(const Duration(days: 1), () {});
        });
    });
    tearDown(() async => recorder.cancel());

    File fileOf(String clientId) => File('${folder.path}/voice/$clientId.wav');

    test('the sound level goes from 0 at −60 dBFS or less to 1 at 0 dBFS, and only while it records', () async {
      expect([levelOf(-120), levelOf(-60), levelOf(-30), levelOf(0), levelOf(6), levelOf(double.nan),
        levelOf(double.negativeInfinity)], [0, 0, 0.5, 1, 1, 0, 0]);
      expect(recorder.levels, isNull);
      microphone.heard = [0.2, 0.9];
      await recorder.start('abc');
      expect(await recorder.levels!.take(2).toList(), [0.2, 0.9]);
      final ended = recorder.levels!.toList();
      await recorder.cancel();
      expect([await ended, recorder.levels], [isEmpty, isNull]);
    });

    test('records to <support>/voice/<clientId>.wav and keeps a hold of 0.5 s or more', () async {
      expect(await recorder.start('abc'), isTrue);
      expect(recorder.recording, isTrue);
      now = now.add(const Duration(milliseconds: 500));
      final kept = (await recorder.stop())!;
      expect([kept.clientId, kept.audioPath, kept.length], ['abc', 'voice/abc.wav', const Duration(milliseconds: 500)]);
      expect(kept.startedAt, DateTime(2026, 11, 5, 9, 41));
      expect(await fileOf('abc').exists(), isTrue);
      expect(microphone.calls, ['start', 'stop']);
      expect(recorder.recording, isFalse);
    });

    test('keeps nothing from a press shorter than 0.5 s', () async {
      await recorder.start('bump');
      now = now.add(const Duration(milliseconds: 300));
      expect(await recorder.stop(), isNull);
      expect(await fileOf('bump').exists(), isFalse);
      expect(microphone.calls, ['start', 'cancel']);
    });

    test('cancel keeps nothing', () async {
      await recorder.start('slid');
      now = now.add(const Duration(seconds: 3));
      await recorder.cancel();
      expect(await fileOf('slid').exists(), isFalse);
      expect(await recorder.stop(), isNull);
    });

    test('ends by itself at 5 minutes, as if the person let go', () async {
      Recording? ended;
      recorder.onLongest = (recording) => ended = recording;
      await recorder.start('long');
      expect(timers.single.$1, const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 5));
      timers.single.$2();
      await pumpEventQueue();
      expect([ended?.clientId, ended?.length], ['long', const Duration(minutes: 5)]);
      expect(recorder.recording, isFalse);
      expect(await fileOf('long').exists(), isTrue);
    });

    test('a microphone that does not start records nothing, and the next press records', () async {
      microphone.startError = Exception('busy');
      await expectLater(recorder.start('busy'), throwsException);
      expect([recorder.recording, recorder.startedAt, await fileOf('busy').exists()], [false, null, false]);
      expect(await recorder.start('next'), isTrue);
      expect(recorder.recording, isTrue);
    });

    test('marks a kept recording to stay out of iCloud backup, and nothing for a short press', () async {
      final marked = <String>[];
      recorder = VoiceRecorder(microphone: microphone, folder: () async => folder, clock: () => now,
        excludeFromBackup: (file) async => marked.add(file.path));
      await recorder.start('bump');
      now = now.add(const Duration(milliseconds: 300));
      await recorder.stop();
      expect(marked, isEmpty);
      await recorder.start('kept');
      now = now.add(const Duration(seconds: 2));
      expect(await recorder.stop(), isNotNull);
      expect(marked, [fileOf('kept').path]);
    });

    test('a failed backup mark still keeps the recording', () async {
      recorder = VoiceRecorder(microphone: microphone, folder: () async => folder, clock: () => now,
        excludeFromBackup: (file) async => throw Exception('channel'));
      await recorder.start('kept');
      now = now.add(const Duration(seconds: 2));
      expect(await recorder.stop(), isNotNull);
      expect(await fileOf('kept').exists(), isTrue);
    });

    test('a refused microphone records nothing', () async {
      microphone.allowed = false;
      expect(await recorder.start('no'), isFalse);
      expect([recorder.recording, microphone.calls], [false, isEmpty]);
    });
  });
}
