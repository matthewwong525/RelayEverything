import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Where the speech model is in its life on this phone.
///
/// `missing → asking → downloading → ready`, and `failed` when a download stopped or its file was wrong: *Try again*
/// starts it again, from where it stopped.
enum ModelState { missing, asking, downloading, ready, failed }

/// whisper.cpp's English-only base model, quantized: the smallest that writes everyday speech well.
const modelName = 'ggml-base.en-q5_1.bin';

/// The model at one fixed revision of whisper.cpp's Hugging Face page, so the file at this address never changes.
final modelUrl = Uri.parse(
  'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/$modelName');

/// The model's SHA-256. A file with any other is deleted, never used.
const modelSha256 = '4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f';

/// The model's size in bytes: 57 MB.
const modelSize = 59721011;

/// The size as the app says it.
String megabytes(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

const _files = MethodChannel('relay/files');

/// Marks [file], the model or a recording, so iCloud does not back it up: `AppDelegate.swift` sets
/// `NSURLIsExcludedFromBackupKey`. Android leaves both out by `res/xml/backup_rules.xml` and `data_extraction_rules.xml`.
Future<void> excludeFromBackup(File file) async {
  if (Platform.isIOS) await _files.invokeMethod<void>('excludeFromBackup', file.path);
}

/// Why a download failed: no connection, or a file that was not the model.
enum ModelProblem { offline, damaged }

/// The speech model on this phone. It is the one request the app may make with sending off, and only after the
/// person's *Get it*: it uses its own HTTP client, never the Relay sender, so it carries no device key.
class SpeechModel extends ChangeNotifier {
  SpeechModel({required this.folder, http.Client Function()? client, this.excludeFromBackup, Uri? url, String? sha256,
    int? bytes})
    : _client = client ?? http.Client.new, url = url ?? modelUrl, sha256Hex = sha256 ?? modelSha256,
      bytes = bytes ?? modelSize;

  /// The app's support folder; the model goes in its `speech-model` folder.
  final Future<Directory> Function() folder;
  final http.Client Function() _client;
  /// Keeps the model out of the phone's backup, such as iCloud: it is large and can be got again.
  final Future<void> Function(File file)? excludeFromBackup;
  final Uri url;
  final String sha256Hex;
  final int bytes;

  ModelState _state = ModelState.missing;
  double _progress = 0;
  ModelProblem? _problem;
  Future<bool>? _download;

  ModelState get state => _state;
  /// From 0 to 1 while downloading.
  double get progress => _progress;
  ModelProblem? get problem => _problem;

  Future<File> get file async => File('${(await folder()).path}/speech-model/$modelName');
  Future<File> get _part async => File('${(await file).path}.part');

  /// Reads whether the model is here. Its checksum was checked before it got its name, so no read of the whole file.
  Future<void> load() async {
    _set(await (await file).exists() ? ModelState.ready : ModelState.missing);
  }

  /// The app asks the person: *Get the speech model?*
  void ask() {
    if (_state == ModelState.missing || _state == ModelState.failed) _set(ModelState.asking);
  }

  /// *Not now*: nothing is got.
  void notNow() {
    if (_state == ModelState.asking) _set(ModelState.missing);
  }

  /// *Get it* or *Try again*. Resumes a stopped download through its `.part` file, and names the file only when its
  /// SHA-256 matches. True when the model is ready.
  Future<bool> download() => _download ??= _get().whenComplete(() => _download = null);

  Future<bool> _get() async {
    if (_state == ModelState.ready) return true;
    _problem = null;
    _set(ModelState.downloading);
    final part = await _part;
    await part.parent.create(recursive: true);
    final client = _client();
    try {
      var have = await part.exists() ? await part.length() : 0;
      _progress = have / bytes;
      notifyListeners();
      final request = http.Request('GET', url);
      if (have > 0) request.headers['Range'] = 'bytes=$have-';
      final response = await client.send(request);
      if (response.statusCode == 416 && have >= bytes) {
        // The whole file came before the app closed: only its check is left.
        await response.stream.drain<void>();
      } else if (response.statusCode == 200 || response.statusCode == 206) {
        // A server that does not resume sends the whole file again.
        if (response.statusCode == 200) have = 0;
        final sink = part.openWrite(mode: have == 0 ? FileMode.write : FileMode.append);
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            have += chunk.length;
            _progress = (have / bytes).clamp(0, 1).toDouble();
            notifyListeners();
          }
        } finally {
          await sink.close();
        }
      } else {
        await response.stream.drain<void>();
        throw http.ClientException('The model download answered ${response.statusCode}', url);
      }
      final path = part.path;
      final sum = await Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());
      if (sum != sha256Hex) {
        await part.delete();
        return _fail(ModelProblem.damaged);
      }
      final done = await part.rename((await file).path);
      try {
        await excludeFromBackup?.call(done);
      } on Exception {
        // A phone that can not mark it still uses it.
      }
      _set(ModelState.ready);
      return true;
    } on Exception {
      // The .part file stays, so *Try again* goes on from where it stopped.
      return _fail(ModelProblem.offline);
    } finally {
      client.close();
    }
  }

  bool _fail(ModelProblem problem) {
    _problem = problem;
    _set(ModelState.failed);
    return false;
  }

  /// Deletes the model and any part of it, to free space. The next voice note asks to get it again.
  Future<void> remove() async {
    await _download;
    for (final f in [await file, await _part]) {
      if (await f.exists()) await f.delete();
    }
    _progress = 0;
    _problem = null;
    _set(ModelState.missing);
  }

  void _set(ModelState state) {
    _state = state;
    notifyListeners();
  }
}
