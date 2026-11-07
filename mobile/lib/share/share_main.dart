import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../controller.dart';
import '../data/attachments.dart';
import '../data/connection.dart';
import '../sync/background.dart';
import '../sync/health.dart';
import '../sync/location.dart';
import 'draft.dart';
import 'share_card.dart';

/// The channel to `ShareActivity.kt`, which copies what Android shared into the app's cache before Dart starts.
const shareChannel = MethodChannel('relay/share');

/// How long *Save* waits for the note to go, while sending is on, before the card closes and the app sends the rest.
const shareWait = Duration(seconds: 20);

/// The Android share card's window: `ShareActivity.kt` starts this in its own engine, see-through over the app the
/// person shares from. It builds the app's own controller on the same store, so the note is kept and sent as a typed
/// note is, with no place.
@pragma('vm:entry-point')
Future<void> shareMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final relay = RelayController(store: openStore(), vault: KeyVault(), places: PhonePlaces(), health: PhoneHealth(),
    folder: getApplicationSupportDirectory);
  await relay.load(watch: false);
  final draft = await sharedDraft();
  runApp(MaterialApp(
    title: 'Relay Everything',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
    home: ShareCard(draft: draft, sending: relay.settings.sending,
      save: (words) => saveShare(relay, draft, words), close: () => unawaited(SystemNavigator.pop())),
  ));
}

/// What Android shared: `{text, subject, files: [{path, name, type, size}]}`. A file over 25 MB comes with its size and
/// no copy, so the card can name it.
Future<ShareDraft> sharedDraft({MethodChannel channel = shareChannel}) async {
  final Map<String, Object?> items;
  try {
    items = await channel.invokeMapMethod<String, Object?>('items') ?? const {};
  } on PlatformException {
    return ShareDraft.of();
  }
  final text = items['text'], subject = items['subject'];
  return ShareDraft.of(text: text is String ? text : null, subject: subject is String ? subject : null, files: [
    for (final file in (items['files'] as List?) ?? const [])
      if (file is Map && file['name'] is String)
        NewFile(path: file['path'] is String ? file['path'] as String : '', name: file['name'] as String,
          size: file['size'] is int ? file['size'] as int : 0, type: file['type'] is String ? file['type'] as String : null,
          move: true),
  ]);
}

/// Keeps the share as one note with no place. While sending is on, it waits up to [wait] for the note and its files
/// to go.
Future<ShareOutcome> saveShare(RelayController relay, ShareDraft draft, String words, {Duration wait = shareWait}) async {
  final kept = await relay.keepNote(draft.noteText(words), files: draft.files, pin: false);
  final note = kept.note;
  if (note == null || !relay.settings.sending) return ShareOutcome.kept;
  await relay.settled().timeout(wait, onTimeout: () {});
  final stored = (await relay.store.notes()).where((each) => each.clientId == note.clientId).firstOrNull;
  final sent = stored != null && stored.sentAt != null && stored.attachments.every((file) => file.sentAt != null);
  return sent ? ShareOutcome.sent : ShareOutcome.later;
}
