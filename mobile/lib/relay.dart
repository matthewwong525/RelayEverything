import 'package:flutter/foundation.dart';

import 'dart:async';

import 'data/settings.dart';
import 'voice/model.dart';

export 'data/settings.dart' show Settings;
export 'voice/model.dart' show ModelState, ModelProblem;

/// One row of the timeline: a note typed or said on this phone, or one the server has.
class Entry {
  const Entry({required this.text, required this.ring, required this.at, this.place, this.device, this.waiting = false, this.audio = false,
    this.voice = false, this.writing = false, this.recording, this.length});

  final String text;
  final bool ring;
  final DateTime at;
  final String? place;
  final String? device;
  final bool waiting;
  final bool audio;

  /// Said into this phone's *Hold to talk*.
  final bool voice;
  /// True while the phone writes its words.
  final bool writing;
  /// The recording on this phone, to play: [Relay.play] takes it.
  final String? recording;
  final Duration? length;
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

  /// The speech model voice notes need, and its download's progress from 0 to 1.
  ModelState get speechModel;
  double get modelProgress;
  ModelProblem? get modelProblem;
  /// The model's size, to show before the person agrees.
  int get modelBytes;
  /// The app shows *Get the speech model?*; *Not now* leaves it missing.
  void askSpeechModel();
  void notNowSpeechModel();
  /// *Get it* or *Try again*: the one request the app makes with sending off.
  Future<void> getSpeechModel();
  /// Deletes the model; the next voice note asks again.
  Future<void> removeSpeechModel();

  /// When the phone started listening, or null when it is not.
  DateTime? get listening;
  /// Hold: starts a voice note. Returns the words to show when it can not, such as a refused microphone or one that
  /// did not start; it does not throw.
  Future<String?> startVoiceNote();
  /// Let go: keeps the note and writes its words. Returns the words to show for a press too short to keep.
  Future<String?> endVoiceNote();
  /// Slide off: keeps nothing.
  Future<void> cancelVoiceNote();
  /// Plays a voice note's recording, from this phone.
  Future<void> play(String recording);

  final _notices = StreamController<String>.broadcast();
  /// Short messages that come later than the act, such as *No speech heard*.
  Stream<String> get notices => _notices.stream;
  void notice(String message) => _notices.add(message);

  @override
  void dispose() {
    _notices.close();
    super.dispose();
  }
}
