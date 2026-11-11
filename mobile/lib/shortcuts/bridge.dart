import 'dart:async';

import 'package:flutter/services.dart';

import '../controller.dart';
import '../data/store.dart';
import 'inbox.dart';

/// The channel between Apple Shortcuts' actions in `ios/Runner/RelayIntents.swift` and the app's own Dart code.
const shortcutsChannel = MethodChannel('relay/shortcuts');

/// How long *Add a note* waits for its note to go, while sending is on, before it answers. The Swift side gives up at
/// 20 seconds, so this stays well under it.
const sendWait = Duration(seconds: 12);

/// Answers the Shortcuts actions with the app's own controller, so a shortcut's note is saved, pinned and sent as a
/// typed note is: `add` keeps a note, `get` reads notes from this phone and sends nothing, `inboxChanged` keeps what
/// waits in the inbox and answers once its words are settled, and `startVoiceNote` opens the recording sheet in the
/// app's own engine.
class ShortcutsBridge {
  ShortcutsBridge(this.relay, {this.onVoice, this.wait = sendWait});

  final RelayController relay;
  /// Opens the recording sheet; only the app's own engine has one.
  final void Function()? onVoice;
  final Duration wait;

  Future<Object?> handle(MethodCall call) async {
    final arguments = call.arguments is Map ? Map<String, dynamic>.from(call.arguments as Map) : <String, dynamic>{};
    switch (call.method) {
      case 'add':
        return add(arguments);
      case 'get':
        return get(arguments);
      case 'inboxChanged':
        // The Apple Watch left a voice note in the inbox while the app runs (ios/Runner/RelayWatchReceiver.swift). The
        // answer waits until its words are written and sent: Swift holds iOS's background time until it comes.
        await relay.drainShortcutsInbox();
        await relay.wordsSettled();
        return null;
      case 'startVoiceNote':
        final open = onVoice;
        if (open == null) throw MissingPluginException();
        open();
        return null;
      default:
        throw MissingPluginException();
    }
  }

  /// `{id, text, createdAt, files: [{path, name, type}], recording: {path, durationMs}}` → the kept note, with `message`
  /// when a file was left out. A `recording` makes a voice note, its words written after the typed ones. Nothing to keep
  /// fails with the words to show.
  Future<Map<String, Object?>> add(Map<String, dynamic> arguments) async {
    final id = arguments['id'], text = arguments['text'], at = arguments['createdAt'];
    final words = text is String ? text : '';
    final clientId = id is String && noteId.hasMatch(id) ? id : null;
    final createdAt = at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null;
    final recording = shortcutRecording(arguments['recording'], arguments['files']);
    final kept = recording == null
      ? await relay.keepNote(words, files: shortcutFiles(arguments['files'], relay.filesRoot ?? ''), clientId: clientId,
          createdAt: createdAt)
      : await relay.keepRecording(words, recording: recording.path, durationMs: recording.durationMs, clientId: clientId,
          createdAt: createdAt);
    final note = kept.note;
    if (note == null) throw PlatformException(code: 'empty', message: kept.problem);
    // The note goes now while sending is on, before iOS puts the app away; it stays waiting if that takes longer.
    await relay.settled().timeout(wait, onTimeout: () {});
    return {...noteMap(note), if (kept.problem != null) 'message': kept.problem};
  }

  /// `{limit, query, since}` → this phone's notes, newest first: at most [limit], holding [query], made at or after
  /// [since]. It reads only the phone.
  Future<List<Map<String, Object?>>> get(Map<String, dynamic> arguments) async {
    final limit = arguments['limit'] is int ? (arguments['limit'] as int).clamp(1, 1000) : 10;
    final query = arguments['query'] is String ? (arguments['query'] as String).trim().toLowerCase() : '';
    final since = arguments['since'] is int ? DateTime.fromMillisecondsSinceEpoch(arguments['since'] as int) : null;
    return [
      for (final note in await relay.store.notes())
        if ((since == null || !note.createdAt.isBefore(since)) && (query.isEmpty || note.text.toLowerCase().contains(query)))
          noteMap(note),
    ].take(limit).toList();
  }

  /// A note as Swift reads it into `RelayNoteEntity`.
  Map<String, Object?> noteMap(LocalNote note) => {
    'id': note.clientId,
    'text': note.text,
    'createdAt': note.createdAt.millisecondsSinceEpoch,
    'kind': note.kind.name,
    'files': [
      for (final file in note.attachments) {'path': relay.fullPath(file.path), 'name': file.name, 'type': file.type},
    ],
  };
}

/// Answers Shortcuts on [channel], then tells Swift this engine is ready, so a request that waited goes now.
Future<void> listenForShortcuts(ShortcutsBridge bridge, {MethodChannel channel = shortcutsChannel}) async {
  channel.setMethodCallHandler(bridge.handle);
  try {
    await channel.invokeMethod<void>('ready');
  } on MissingPluginException {
    // Android, and iPhones before iOS 16, have no Shortcuts actions.
  } on PlatformException {
    // As above.
  }
}
