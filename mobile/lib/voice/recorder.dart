import 'dart:async';
import 'dart:io';

import 'package:record/record.dart';

import 'wave.dart';

/// The phone's microphone. The app's is the `record` package; a test's is a fake that writes a file.
abstract class Microphone {
  /// Asks for the microphone the first time; true when Relay may use it.
  Future<bool> allow();

  /// Starts writing 16 kHz mono WAV, the sound whisper.cpp reads, to [path].
  Future<void> start(String path);

  /// Ends the file.
  Future<void> stop();

  /// Ends and deletes the file.
  Future<void> cancel();

  /// The sound level while it records, from 0 for silence to 1 for loud, about ten times a second.
  Stream<double> levels();
}

/// A level from 0 to 1 for [dbfs], the loudness from −60, near silence, to 0, the loudest.
double levelOf(double dbfs) => dbfs.isNaN ? 0 : ((dbfs + 60) / 60).clamp(0.0, 1.0);

class PhoneMicrophone implements Microphone {
  final _recorder = AudioRecorder();

  @override
  Future<bool> allow() => _recorder.hasPermission();

  @override
  Future<void> start(String path) =>
    _recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);

  @override
  Future<void> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Stream<double> levels() =>
    _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).map((amplitude) => levelOf(amplitude.current));
}

/// One finished recording: where it is, from the support folder, and how long.
class Recording {
  const Recording({required this.clientId, required this.audioPath, required this.startedAt, required this.length});

  final String clientId;
  /// `voice/<clientId>.wav`, from the app's support folder. The folder's full path can change when the app updates,
  /// so the store keeps this part only.
  final String audioPath;
  final DateTime startedAt;
  final Duration length;
}

/// A press shorter than this keeps nothing: a bump in a pocket makes no note.
const shortest = Duration(milliseconds: 500);

/// A recording ends by itself at this length, so a stuck press can not fill the phone.
const longest = Duration(minutes: 5);

/// A voice note: records to `<support>/voice/<clientId>.wav` until the person saves or cancels it.
class VoiceRecorder {
  VoiceRecorder({required this.microphone, required this.folder, this.excludeFromBackup, DateTime Function()? clock,
    Timer Function(Duration, void Function())? timer})
    : _clock = clock ?? DateTime.now, _timer = timer ?? Timer.new;

  final Microphone microphone;
  /// The app's support folder.
  final Future<Directory> Function() folder;
  /// Keeps a kept recording out of iCloud backup, because a recording never leaves the phone. Android leaves `voice/`
  /// out by `res/xml/backup_rules.xml` and `data_extraction_rules.xml`.
  final Future<void> Function(File file)? excludeFromBackup;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _timer;

  String? _clientId;
  DateTime? _startedAt;
  Timer? _cap;
  StreamController<double>? _levels;
  StreamSubscription<double>? _heard;
  /// Called with the recording when it reaches [longest], as if the person let go; with null when the microphone did not
  /// stop, and nothing is kept.
  void Function(Recording? recording)? onLongest;

  bool get recording => _clientId != null;
  DateTime? get startedAt => _startedAt;
  /// The sound level while it records, only to draw; it ends when the recording does, and nothing keeps it.
  Stream<double>? get levels => _levels?.stream;

  /// The recording's file, from its [audioPath].
  Future<File> fileOf(String audioPath) async => File('${(await folder()).path}/$audioPath');

  static String pathOf(String clientId) => 'voice/$clientId.wav';

  /// Starts a recording for the note [clientId]. False when the person refused the microphone. Throws, recording
  /// nothing, when the microphone does not start; the next press can try again.
  Future<bool> start(String clientId) async {
    if (recording) return true;
    if (!await microphone.allow()) return false;
    final file = await fileOf(pathOf(clientId));
    await file.parent.create(recursive: true);
    final startedAt = _clock();
    try {
      await microphone.start(file.path);
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
    _clientId = clientId;
    _startedAt = startedAt;
    final levels = _levels = StreamController<double>.broadcast();
    // With no level from the microphone, the bars stay low and the recording goes on.
    _heard = microphone.levels().listen(levels.add, onError: (_) {});
    _cap = _timer(longest, () async {
      final Recording? done;
      try {
        done = await stop();
      } catch (_) {
        return onLongest?.call(null);
      }
      if (done != null) onLongest?.call(done);
    });
    return true;
  }

  /// Ends the recording. Null, with its file deleted, when it was shorter than [shortest] or none was running.
  Future<Recording?> stop() async {
    final clientId = _clientId, startedAt = _startedAt;
    if (clientId == null || startedAt == null) return null;
    _end();
    final length = _clock().difference(startedAt);
    if (length < shortest) {
      try {
        await microphone.cancel();
      } finally {
        await _delete(clientId);
      }
      return null;
    }
    try {
      await microphone.stop();
    } catch (_) {
      // A file the microphone did not end is not kept.
      await _delete(clientId);
      rethrow;
    }
    try {
      await excludeFromBackup?.call(await fileOf(pathOf(clientId)));
    } catch (_) {
      // The note is kept all the same; the mark is tried for each recording.
    }
    return Recording(clientId: clientId, audioPath: pathOf(clientId), startedAt: startedAt, length: length > longest ? longest : length);
  }

  /// Ends the recording and deletes it: the person slid off the button.
  Future<void> cancel() async {
    final clientId = _clientId;
    if (clientId == null) return;
    _end();
    try {
      await microphone.cancel();
    } finally {
      await _delete(clientId);
    }
  }

  void _end() {
    _cap?.cancel();
    _cap = null;
    unawaited(_heard?.cancel());
    unawaited(_levels?.close());
    _heard = null;
    _levels = null;
    _clientId = null;
    _startedAt = null;
  }

  Future<void> _delete(String clientId) async {
    final file = await fileOf(pathOf(clientId));
    if (await file.exists()) await file.delete();
  }
}

/// Reads the sound waves of the recording at [job]'s path in [job]'s number of bars, for `compute` to run away from the
/// page: empty when the file is gone or is not a 16-bit PCM WAV.
Future<List<double>> readWave((String path, int bars) job) async {
  final file = File(job.$1);
  if (!await file.exists()) return const [];
  return levelsOfWav(await file.readAsBytes(), bars: job.$2);
}
