import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show protected;
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

/// One recording's writing, so a time limit stops this recording and no other.
class WordsJob {
  WordsJob._();

  bool _cancelled = false;
  bool _ended = false;
  void Function()? _stop;

  /// True once this recording passed its time limit: start no more work for it.
  bool get cancelled => _cancelled;

  /// Calls [stop] if this recording passes its time limit, at once when it has already.
  void onCancel(void Function() stop) {
    if (_cancelled) return stop();
    _stop = stop;
  }

  void _cancel() {
    if (_cancelled || _ended) return;
    _cancelled = true;
    _stop?.call();
  }

  // The work ended: a late time limit must not stop a job the engine has let go of.
  void _end() {
    _ended = true;
    _stop = null;
  }
}

/// Writes the words of one recording. The app's is whisper.cpp on the phone; a test's is a fake. The Relay ring can
/// call the same one later with its own recording.
abstract class Transcriber {
  // One recording at a time, in order: the engine takes one job. This completes when the last job ends.
  Future<void> _last = Future.value();
  // When the last recording's limit lets the next one's start: its job ends, or it passes its limit. A stuck job that
  // its cancel does not stop so frees the clock of the notes behind it.
  Future<void> _clock = Future.value();

  /// The recording's words, cleaned; empty when it has no speech. A recording waits while an earlier one is written.
  /// Its [limit] counts from when the job before it ends, or passes its own limit: not while an earlier job runs in
  /// time. Past the limit, only this recording's writing stops, and the future fails with a [TimeoutException]. A
  /// recording that passes its limit before its job starts never starts it.
  Future<String> words(File wav, {Duration? limit}) {
    final job = WordsJob._();
    final released = Completer<void>();
    void release() {
      if (!released.isCompleted) released.complete();
    }

    final clock = _clock;
    final run = _last.then((_) {
      if (job.cancelled) throw TimeoutException('No words after $limit', limit);
      return write(wav, job).whenComplete(job._end);
    });
    _last = run.then((_) {}, onError: (_) {}).whenComplete(release);
    _clock = released.future;
    if (limit == null) return run;
    return clock.then((_) => run.timeout(limit, onTimeout: () {
      job._cancel();
      release();
      throw TimeoutException('No words after $limit', limit);
    }));
  }

  /// Writes one recording's words, with the engine free. It checks [WordsJob.cancelled] before a long step, and gives
  /// [WordsJob.onCancel] what stops the engine.
  @protected
  Future<String> write(File wav, WordsJob job);

  /// Lets go of the speech model, such as before *Remove* deletes it. It waits for the writing that runs now.
  Future<void> close() => _last;
}

/// Reads a WAV file in a background isolate. It is top-level, so its closure holds only [path]: a closure in a method
/// can hold `this`, and a [Future] in `this` can not go to an isolate, so [Isolate.run] throws an [ArgumentError].
Future<Float32List> _readWav(String path) => Isolate.run(() => WhisperAudio.readWav(File(path)));

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

  @override
  @protected
  Future<String> write(File wav, WordsJob job) async {
    final samples = await _readWav(wav.path);
    if (samples.isEmpty) return '';
    final engine = _engine ??= await WhisperEngine.load(await modelPath());
    // The time limit can pass while the WAV or the model loads: then the engine starts no job.
    if (job.cancelled) throw StateError('Cancelled at the time limit');
    final task = engine.transcribe(samples, options: const TranscribeOptions(language: 'en', suppressNonSpeechTokens: true));
    // The native run starts later, in a new isolate, and clears the cancel flag as it starts: a cancel before then is
    // lost. So once cancelled, cancel again every 100 ms until the result comes. The package frees the native job in
    // its own listener on the result, which runs before this one in the same turn, so no tick can touch a freed job.
    var running = true;
    Timer? again;
    task.result.whenComplete(() {
      running = false;
      again?.cancel();
    }).ignore();
    job.onCancel(() {
      if (!running) return;
      task.cancel();
      again = Timer.periodic(const Duration(milliseconds: 100), (_) => task.cancel());
    });
    final result = await task.result;
    return cleanWords([for (final segment in result.segments) segment.text]);
  }

  @override
  Future<void> close() async {
    await super.close();
    _engine?.dispose();
    _engine = null;
  }
}
