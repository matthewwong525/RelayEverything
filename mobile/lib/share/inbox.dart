import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../data/attachments.dart';
import '../data/store.dart';
import '../shortcuts/inbox.dart' show noteId;

/// The folder in the App Group where the iPhone's share card leaves each note: `share-inbox/<clientId>/note.json` and
/// its files. `ios/ShareExtension/ShareInbox.swift` writes it in `.tmp-<clientId>/` and renames it when whole.
const shareInboxFolder = 'share-inbox';

/// The App Group the iPhone app shares with its share card, through Swift on `relay/files`. Android has none.
abstract class ShareGroup {
  /// Tells the share card whether it may send: true only while sending to the server is on and the phone has a key.
  /// The key itself never goes here: the card reads it from the shared Keychain group. [later] is true while the phone
  /// sends to the person's own webhook: the card only keeps each share, and says the app sends it.
  Future<void> setSending(bool on, {bool later = false});

  /// The App Group's folder, or null when this build has none.
  Future<Directory?> folder();
}

class PhoneShareGroup implements ShareGroup {
  static const _channel = MethodChannel('relay/files');

  @override
  Future<void> setSending(bool on, {bool later = false}) =>
    _channel.invokeMethod<void>('setShareSettings', {'sending': on, 'later': later});

  @override
  Future<Directory?> folder() async {
    final path = await _channel.invokeMethod<String>('appGroupPath');
    return path == null ? null : Directory(path);
  }
}

/// One file of a shared note, as the share card wrote it.
class SharedFile {
  const SharedFile({required this.id, required this.name, required this.type, required this.size, required this.path});

  final String id;
  final String name;
  final String type;
  final int size;
  /// The card's copy, in the share inbox.
  final String path;
}

/// One note the share card left, and what of it the card sent already.
class SharedNote {
  const SharedNote({required this.clientId, required this.text, required this.createdAt, required this.files,
    this.sentNote = false, this.sentFiles = const {}});

  final String clientId;
  final String text;
  final DateTime createdAt;
  final List<SharedFile> files;
  final bool sentNote;
  final Set<String> sentFiles;

  /// Reads a `note.json` in [folder], or null when it is not one.
  static SharedNote? parse(String json, String folder) {
    final Object? body;
    try {
      body = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (body is! Map || body['v'] != 1) return null;
    final id = body['clientId'], text = body['text'], at = body['createdAt'], files = body['files'] ?? const [];
    if (id is! String || !noteId.hasMatch(id) || text is! String || at is! int || files is! List) return null;
    final shared = <SharedFile>[];
    for (final file in files) {
      if (file is! Map) return null;
      final fileId = file['id'], name = file['name'], type = file['type'], size = file['size'], stored = file['file'];
      if (fileId is! String || !noteId.hasMatch(fileId) || name is! String || stored is! String || stored.contains('/')) {
        return null;
      }
      shared.add(SharedFile(id: fileId, name: name, type: type is String && type.isNotEmpty ? type : typeOf(name),
        size: size is int ? size : 0, path: '$folder/$stored'));
    }
    final sent = body['sentFiles'];
    return SharedNote(clientId: id, text: text, createdAt: DateTime.fromMillisecondsSinceEpoch(at), files: shared,
      sentNote: body['sentNote'] == true, sentFiles: {if (sent is List) for (final file in sent) if (file is String) file});
  }
}

/// How long a taken entry waits before another drain takes it over, as when the app closed half way through one.
const _abandoned = Duration(minutes: 10);

/// A taken entry: `.taking-<clientId>-<ms>`, with the time of the take in its name. A rename keeps the folder's own
/// modified time, so a share made 15 minutes ago and taken now would look abandoned by that time.
final _taking = RegExp(r'^\.taking-([0-9a-f]{32})-(\d+)$');

/// Keeps each note the share card left in [group], oldest first, then deletes it. Its files move into `attachments/`
/// under [root], the app's support folder, with the ids the card gave them. The note gets no place. What the card sent
/// is marked sent; with [send], the rest is queued. An entry that can not be read moves to `share-inbox/.bad/`, so a
/// bug never loses a share. Returns how many notes it kept.
Future<int> drainShareInbox(Directory group, String root, Store store, {required bool send, DateTime Function()? clock}) async {
  final inbox = Directory('${group.path}/$shareInboxFolder');
  if (!await inbox.exists()) return 0;
  final now = clock ?? DateTime.now;
  final waiting = <Directory>[];
  await for (final entry in inbox.list()) {
    if (entry is! Directory) continue;
    final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (name.startsWith('.taking-')) {
      final taking = _taking.firstMatch(name);
      final takenAt = taking == null ? (await entry.stat()).modified
        : DateTime.fromMillisecondsSinceEpoch(int.parse(taking.group(2)!));
      if (now().difference(takenAt) > _abandoned) waiting.add(entry);
    } else if (name.startsWith('.tmp-')) {
      // A card the system closed before Save left its copies: they go after a day.
      if (now().difference((await entry.stat()).modified) > const Duration(days: 1)) await entry.delete(recursive: true);
    } else if (!name.startsWith('.')) {
      waiting.add(entry);
    }
  }
  waiting.sort((a, b) => a.path.compareTo(b.path));
  var kept = 0;
  for (final entry in waiting) {
    final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
    final id = name.startsWith('.taking-') ? _taking.firstMatch(name)?.group(1) ?? name.substring('.taking-'.length) : name;
    // Taken by a rename first, so two engines that drain at once keep it once. The new name holds the time of this
    // take, so a second drain leaves it alone for 10 minutes; an abandoned take is renamed again, so only one takes it.
    final Directory taken;
    try {
      taken = await entry.rename('${inbox.path}/.taking-$id-${now().millisecondsSinceEpoch}');
    } on FileSystemException {
      continue;
    }
    final note = File('${taken.path}/note.json');
    final shared = await note.exists() ? SharedNote.parse(await note.readAsString(), taken.path) : null;
    if (shared == null || shared.clientId != id) {
      final bad = Directory('${inbox.path}/.bad');
      await bad.create(recursive: true);
      await taken.rename('${bad.path}/$id-${now().millisecondsSinceEpoch}');
      continue;
    }
    if (await keepShared(shared, root, store, send: send, now: now())) kept++;
    await taken.delete(recursive: true);
  }
  return kept;
}

/// Keeps one shared note in [store], with its files moved under [root]. False when this phone has it already, such as
/// after an earlier drain the app's close cut short.
Future<bool> keepShared(SharedNote shared, String root, Store store, {required bool send, required DateTime now}) async {
  if (await store.hasNote(shared.clientId)) return false;
  final attachments = <Attachment>[];
  final sentFiles = <String>{};
  for (final file in shared.files) {
    final kept = await keepFile(root, NewFile(path: file.path, name: file.name, size: file.size, type: file.type, move: true),
      file.id);
    if (kept == null) continue;
    attachments.add(kept);
    if (shared.sentFiles.contains(file.id)) sentFiles.add(file.id);
  }
  final note = LocalNote(clientId: shared.clientId, text: shared.text.trim(), createdAt: shared.createdAt,
    attachments: attachments);
  if (note.text.isEmpty && attachments.isEmpty) return false;
  return store.addSharedNote(note, sentAt: shared.sentNote ? now : null, sentFiles: sentFiles, send: send);
}
