import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ArchiveException, BZip2Decoder, InputFileStream, InputStream;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Where the speech model is in its life on this phone.
///
/// `missing → asking → downloading → ready`, and `failed` when a download or its unpack stopped, or a file was wrong:
/// *Try again* starts it again, from where it stopped.
enum ModelState { missing, asking, downloading, ready, failed }

/// One file a speech model keeps on the phone: its name in the model's folder, its size and SHA-256, and what the
/// speech engine reads it as, such as `encoder`, `decoder`, `joiner` or `tokens`.
class SpeechModelFile {
  const SpeechModelFile(this.name, {required this.role, required this.bytes, required this.sha256});

  final String name;
  final String role;
  final int bytes;
  final String sha256;
}

/// A speech model the app can get: one item of [speechModels]. The phone downloads its archive once, checks it, and keeps
/// only its [files], each checked, in `speech-model/<id>/`. A later model is a new item, with no new download code.
class SpeechModelInfo {
  const SpeechModelInfo({required this.id, required this.name, required this.url, required this.sha256,
    required this.bytes, required this.folder, required this.kind, required this.files});

  /// Its name on the phone, such as `parakeet-small`: the folder it is kept in.
  final String id;
  /// Its name as the app shows it.
  final String name;
  /// The `.tar.bz2` archive the phone downloads.
  final String url;
  /// The archive's SHA-256. An archive with any other is deleted, never unpacked.
  final String sha256;
  /// The archive's size in bytes: what the ask says.
  final int bytes;
  /// The folder inside the archive that holds [files].
  final String folder;
  /// How sherpa-onnx loads it: its model type, such as `nemo_transducer`.
  final String kind;
  /// The files the phone keeps. The archive's other files, such as its test recordings, are skipped.
  final List<SpeechModelFile> files;

  Uri get uri => Uri.parse(url);

  /// What the phone keeps, in bytes: what Settings says and *Remove* frees.
  int get keptBytes => files.fold(0, (sum, file) => sum + file.bytes);
}

/// NVIDIA's Parakeet small (Parakeet TDT 110M, English), in the int8 build sherpa-onnx's makers keep in their GitHub
/// release. It writes punctuation and capitals. NVIDIA gives it under CC-BY-4.0.
const parakeetSmall = SpeechModelInfo(
  id: 'parakeet-small',
  name: 'Parakeet small',
  url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
    'sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8.tar.bz2',
  sha256: 'f628312e9fdf8686374cb01a69425c41732529d540860311f16f37cbc32cfe9b',
  bytes: 108035095,
  folder: 'sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8',
  kind: 'nemo_transducer',
  files: [
    SpeechModelFile('encoder.int8.onnx', role: 'encoder', bytes: 131113202,
      sha256: '0f35509ddeb9b39002fb077d979a9fe74f06eb0bc4dd5c34f512f82e5111d657'),
    SpeechModelFile('decoder.int8.onnx', role: 'decoder', bytes: 3955863,
      sha256: 'f7c331c5504c2e593c76ed22b728e3f554af6c4a383dde862e719ced08b1da19'),
    SpeechModelFile('joiner.int8.onnx', role: 'joiner', bytes: 1411403,
      sha256: 'bf7dff69e9f2cdbe9943d70da358f38b361c115ba0105bae7e908e0d6ec782f6'),
    SpeechModelFile('tokens.txt', role: 'tokens', bytes: 9953,
      sha256: '450e56bd2f036fe5b6aa821865838cc5aa9d8b0106134ce9a9ba0664abe6cd10'),
  ],
);

/// Every speech model the app knows. There is no choice on screen yet: the app uses [currentSpeechModel].
const speechModels = [parakeetSmall];

/// The model voice notes use.
const currentSpeechModel = parakeetSmall;

/// The size as the app says it.
String megabytes(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

const _files = MethodChannel('relay/files');

/// Marks [file], the model or a recording, so iCloud does not back it up: `AppDelegate.swift` sets
/// `NSURLIsExcludedFromBackupKey`. Android leaves both out by `res/xml/backup_rules.xml` and `data_extraction_rules.xml`.
Future<void> excludeFromBackup(File file) async {
  if (Platform.isIOS) await _files.invokeMethod<void>('excludeFromBackup', file.path);
}

/// Why getting the model failed: no connection or no space ([offline]), or a file that was not the model ([damaged]).
enum ModelProblem { offline, damaged }

/// The speech model on this phone. It is the one request the app may make with sending off, and only after the
/// person's *Get it*: it uses its own HTTP client, never the Relay sender, so it carries no device key.
///
/// In `speech-model/`, the archive downloads to `<id>.tar.bz2.part`, its files unpack to `<id>.part/`, and the rename
/// to `<id>/` is the only mark that the model is ready: a phone that stops halfway never uses half a model.
class SpeechModel extends ChangeNotifier {
  SpeechModel({required this.folder, http.Client Function()? client, this.excludeFromBackup,
    this.info = currentSpeechModel})
    : _client = client ?? http.Client.new;

  /// The app's support folder; the model goes in its `speech-model` folder.
  final Future<Directory> Function() folder;
  final http.Client Function() _client;
  /// Keeps the model out of the phone's backup, such as iCloud: it is large and can be got again.
  final Future<void> Function(File file)? excludeFromBackup;
  /// Which model this is.
  final SpeechModelInfo info;

  ModelState _state = ModelState.missing;
  double _progress = 0;
  ModelProblem? _problem;
  Future<bool>? _download;

  ModelState get state => _state;
  /// From 0 to 1 while getting it: to 0.9 for the download, and the last 0.1 for the unpack.
  double get progress => _progress;
  ModelProblem? get problem => _problem;

  Future<Directory> get _models async => Directory('${(await folder()).path}/speech-model');
  /// The folder that holds the model's files once it is ready.
  Future<Directory> get directory async => Directory('${(await _models).path}/${info.id}');
  Future<Directory> get _unpacking async => Directory('${(await _models).path}/${info.id}.part');
  Future<File> get _archive async => File('${(await _models).path}/${info.id}.tar.bz2.part');

  /// Deletes what an earlier model left, such as whisper.cpp's `ggml-base.en-q5_1.bin`, then reads whether the model is
  /// here. Its files were checked before the folder got its name, so no read of the whole model.
  Future<void> load() async {
    final models = await _models;
    if (await models.exists()) {
      final keep = {info.id, '${info.id}.part', '${info.id}.tar.bz2.part'};
      await for (final entry in models.list(followLinks: false)) {
        if (keep.contains(entry.uri.pathSegments.lastWhere((part) => part.isNotEmpty))) continue;
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {
          // Gone already, or held: the next open tries again.
        }
      }
    }
    _set(await (await directory).exists() ? ModelState.ready : ModelState.missing);
  }

  /// The app asks the person: *Get the speech model?*
  void ask() {
    if (_state == ModelState.missing || _state == ModelState.failed) _set(ModelState.asking);
  }

  /// *Not now*: nothing is got.
  void notNow() {
    if (_state == ModelState.asking) _set(ModelState.missing);
  }

  /// *Get it* or *Try again*. Resumes a stopped download through its `.part` file, unpacks the archive only when its
  /// SHA-256 matches, and names the folder only when each kept file's SHA-256 matches. True when the model is ready.
  Future<bool> download() => _download ??= _get().whenComplete(() => _download = null);

  Future<bool> _get() async {
    if (_state == ModelState.ready) return true;
    _problem = null;
    _set(ModelState.downloading);
    final part = await _archive;
    await part.parent.create(recursive: true);
    final bytes = info.bytes;
    final url = info.uri;
    final client = _client();
    try {
      var have = await part.exists() ? await part.length() : 0;
      _progress = _downloaded(have);
      notifyListeners();
      final request = http.Request('GET', url);
      if (have > 0) request.headers['Range'] = 'bytes=$have-';
      final response = await client.send(request);
      if (response.statusCode == 416 && have >= bytes) {
        // The whole archive came before the app closed: only its check and unpack are left.
        await response.stream.drain<void>();
      } else if (response.statusCode == 200 || response.statusCode == 206) {
        // A server that does not resume sends the whole archive again.
        if (response.statusCode == 200) have = 0;
        final sink = part.openWrite(mode: have == 0 ? FileMode.write : FileMode.append);
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            have += chunk.length;
            _progress = _downloaded(have);
            notifyListeners();
          }
        } finally {
          await sink.close();
        }
      } else {
        await response.stream.drain<void>();
        throw http.ClientException('The model download answered ${response.statusCode}', url);
      }
      if (await _sha256Of(part.path) != info.sha256) {
        await part.delete();
        return _fail(ModelProblem.damaged);
      }
      _progress = _downloadShare;
      notifyListeners();
      final unpacking = await _unpacking;
      final result = await unpackInBackground(info, archive: part.path, into: unpacking.path, onProgress: (done) {
        _progress = _downloadShare + (1 - _downloadShare) * done;
        notifyListeners();
      });
      if (result != UnpackResult.done) {
        if (await unpacking.exists()) await unpacking.delete(recursive: true);
        if (result == UnpackResult.damaged) {
          // An archive whose checksum matched but whose files do not: get it again, never use it.
          if (await part.exists()) await part.delete();
          return _fail(ModelProblem.damaged);
        }
        // Such as a phone with no space left: the archive stays, and *Try again* unpacks it again.
        return _fail(ModelProblem.offline);
      }
      await part.delete();
      final ready = await unpacking.rename((await directory).path);
      for (final file in info.files) {
        try {
          await excludeFromBackup?.call(File('${ready.path}/${file.name}'));
        } on Exception {
          // A phone that can not mark it still uses it.
        }
      }
      _progress = 1;
      _set(ModelState.ready);
      return true;
    } on Exception {
      // The .part file stays, so *Try again* goes on from where it stopped.
      return _fail(ModelProblem.offline);
    } finally {
      client.close();
    }
  }

  double _downloaded(int have) => (have / info.bytes).clamp(0, 1).toDouble() * _downloadShare;

  bool _fail(ModelProblem problem) {
    _problem = problem;
    _set(ModelState.failed);
    return false;
  }

  /// Deletes the model and any part of it, to free space. The next voice note asks to get it again.
  Future<void> remove() async {
    await _download;
    for (final folder in [await directory, await _unpacking]) {
      if (await folder.exists()) await folder.delete(recursive: true);
    }
    final archive = await _archive;
    if (await archive.exists()) await archive.delete();
    _progress = 0;
    _problem = null;
    _set(ModelState.missing);
  }

  void _set(ModelState state) {
    _state = state;
    notifyListeners();
  }
}

/// The SHA-256 of the file at [path], read in a background isolate. It is top-level, so its closure holds only [path]:
/// a closure in a method can hold `this`, which can not go to an isolate.
Future<String> _sha256Of(String path) =>
  Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());

/// The share of [SpeechModel.progress] the download takes; the unpack takes the rest.
const _downloadShare = 0.9;

/// How an unpack ended: [done], an archive that does not hold the model's files as listed ([damaged]), or a write that
/// failed, such as for space ([failed]).
enum UnpackResult { done, damaged, failed }

/// Unpacks [model]'s files from the checked `.tar.bz2` at [archive] into the folder [into], in a background isolate,
/// so the timeline never stops. [onProgress] gets how much of the archive is read, from 0 to 1.
Future<UnpackResult> unpackInBackground(SpeechModelInfo model, {required String archive, required String into,
    void Function(double done)? onProgress}) async {
  final port = ReceivePort();
  try {
    await Isolate.spawn(_unpackJob, (port.sendPort, model, archive, into), onExit: port.sendPort,
      onError: port.sendPort, debugName: 'speech-model-unpack');
    await for (final message in port) {
      if (message is double) {
        onProgress?.call(message);
      } else if (message is int) {
        return UnpackResult.values[message];
      } else {
        // The isolate stopped with an error, or with no answer.
        return UnpackResult.failed;
      }
    }
    return UnpackResult.failed;
  } finally {
    port.close();
  }
}

void _unpackJob((SendPort, SpeechModelInfo, String, String) job) {
  final (port, model, archive, into) = job;
  UnpackResult result;
  try {
    result = unpackModel(model, archive: archive, into: into, onProgress: port.send);
  } on ArchiveException {
    result = UnpackResult.damaged;
  } on Object {
    result = UnpackResult.failed;
  }
  port.send(result.index);
}

/// Reads the `.tar.bz2` at [archive] once, front to back, and writes only [model]'s files into [into], each checked
/// against its size and SHA-256. The tar stays in memory a window at a time, never on disk. It runs in the isolate that
/// calls it: the app calls it through [unpackInBackground].
@visibleForTesting
UnpackResult unpackModel(SpeechModelInfo model, {required String archive, required String into,
    void Function(double done)? onProgress}) {
  final folder = Directory(into);
  if (folder.existsSync()) folder.deleteSync(recursive: true);
  folder.createSync(recursive: true);
  final wanted = {for (final file in model.files) '${model.folder}/${file.name}': file};
  final written = <String>{};
  final input = InputFileStream(archive);
  try {
    final total = input.length;
    var told = -1;
    void tell() {
      final done = total == 0 ? 1.0 : input.position / total;
      final percent = (done * 100).floor();
      if (percent != told) {
        told = percent;
        onProgress?.call(done.clamp(0, 1).toDouble());
      }
    }

    final tar = BZip2Decoder().decodeLazy(input, verify: true);
    for (final entry in tarEntries(tar)) {
      final file = entry.type == _regular ? wanted[entry.name] : null;
      if (file == null || written.contains(file.name)) {
        entry.skip();
        tell();
        continue;
      }
      if (entry.size != file.bytes) return UnpackResult.damaged;
      final digest = _Digest();
      final hash = sha256.startChunkedConversion(digest);
      final out = File('${folder.path}/${file.name}').openSync(mode: FileMode.write);
      try {
        entry.read((chunk) {
          hash.add(chunk);
          out.writeFromSync(chunk);
          tell();
        });
      } finally {
        out.closeSync();
      }
      hash.close();
      if (digest.value.toString() != file.sha256) return UnpackResult.damaged;
      written.add(file.name);
      if (written.length == wanted.length) break;
    }
  } finally {
    input.closeSync();
  }
  return written.length == wanted.length ? UnpackResult.done : UnpackResult.damaged;
}

class _Digest implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

const _regular = 0x30; // '0'

/// One entry of a tar: its name with any leading `./`, its size and its type flag, and a way to read or skip its body.
/// The body must be read or skipped before the next entry.
class TarEntry {
  TarEntry._(this.name, this.size, this.type, this._input);

  final String name;
  final int size;
  final int type;
  final InputStream _input;

  /// Gives the body to [chunk] a part at a time, then moves past its padding.
  void read(void Function(Uint8List chunk) chunk) {
    var left = size;
    while (left > 0) {
      final part = _input.readBytes(left < _chunk ? left : _chunk).toUint8List();
      if (part.isEmpty) throw ArchiveException('The tar ended inside $name');
      chunk(part);
      left -= part.length;
    }
    _pad();
  }

  /// Moves past the body and its padding.
  void skip() => read((_) {});

  void _pad() {
    final pad = (512 - size % 512) % 512;
    if (pad > 0) _input.readBytes(pad).toUint8List();
  }
}

const _chunk = 1 << 20;

/// The entries of the tar read from [input], in order, with GNU long names and pax `path` records applied.
Iterable<TarEntry> tarEntries(InputStream input) sync* {
  String? longName;
  while (!input.isEOS) {
    final header = input.readBytes(512).toUint8List();
    if (header.length < 512 || header.every((byte) => byte == 0)) return;
    if (!_checksumMatches(header)) throw ArchiveException('A tar header is damaged');
    var name = _text(header, 0, 100);
    final ustar = _text(header, 257, 6).startsWith('ustar');
    final prefix = ustar ? _text(header, 345, 155) : '';
    if (prefix.isNotEmpty) name = '$prefix/$name';
    final size = _octal(header, 124, 12);
    final type = header[156];
    final entry = TarEntry._(_clean(longName ?? name), size, type == 0 ? _regular : type, input);
    if (type == 0x4c /* L: GNU long name */ || type == 0x78 /* x: pax */) {
      final body = BytesBuilder(copy: false);
      entry.read(body.add);
      final bytes = body.takeBytes();
      longName = type == 0x4c ? _text(bytes, 0, bytes.length) : (_paxPath(bytes) ?? longName);
      continue;
    }
    longName = null;
    yield entry;
  }
}

String _text(Uint8List bytes, int from, int length) {
  var end = from;
  final stop = (from + length).clamp(0, bytes.length);
  while (end < stop && bytes[end] != 0) {
    end++;
  }
  return utf8.decode(bytes.sublist(from, end), allowMalformed: true);
}

int _octal(Uint8List bytes, int from, int length) {
  final text = _text(bytes, from, length).trim();
  if (text.isEmpty) return 0;
  final value = int.tryParse(text, radix: 8);
  if (value == null) throw ArchiveException('A tar size is not a number');
  return value;
}

bool _checksumMatches(Uint8List header) {
  var sum = 0;
  for (var i = 0; i < 512; i++) {
    sum += i >= 148 && i < 156 ? 0x20 : header[i];
  }
  return _octal(header, 148, 8) == sum;
}

String? _paxPath(Uint8List bytes) {
  for (final record in utf8.decode(bytes, allowMalformed: true).split('\n')) {
    final at = record.indexOf(' path=');
    if (at >= 0) return record.substring(at + ' path='.length);
  }
  return null;
}

String _clean(String name) {
  var clean = name;
  while (clean.startsWith('./')) {
    clean = clean.substring(2);
  }
  return clean.endsWith('/') ? clean.substring(0, clean.length - 1) : clean;
}
