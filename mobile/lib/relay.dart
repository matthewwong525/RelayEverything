import 'package:flutter/foundation.dart';

import 'data/settings.dart';

export 'data/settings.dart' show Settings;

/// One row of the timeline: a note typed on this phone, or one the server has.
class Entry {
  const Entry({required this.text, required this.ring, required this.at, this.place, this.device, this.waiting = false, this.audio = false});

  final String text;
  final bool ring;
  final DateTime at;
  final String? place;
  final String? device;
  final bool waiting;
  final bool audio;
}

enum SyncStatus { idle, syncing, synced, offline, refused }

/// What the screens read and do. The app's controller is one; a test's fake is another.
abstract class Relay extends ChangeNotifier {
  bool get connected;
  String? get server;
  List<Entry> get entries;
  bool get hasMore;
  SyncStatus get status;
  int get waiting;
  Settings get settings;

  /// Each returns null on success, or the words to show when it failed.
  Future<String?> connect(String code);
  Future<String?> setServer(String server);
  Future<String?> setPinNotes(bool on);
  Future<String?> setHistory(bool on);
  Future<String?> setHealth(bool on);

  /// How many notes never went to the server: the earlier-notes prompt asks about them when sending turns on.
  Future<int> earlierNotes();
  /// Turns sending on, with a key already kept; [sendEarlier] queues the earlier notes too, oldest first.
  Future<String?> startSending({required bool sendEarlier});
  /// Turns sending off: stops health and location history and drops what of them did not go. Keeps notes and the key.
  Future<void> stopSending();

  /// Forgets the key and turns sending off.
  Future<void> disconnect();
  Future<void> sync();
  Future<void> more();
  Future<void> addNote(String text);
}
