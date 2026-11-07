import 'dart:convert';
import 'dart:io';

import '../data/attachments.dart';

/// The folder, in the app's support folder, where *Add a note* leaves a note when the app does not answer in time.
/// `ios/Runner/RelayIntents.swift` writes it: `<id>.json` for each note, and `<id>/` for its files.
const inboxFolder = 'shortcuts-inbox';

/// One note a shortcut left in the inbox.
class InboxRequest {
  const InboxRequest({required this.id, required this.text, required this.createdAt, required this.files});

  /// The note's id, the same one the shortcut gave the app: a note the app kept already is not kept twice.
  final String? id;
  final String text;
  final DateTime createdAt;
  final List<NewFile> files;
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
    createdAt: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : DateTime.now(), files: shortcutFiles(body['files'], root));
}
