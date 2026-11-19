import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show protected, visibleForTesting;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model.dart' show SpeechModelInfo;
import 'wave.dart' show soundOfWav;

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

/// Writes the words of one recording. The app's is sherpa-onnx on the phone; a test's is a fake.
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

/// One recording's sound, as the speech engine reads it.
typedef Sound = ({Float32List samples, int sampleRate});

/// Reads a WAV file in a background isolate. It is top-level, so its closure holds only [path]: a closure in a method
/// can hold `this`, and a [Future] in `this` can not go to an isolate, so [Isolate.run] throws an [ArgumentError].
/// A file that is not a 16-bit PCM WAV has no sound.
Future<Sound> _readWav(String path) => Isolate.run(() =>
  soundOfWav(File(path).readAsBytesSync()) ?? (samples: Float32List(0), sampleRate: 16000));

// A mark a speech model can write for a sound with no words: [BLANK_AUDIO], [ Silence ], [MUSIC].
final _bracketed = RegExp(r'\[[^\]]*\]');
// A segment wholly in round brackets is a sound too: (music), (wind blowing).
final _onlySounds = RegExp(r'^(\s*\([^)]*\)\s*)+$');
// A segment of only marks, such as "..." or "-", has no words.
final _noLetters = RegExp(r'^[^\p{L}\p{N}]*$', unicode: true);
final _spaces = RegExp(r'\s+');

/// The words of [segments] with no-speech marks taken out, one space between words. Empty when no segment holds a word.
String cleanWords(Iterable<String> segments) {
  final kept = <String>[];
  for (final segment in segments) {
    final text = segment.replaceAll(_bracketed, ' ').trim();
    if (text.isEmpty || _onlySounds.hasMatch(text) || _noLetters.hasMatch(text)) continue;
    kept.add(text);
  }
  return kept.join(' ').replaceAll(_spaces, ' ').trim();
}

/// True when a run that failed must let its engine go, so the next recording loads a new one: a native error can stay
/// in the engine and fail each later run. A run the app [cancelled] at the time limit has let it go already: its cancel
/// stopped the engine.
bool dropsEngine({required bool cancelled}) => !cancelled;

/// An error from the speech engine, with its own words.
class SpeechEngineException implements Exception {
  const SpeechEngineException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _lineBreaks = RegExp(r'\s+');

/// The reason a recording's words did not come, as the note's page shows it after *Why:*. It stays on the phone.
String whyNoWords(Object error) {
  if (error is TimeoutException) {
    final limit = error.duration;
    if (limit == null) return 'the phone took too long.';
    final minutes = limit.inMinutes, seconds = limit.inSeconds;
    final words = minutes >= 1
      ? '$minutes minute${minutes == 1 ? '' : 's'}' : '$seconds second${seconds == 1 ? '' : 's'}';
    return 'the phone took more than $words.';
  }
  final text = '$error'.replaceAll(_lineBreaks, ' ').trim();
  return 'the speech engine stopped (${text.length > 80 ? text.substring(0, 80) : text}).';
}

/// A loaded speech engine, as [SherpaTranscriber] uses it. The app's is sherpa-onnx in a worker isolate; a test's is a
/// fake.
abstract interface class SpeechEngine {
  /// The text of one recording's [sound]. One run at a time.
  Future<String> run(Sound sound);

  /// Stops the engine at once, such as at the time limit: the run fails, the engine is not used again, and it frees
  /// its model once a native call that runs now returns.
  void kill();

  /// Frees the engine once its run ends: after a failed run, or before *Remove* deletes the model.
  void dispose();
}

/// The sherpa-onnx settings that load [model] from the folder [folder]: CPU, on 2 threads. Each of the model's files
/// goes where its role says. The CPU works on every phone, with the app not on the screen, such as when a watch note
/// starts it, and on the simulator.
sherpa.OfflineRecognizerConfig sherpaConfig(SpeechModelInfo model, String folder) {
  final paths = {for (final file in model.files) file.role: '$folder/${file.name}'};
  String path(String role) => paths[role] ?? (throw ArgumentError('${model.id} has no $role file'));
  return switch (model.kind) {
    'nemo_transducer' || 'transducer' => sherpa.OfflineRecognizerConfig(model: sherpa.OfflineModelConfig(
      transducer: sherpa.OfflineTransducerModelConfig(encoder: path('encoder'), decoder: path('decoder'),
        joiner: path('joiner')),
      tokens: path('tokens'), modelType: model.kind, numThreads: 2, provider: 'cpu', debug: false)),
    _ => throw ArgumentError('sherpa-onnx can not load a ${model.kind} model here'),
  };
}

/// sherpa-onnx in its own long-lived isolate: a decode is a native call that blocks its isolate, and a loaded
/// recognizer can not move between isolates. The worker loads the model once, then decodes one recording per message.
/// The worker is never killed: sherpa-onnx sets no native finalizer, so only the worker's own `recognizer.free()` lets
/// the model's memory go. A killed worker keeps it until the app closes.
final class _SherpaWorker implements SpeechEngine {
  _SherpaWorker._(this._send, this._answers);

  final SendPort _send;
  final StreamIterator<Object?> _answers;
  bool _stopped = false;

  static Future<SpeechEngine> load(SpeechModelInfo model, String folder) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_work, (port.sendPort, sherpaConfig(model, folder)), onExit: port.sendPort,
      onError: port.sendPort, debugName: 'speech-engine');
    final answers = StreamIterator<Object?>(port);
    final first = await answers.moveNext() ? answers.current : null;
    if (first is SendPort) return _SherpaWorker._(first, answers);
    port.close();
    isolate.kill(priority: Isolate.immediate);
    throw _errorOf(first);
  }

  @override
  Future<String> run(Sound sound) async {
    if (_stopped) throw const SpeechEngineException('The speech engine stopped');
    _send.send(sound);
    final answer = await _answers.moveNext() ? _answers.current : null;
    if (answer is String) return answer;
    throw _errorOf(answer);
  }

  // Dart can not stop a native decode, so a kill stops only the wait: the run fails now, and the worker frees the
  // recognizer once its decode returns. Its answer goes nowhere.
  @override
  void kill() => dispose();

  @override
  void dispose() {
    if (_stopped) return;
    _stopped = true;
    // The worker frees the recognizer and ends once its run ends. The cancel ends a run that waits now.
    _send.send(null);
    unawaited(_answers.cancel());
  }

  static Object _errorOf(Object? answer) => switch (answer) {
    (String error,) => SpeechEngineException(error),
    [final error, _] => SpeechEngineException('$error'),
    _ => const SpeechEngineException('The speech engine stopped'),
  };
}

/// The worker isolate: it loads the recognizer, sends back its port, then answers each sound with its text, or with a
/// one-item record that holds the error. A null message frees the recognizer and ends the worker.
void _work((SendPort, sherpa.OfflineRecognizerConfig) job) {
  final (answer, config) = job;
  final sherpa.OfflineRecognizer recognizer;
  try {
    sherpa.initBindings();
    recognizer = sherpa.OfflineRecognizer(config);
  } on Object catch (error) {
    answer.send((_message(error),));
    return;
  }
  final inbox = ReceivePort();
  answer.send(inbox.sendPort);
  inbox.listen((message) {
    if (message is! Sound) {
      recognizer.free();
      inbox.close();
      return;
    }
    try {
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: message.samples, sampleRate: message.sampleRate);
        recognizer.decode(stream);
        answer.send(recognizer.getResult(stream).text);
      } finally {
        stream.free();
      }
    } on Object catch (error) {
      answer.send((_message(error),));
    }
  });
}

String _message(Object error) => '$error'.replaceFirst(RegExp(r'^Exception: '), '');

/// sherpa-onnx through its `sherpa_onnx` package. The model loads at the first recording and stays loaded in its worker
/// isolate, until a run fails: then the engine frees its model, and the next recording loads it again ([dropsEngine]).
/// sherpa-onnx has no cancel, so the time limit stops the wait, the worker frees its model once its decode returns, and
/// the next recording loads a new one. The WAV file is read in a background isolate too, so the timeline never stops.
class SherpaTranscriber extends Transcriber {
  /// A test gives [loadEngine]; the app loads sherpa-onnx.
  SherpaTranscriber(this.model, this.folder,
    {@visibleForTesting Future<SpeechEngine> Function(SpeechModelInfo model, String folder)? loadEngine})
    : _load = loadEngine ?? _SherpaWorker.load;

  /// Which model to load.
  final SpeechModelInfo model;
  /// The folder that holds the model's files; [SpeechModel] keeps them there.
  final Future<String> Function() folder;

  final Future<SpeechEngine> Function(SpeechModelInfo model, String folder) _load;
  SpeechEngine? _engine;

  @override
  @protected
  Future<String> write(File wav, WordsJob job) async {
    final sound = await _readWav(wav.path);
    if (sound.samples.isEmpty) return '';
    final engine = _engine ??= await _load(model, await folder());
    // The time limit can pass while the WAV or the model loads: then the engine starts no job.
    if (job.cancelled) throw StateError('Cancelled at the time limit');
    job.onCancel(() {
      if (identical(_engine, engine)) _engine = null;
      engine.kill();
    });
    try {
      return cleanWords([await engine.run(sound)]);
    } catch (_) {
      if (dropsEngine(cancelled: job.cancelled)) _drop(engine);
      rethrow;
    }
  }

  // Lets go of an engine whose run failed, and frees its model: the engine is idle now. The next recording loads a new
  // one.
  void _drop(SpeechEngine engine) {
    if (identical(_engine, engine)) _engine = null;
    engine.dispose();
  }

  @override
  Future<void> close() async {
    await super.close();
    _engine?.dispose();
    _engine = null;
  }
}
