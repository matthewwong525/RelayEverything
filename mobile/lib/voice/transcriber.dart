import 'dart:io';
import 'dart:isolate';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

/// Writes the words of one recording. The app's is whisper.cpp on the phone; a test's is a fake. The Relay ring can
/// call the same one later with its own recording.
abstract class Transcriber {
  /// The recording's words, cleaned; empty when it has no speech.
  Future<String> words(File wav);

  /// Lets go of the speech model, such as before *Remove* deletes it.
  Future<void> close() async {}
}

// A mark whisper.cpp writes for a sound with no words: [BLANK_AUDIO], [ Silence ], [MUSIC].
final _bracketed = RegExp(r'\[[^\]]*\]');
// A segment wholly in round brackets is a sound too: (music), (wind blowing).
final _onlySounds = RegExp(r'^(\s*\([^)]*\)\s*)+$');
// A segment of only marks, such as "..." or "-", has no words.
final _noLetters = RegExp(r'^[^\p{L}\p{N}]*$', unicode: true);
final _spaces = RegExp(r'\s+');

/// The words of [segments] with whisper.cpp's no-speech marks taken out, one space between words. Empty when no
/// segment holds a word.
String cleanWords(Iterable<String> segments) {
  final kept = <String>[];
  for (final segment in segments) {
    final text = segment.replaceAll(_bracketed, ' ').trim();
    if (text.isEmpty || _onlySounds.hasMatch(text) || _noLetters.hasMatch(text)) continue;
    kept.add(text);
  }
  return kept.join(' ').replaceAll(_spaces, ' ').trim();
}

/// whisper.cpp through `whisper_cpp_flutter_plus`. The model loads at the first recording and stays loaded. The
/// binding loads the model and writes the words in a background isolate, and the WAV file is read in one too, so the
/// timeline never stops.
class WhisperTranscriber extends Transcriber {
  WhisperTranscriber(this.modelPath);

  /// Where the speech model is; [SpeechModel] keeps it there.
  final Future<String> Function() modelPath;

  WhisperEngine? _engine;
  // One recording at a time: the engine takes one job.
  Future<void> _last = Future.value();

  @override
  Future<String> words(File wav) {
    final next = _last.then((_) => _words(wav));
    _last = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<String> _words(File wav) async {
    final samples = await Isolate.run(() => WhisperAudio.readWav(wav));
    if (samples.isEmpty) return '';
    final engine = _engine ??= await WhisperEngine.load(await modelPath());
    final result = await engine.transcribe(samples, options: const TranscribeOptions(language: 'en', suppressNonSpeechTokens: true)).result;
    return cleanWords([for (final segment in result.segments) segment.text]);
  }

  @override
  Future<void> close() async {
    await _last;
    _engine?.dispose();
    _engine = null;
  }
}
