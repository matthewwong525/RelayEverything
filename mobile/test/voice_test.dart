import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/voice/model.dart';
import 'package:relay_app/voice/recorder.dart';
import 'package:relay_app/voice/transcriber.dart';
import 'package:relay_app/voice/wave.dart';

import 'fakes.dart';

/// A speech engine whose runs give the next of [answers]; a null answer is a run that ends only when it is killed, and
/// fails.
class FakeSpeechEngine implements SpeechEngine {
  FakeSpeechEngine(this.answers);

  final Queue<Future<String> Function()?> answers;
  int runs = 0;
  bool killed = false, disposed = false;
  Completer<String>? _running;

  @override
  Future<String> run(Sound sound) {
    runs++;
    final done = _running = Completer<String>();
    final give = answers.isEmpty ? null : answers.removeFirst();
    if (give != null) done.complete(give());
    return done.future;
  }

  @override
  void kill() {
    killed = true;
    final running = _running;
    if (running != null && !running.isCompleted) running.completeError(const SpeechEngineException('Killed'));
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  test('a failed run lets its engine go, and a run the app cancelled at the time limit has let it go already', () {
    expect(dropsEngine(cancelled: false), isTrue);
    expect(dropsEngine(cancelled: true), isFalse);
  });

  group('the speech engine', () {
    late File wav;
    late List<FakeSpeechEngine> loaded;
    late List<(SpeechModelInfo, String)> loads;
    late SherpaTranscriber transcriber;
    // What the engines' runs give, in order; null: a run that ends only when it is killed.
    late Queue<Future<String> Function()?> answers;
    setUp(() {
      final folder = tempFolder();
      wav = File('${folder.path}/note.wav')..writeAsBytesSync(wavOf(List.filled(1600, 1000)));
      loaded = [];
      loads = [];
      answers = Queue();
      transcriber = SherpaTranscriber(testSpeechModel(), () async => '${folder.path}/speech-model/test-model',
        loadEngine: (model, path) async {
          loads.add((model, path));
          final engine = FakeSpeechEngine(answers);
          loaded.add(engine);
          return engine;
        });
    });

    test('loads the model once, from its folder, and writes each recording\'s words in order', () async {
      answers.addAll([() async => ' Order more switches. ', () async => 'Call the fab.']);
      final first = transcriber.words(wav), second = transcriber.words(wav);
      expect([await first, await second], ['Order more switches.', 'Call the fab.']);
      expect([loaded.length, loaded.single.runs], [1, 2]);
      expect([loads.single.$1.id, loads.single.$2], ['test-model', endsWith('/speech-model/test-model')]);
    });

    test('a failed run frees its engine, and the next recording loads a new one that it keeps', () async {
      answers.add(() => Future.error(const SpeechEngineException('Failed to create offline stream')));
      await expectLater(transcriber.words(wav), throwsA(isA<SpeechEngineException>()));
      expect([loaded.length, loaded.single.disposed, loaded.single.killed], [1, true, false]);
      answers.addAll([() async => ' Order more switches.', () async => ' Order more switches.']);
      expect(await transcriber.words(wav), 'Order more switches.');
      expect(await transcriber.words(wav), 'Order more switches.');
      expect([loaded.length, loaded.last.runs, loaded.last.disposed, loaded.last.killed], [2, 2, false, false]);
    });

    test('the time limit kills only its own recording\'s engine: the next recording loads a new one and gets its words',
        () async {
      answers.addAll([null, () async => 'Order more switches.']);
      final late = transcriber.words(wav, limit: const Duration(seconds: 2));
      final next = transcriber.words(wav);
      await expectLater(late, throwsA(isA<TimeoutException>()));
      expect(await next, 'Order more switches.');
      expect([loaded.length, loaded.first.killed, loaded.first.runs, loaded.last.killed, loaded.last.runs],
        [2, true, 1, false, 1]);
    });

    test('close lets the engine go, and the next recording loads it again', () async {
      answers.addAll([() async => 'One.', () async => 'Two.']);
      expect(await transcriber.words(wav), 'One.');
      await transcriber.close();
      expect(loaded.single.disposed, isTrue);
      expect(await transcriber.words(wav), 'Two.');
      expect([loaded.length, loaded.last.disposed], [2, false]);
    });
  });

  group('the sherpa-onnx settings', () {
    test('load Parakeet small\'s files by their roles, as a NeMo transducer, on the CPU with 2 threads', () {
      final config = sherpaConfig(currentSpeechModel, '/m/parakeet-small');
      final model = config.model;
      expect([model.transducer.encoder, model.transducer.decoder, model.transducer.joiner, model.tokens], [
        '/m/parakeet-small/encoder.int8.onnx', '/m/parakeet-small/decoder.int8.onnx',
        '/m/parakeet-small/joiner.int8.onnx', '/m/parakeet-small/tokens.txt',
      ]);
      expect([model.modelType, model.provider, model.numThreads, model.debug], ['nemo_transducer', 'cpu', 2, false]);
    });

    test('refuse a kind of model the app can not load yet', () {
      const whisper = SpeechModelInfo(id: 'w', name: 'W', url: 'https://example.com/w.tar.bz2', sha256: '', bytes: 0,
        folder: 'w', kind: 'whisper', files: []);
      expect(() => sherpaConfig(whisper, '/m/w'), throwsArgumentError);
    });
  });

  test('a WAV\'s sound, as the speech engine reads it: mono, from -1 to 1, with its sample rate', () {
    final sound = soundOfWav(wavOf([16384, -32768, 0, 8192]))!;
    expect([sound.sampleRate, sound.samples], [16000, [0.5, -1.0, 0.0, 0.25]]);
    expect(soundOfWav(Uint8List.fromList('RIFF'.codeUnits)), isNull);
  });

  group('why the words did not come', () {
    test('the time limit, in minutes', () {
      expect(whyNoWords(TimeoutException('No words', const Duration(minutes: 2))), 'the phone took more than 2 minutes.');
      expect(whyNoWords(TimeoutException('No words', const Duration(minutes: 5, seconds: 30))),
        'the phone took more than 5 minutes.');
      expect(whyNoWords(TimeoutException('No words', const Duration(seconds: 30))), 'the phone took more than 30 seconds.');
      expect(whyNoWords(TimeoutException('No words')), 'the phone took too long.');
    });

    test('the speech engine\'s own words', () {
      expect(whyNoWords(const SpeechEngineException('Failed to create offline recognizer. Please check your config')),
        'the speech engine stopped (Failed to create offline recognizer. Please check your config).');
    });

    test('any other error: its first 80 characters, on one line', () {
      expect(whyNoWords(const SpeechEngineException('The speech engine stopped')),
        'the speech engine stopped (The speech engine stopped).');
      expect(whyNoWords(StateError('engine')), 'the speech engine stopped (Bad state: engine).');
      final long = whyNoWords(ArgumentError('Invalid argument:\n${'x' * 200}'));
      expect(long, 'the speech engine stopped (Invalid argument(s): Invalid argument: ${'x' * 41}).');
      expect(long, isNot(contains('\n')));
    });
  });

  group('the sound waves', () {
    test('a 16-bit WAV gives 48 levels, the loudest part at 1 and a quiet part low', () {
      // Quiet, then loud, then quiet: each a third of the recording.
      final samples = [
        for (var i = 0; i < 1600; i++) i.isEven ? 300 : -300,
        for (var i = 0; i < 1600; i++) i.isEven ? 30000 : -30000,
        for (var i = 0; i < 1600; i++) i.isEven ? 300 : -300,
      ];
      for (final extra in [false, true]) {
        final levels = levelsOfWav(wavOf(samples, extra: extra));
        expect(levels, hasLength(48), reason: 'extra $extra');
        expect([levels.first, levels[24], levels.last], [closeTo(0.01, 0.001), 1.0, closeTo(0.01, 0.001)]);
      }
      expect(levelsOfWav(wavOf(samples), bars: 3), [closeTo(0.01, 0.001), 1.0, closeTo(0.01, 0.001)]);
    });

    test('an m4a, or any file that is not a WAV, gives no levels, and a silent WAV gives 48 zeros', () {
      final m4a = Uint8List.fromList([0, 0, 0, 0x20, ...'ftypM4A '.codeUnits, ...List.filled(64, 7)]);
      expect([levelsOfWav(m4a), levelsOfWav(Uint8List(0)), levelsOfWav(Uint8List.fromList('RIFF'.codeUnits))],
        everyElement(isEmpty));
      expect(levelsOfWav(wavOf(List.filled(3200, 0))), List.filled(48, 0.0));
    });

    test('a WAV whose data size the recorder did not write reads to the end', () {
      final bytes = wavOf([for (var i = 0; i < 960; i++) i < 480 ? 1000 : 4000]);
      // The data chunk's size is the last 4 bytes before the samples.
      ByteData.sublistView(bytes).setUint32(bytes.length - 960 * 2 - 4, 0, Endian.little);
      final levels = levelsOfWav(bytes, bars: 2);
      expect(levels, [closeTo(0.25, 0.001), 1.0]);
    });
  });

  group('the words', () {
    test('drop marks for sounds with no speech', () {
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
    final transcriber = SherpaTranscriber(testSpeechModel(), () async {
      asked++;
      return '${folder.path}/speech-model/test-model';
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

    File archivePart() => File('${folder.path}/speech-model/test-model.tar.bz2.part');
    Directory unpacking() => Directory('${folder.path}/speech-model/test-model.part');
    List<String> entries(Directory directory) =>
      [for (final entry in directory.listSync()) entry.uri.pathSegments.lastWhere((part) => part.isNotEmpty)]..sort();

    test('is missing until the person says yes, and *Not now* gets nothing', () async {
      await model.load();
      expect(model.state, ModelState.missing);
      model.ask();
      expect(model.state, ModelState.asking);
      model.notNow();
      expect(model.state, ModelState.missing);
      expect(server.requests, isEmpty);
    });

    test('downloads the archive, checks it, keeps only the model\'s files, and is ready; the request carries no key',
        () async {
      final progress = <double>[];
      model.addListener(() => progress.add(model.progress));
      model.ask();
      expect(await model.download(), isTrue);
      expect(model.state, ModelState.ready);
      final kept = modelFolder(folder);
      expect(entries(kept), ['model.onnx', 'tokens.txt']);
      for (final MapEntry(key: name, value: bytes) in testModelFiles.entries) {
        expect(File('${kept.path}/$name').readAsBytesSync(), bytes);
      }
      expect(entries(Directory('${folder.path}/speech-model')), ['test-model']);
      // To 0.9 for the download, then the unpack to 1.
      expect(progress, contains(0.9));
      expect(progress, orderedEquals([...progress]..sort()));
      expect(progress.last, 1);
      final request = server.requests.single;
      expect(request.url, testSpeechModel().uri);
      expect(request.method, 'GET');
      expect(request.headers.keys.map((key) => key.toLowerCase()), isNot(contains(startsWith('cf-access'))));
      expect(request.headers.keys, isNot(contains('Range')));
      // A second open finds it, with no request.
      final again = speechModel(folder, server);
      await again.load();
      expect([again.state, server.requests.length], [ModelState.ready, 1]);
    });

    test('a dropped download fails, and *Try again* goes on from where it stopped', () async {
      final half = modelFile.length ~/ 2;
      server.dropAfter = half;
      expect(await model.download(), isFalse);
      expect([model.state, model.problem], [ModelState.failed, ModelProblem.offline]);
      expect(await archivePart().length(), half);
      expect(modelFolder(folder).existsSync(), isFalse);
      // The app closed and opened again: the archive's part stays for the resume.
      final again = speechModel(folder, server);
      await again.load();
      expect([again.state, archivePart().existsSync()], [ModelState.missing, true]);
      expect(await again.download(), isTrue);
      expect(server.requests.last.headers['Range'], 'bytes=$half-');
      expect(entries(modelFolder(folder)), ['model.onnx', 'tokens.txt']);
      expect([again.state, archivePart().existsSync()], [ModelState.ready, false]);
    });

    test('an archive with the wrong checksum is deleted, and voice notes stay off', () async {
      server.file = List<int>.filled(modelFile.length, 1);
      expect(await model.download(), isFalse);
      expect([model.state, model.problem], [ModelState.failed, ModelProblem.damaged]);
      expect([archivePart().existsSync(), unpacking().existsSync(), modelFolder(folder).existsSync()],
        [false, false, false]);
    });

    test('an archive whose file has the wrong checksum is deleted with what came out of it, and voice notes stay off',
        () async {
      final bad = modelArchive(files: {...testModelFiles, 'model.onnx': List<int>.filled(4096, 9)});
      server.file = bad;
      final damaged = SpeechModel(folder: () async => folder, client: server.client, info: testSpeechModel(archive: bad));
      expect(await damaged.download(), isFalse);
      expect([damaged.state, damaged.problem], [ModelState.failed, ModelProblem.damaged]);
      expect([archivePart().existsSync(), unpacking().existsSync(), modelFolder(folder).existsSync()],
        [false, false, false]);
    });

    test('an archive that lacks one of the model\'s files is refused', () async {
      final short = modelArchive(files: {'model.onnx': testModelFiles['model.onnx']!});
      server.file = short;
      final damaged = SpeechModel(folder: () async => folder, client: server.client, info: testSpeechModel(archive: short));
      expect(await damaged.download(), isFalse);
      expect([damaged.problem, modelFolder(folder).existsSync(), unpacking().existsSync()],
        [ModelProblem.damaged, false, false]);
    });

    test('unpacks an entry whose name is too long for a plain tar header', () async {
      final long = 'sherpa-onnx-${'x' * 120}';
      final archive = modelArchive(folder: long);
      final info = testSpeechModel(archive: archive);
      final at = '${folder.path}/long.tar.bz2';
      File(at).writeAsBytesSync(archive);
      final into = '${folder.path}/long';
      final named = SpeechModelInfo(id: info.id, name: info.name, url: info.url, sha256: info.sha256, bytes: info.bytes,
        folder: long, kind: info.kind, files: info.files);
      expect(unpackModel(named, archive: at, into: into), UnpackResult.done);
      expect(entries(Directory(into)), ['model.onnx', 'tokens.txt']);
    });

    test('with no connection, it fails and offers to try again', () async {
      server.offline = true;
      expect(await model.download(), isFalse);
      expect([model.state, model.problem], [ModelState.failed, ModelProblem.offline]);
    });

    test('each of its files is kept out of the phone\'s backup', () async {
      final marked = <String>[];
      final kept = SpeechModel(folder: () async => folder, client: server.client, info: testSpeechModel(),
        excludeFromBackup: (file) async => marked.add(file.path));
      expect(await kept.download(), isTrue);
      final at = (await kept.directory).path;
      expect(marked, ['$at/model.onnx', '$at/tokens.txt']);
    });

    test('an update deletes the old model: whisper.cpp\'s file and its part go, and the next voice note asks', () async {
      final models = Directory('${folder.path}/speech-model')..createSync(recursive: true);
      File('${models.path}/ggml-base.en-q5_1.bin').writeAsBytesSync([1, 2, 3]);
      File('${models.path}/ggml-base.en-q5_1.bin.part').writeAsBytesSync([1]);
      Directory('${models.path}/older-model/inner').createSync(recursive: true);
      await model.load();
      expect(model.state, ModelState.missing);
      expect(entries(models), isEmpty);
      model.ask();
      expect(model.state, ModelState.asking);
    });

    test('the clean-up keeps the current model and its parts', () async {
      await placeModel(folder);
      archivePart().writeAsBytesSync([1]);
      unpacking().createSync();
      await model.load();
      expect(model.state, ModelState.ready);
      expect(entries(Directory('${folder.path}/speech-model')),
        ['test-model', 'test-model.part', 'test-model.tar.bz2.part']);
    });

    test('remove deletes its folder and every part, and the next voice note asks again', () async {
      expect(await model.download(), isTrue);
      archivePart().writeAsBytesSync([1]);
      unpacking().createSync();
      await model.remove();
      expect(model.state, ModelState.missing);
      expect(entries(Directory('${folder.path}/speech-model')), isEmpty);
      model.ask();
      expect(model.state, ModelState.asking);
    });

    test('the current model is Parakeet small from sherpa-onnx\'s GitHub release: a 103 MB download, 130 MB kept', () {
      expect(speechModels, contains(currentSpeechModel));
      expect([currentSpeechModel.id, currentSpeechModel.name, currentSpeechModel.kind],
        ['parakeet-small', 'Parakeet small', 'nemo_transducer']);
      expect(currentSpeechModel.uri.host, 'github.com');
      expect(currentSpeechModel.uri.path, startsWith('/k2-fsa/sherpa-onnx/releases/download/asr-models/'));
      expect(currentSpeechModel.bytes, 108035095);
      expect(currentSpeechModel.keptBytes, 136490421);
      expect([megabytes(currentSpeechModel.bytes), megabytes(currentSpeechModel.keptBytes)], ['103 MB', '130 MB']);
      expect([for (final file in currentSpeechModel.files) file.role], ['encoder', 'decoder', 'joiner', 'tokens']);
      final hex = RegExp(r'^[0-9a-f]{64}$');
      expect([currentSpeechModel.sha256, for (final file in currentSpeechModel.files) file.sha256], everyElement(matches(hex)));
      // Each id is a folder name of its own.
      expect({for (final info in speechModels) info.id}, hasLength(speechModels.length));
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
