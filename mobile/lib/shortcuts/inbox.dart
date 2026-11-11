import 'dart:convert';
import 'dart:io';

import '../data/attachments.dart';

/// The folder, in the app's support folder, where *Add a note* leaves a note the app did not answer in time, and the
/// Apple Watch each voice note. `ios/Runner/ShortcutsInbox.swift` writes `<id>.json` for each, `<id>/` for its files.
const inboxFolder = 'shortcuts-inbox';

/// One note a shortcut left in the inbox.
class InboxRequest {
  const InboxRequest({required this.id, required this.text, required this.createdAt, required this.files, this.recording,
    this.fromWatch = false});

  /// The note's id, the same one the shortcut gave the app: a note the app kept already is not kept twice.
  final String? id;
  final String text;
  final DateTime createdAt;
  final List<NewFile> files;

  /// A lone recording Swift made into a voice note's WAV, or null.
  final ShortcutRecording? recording;

  /// True for a voice note the Apple Watch handed over: Swift writes `"from": "watch"`.
  final bool fromWatch;
}

/// A recording a shortcut gave as its only file: Swift writes it as a 16 kHz mono WAV at
/// `shortcuts-inbox/<id>/voice.wav`, and the app moves it to where a voice note keeps its recording once the note is kept.
class ShortcutRecording {
  const ShortcutRecording({required this.path, required this.durationMs});

  /// From the app's support folder.
  final String path;
  final int durationMs;
}

final _recordingPath = RegExp('^$inboxFolder/[0-9a-f]{32}/voice\\.wav\$');

/// The recording in a request's `recording`, `{path, durationMs}`, or null when there is none or its path is not one
/// Swift writes. A request with files too keeps them as files: Swift makes a recording only of a lone file.
ShortcutRecording? shortcutRecording(Object? recording, Object? files) {
  if (recording is! Map || (files is List && files.isNotEmpty)) return null;
  final path = recording['path'], length = recording['durationMs'];
  if (path is! String || !_recordingPath.hasMatch(path)) return null;
  return ShortcutRecording(path: path, durationMs: length is int && length > 0 ? length : 0);
}

/// A note id the server takes: 32 lowercase hex characters.
final noteId = RegExp(r'^[0-9a-f]{32}$');

/// The files a shortcut gave, each the app's own copy, by a path full or from [root].
List<NewFile> shortcutFiles(Object? files, String root) => [
  for (final file in (files as List?) ?? const [])
    if (file is Map && file['path'] is String)
      _fileOf(file['path'] as String, file['name'] is String ? file['name'] as String : null,
        file['type'] is String ? file['type'] as String : null, root),
];

NewFile _fileOf(String path, String? name, String? type, String root) {
  final full = path.startsWith('/') ? path : '$root/$path';
  final found = File(full);
  return NewFile(path: full, name: name == null || name.isEmpty ? found.uri.pathSegments.last : name,
    size: found.existsSync() ? found.lengthSync() : 0, type: type, move: true);
}

/// Keeps each note left in the inbox, oldest first, through [keep], then deletes it and what is left of its files.
/// A note is taken by renaming it first, so two engines that drain at once keep it once. A note that can not be read
/// is deleted.
Future<void> drainInbox(Directory root, Future<void> Function(InboxRequest request) keep) async {
  final inbox = Directory('${root.path}/$inboxFolder');
  if (!await inbox.exists()) return;
  final waiting = [
    await for (final entry in inbox.list()) if (entry is File && entry.path.endsWith('.json')) entry,
  ]..sort((a, b) => a.path.compareTo(b.path));
  for (final file in waiting) {
    final File taken;
    try {
      taken = await file.rename('${file.path}.taking-$pid');
    } on FileSystemException {
      continue;
    }
    final name = file.uri.pathSegments.last;
    final files = Directory('${inbox.path}/${name.substring(0, name.length - '.json'.length)}');
    final request = _requestOf(await taken.readAsString(), root.path);
    // A note that can not be read is not a note: it goes.
    if (request != null) {
      try {
        await keep(request);
      } on Exception {
        // Kept for the next open, such as when the store was busy.
        await taken.rename(file.path);
        continue;
      }
    }
    await taken.delete();
    if (await files.exists()) await files.delete(recursive: true);
  }
}

InboxRequest? _requestOf(String text, String root) {
  final Object? body;
  try {
    body = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (body is! Map) return null;
  final id = body['id'], words = body['text'], at = body['createdAt'];
  return InboxRequest(id: id is String && noteId.hasMatch(id) ? id : null, text: words is String ? words : '',
    createdAt: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : DateTime.now(), files: shortcutFiles(body['files'], root),
    recording: shortcutRecording(body['recording'], body['files']), fromWatch: body['from'] == 'watch');
}
