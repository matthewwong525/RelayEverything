import 'package:flutter/foundation.dart';

import 'dart:async';

import 'data/settings.dart';
import 'voice/model.dart';

export 'data/settings.dart' show LocationMode, Settings;
export 'voice/model.dart' show ModelState, ModelProblem;

/// One row of the timeline: a note typed or said on this phone.
class Entry {
  const Entry({required this.text, required this.at, this.place, this.sent = false, this.waiting = false, this.voice = false,
    this.writing = false, this.recording, this.length});

  final String text;
  final DateTime at;
  final String? place;
  /// The server took it.
  final bool sent;
  /// It has an upload in the outbox, or waits for its pin, while sending is on.
  final bool waiting;

  /// Said into this phone's *Hold to talk*.
  final bool voice;
  /// True while the phone writes its words.
  final bool writing;
  /// The recording on this phone, to play: [Relay.play] takes it.
  final String? recording;
  final Duration? length;
}

enum SyncStatus { idle, syncing, synced, offline, refused }

/// When one kind of data, health or places, last reached the server, and how many of it wait to send.
class SendState {
  const SendState({this.at, this.waiting = 0});

  /// Null when none went yet.
  final DateTime? at;
  final int waiting;
}

/// What the screens read and do. The app's controller is one; a test's fake is another.
abstract class Relay extends ChangeNotifier {
  bool get connected;
  String? get server;
  List<Entry> get entries;
  SyncStatus get status;
  int get waiting;
  Settings get settings;

  /// Health readings and location points: when each last went, and how many wait. Settings shows them.
  SendState get healthSent;
  SendState get pointsSent;
  /// True on iPhone, where *Location history* has two ways to keep places.
  bool get locationModes;

  /// Each returns null on success, or the words to show when it failed.
  Future<String?> connect(String code);
  /// *Sign in to connect*: the person signs in on [server] inside the app and confirms, and this phone gets its own
  /// key. Null also when the person closed the sign-in: then [connected] stays false.
  Future<String?> signIn(String server);
  Future<String?> setLocationMode(LocationMode mode);
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
