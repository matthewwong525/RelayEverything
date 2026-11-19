import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/voice/model.dart';
import 'package:relay_app/voice/transcriber.dart';

/// Runs the real Parakeet small model, once, on a computer that has its archive: it unpacks the archive as the phone
/// does, then writes the words of one of its test recordings through sherpa-onnx. CI has no archive, so it skips.
///
/// `RELAY_SPEECH_ARCHIVE=<the .tar.bz2> RELAY_SPEECH_WAV=<its test_wavs/0.wav> flutter test test/real_speech_model_test.dart`;
/// on Linux, also set `LD_LIBRARY_PATH` to the pub cache's `sherpa_onnx_linux-<version>/linux/x64`.
void main() {
  final archive = Platform.environment['RELAY_SPEECH_ARCHIVE'];
  final wav = Platform.environment['RELAY_SPEECH_WAV'];
  final skip = archive == null || wav == null ? 'Set RELAY_SPEECH_ARCHIVE and RELAY_SPEECH_WAV to run the real model' : null;

  test('Parakeet small unpacks and writes a recording\'s words with punctuation', () async {
    final folder = Directory.systemTemp.createTempSync('relay-real-model-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final into = '${folder.path}/${currentSpeechModel.id}';
    final clock = Stopwatch()..start();
    final progress = <double>[];
    expect(unpackModel(currentSpeechModel, archive: archive!, into: into, onProgress: progress.add), UnpackResult.done);
    expect([progress.length > 50, progress.last], [true, 1]);
    final unpacked = clock.elapsed;
    clock.reset();
    final transcriber = SherpaTranscriber(currentSpeechModel, () async => into);
    final first = await transcriber.words(File(wav!));
    final loadAndDecode = clock.elapsed;
    clock.reset();
    final second = await transcriber.words(File(wav));
    final decode = clock.elapsed;
    await transcriber.close();
    // ignore: avoid_print
    print('unpack ${unpacked.inMilliseconds} ms, load and decode ${loadAndDecode.inMilliseconds} ms, '
      'decode ${decode.inMilliseconds} ms: $first');
    expect(first, second);
    expect(first, contains('Phoebe'));
    expect(first, matches(RegExp(r'^[A-Z].*\.$')));
    expect(first, contains(','));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}
