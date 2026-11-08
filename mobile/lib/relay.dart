import 'package:flutter/foundation.dart';

import 'dart:async';

import 'data/attachments.dart';
import 'data/settings.dart';
import 'sync/calendar.dart';
import 'voice/model.dart';

export 'data/attachments.dart' show NewFile, sizeLabel;
export 'data/settings.dart' show LocationMode, SendPlace, Settings;
export 'sync/calendar.dart' show PhoneCalendar;
export 'voice/model.dart' show ModelState, ModelProblem;

/// One row of the timeline: a note typed or said on this phone.
class Entry {
  const Entry({this.id = '', required this.text, required this.at, this.place, this.sent = false, this.waiting = false, this.voice = false,
    this.writing = false, this.failed = false, this.recording, this.length, this.files = const []});

  /// The phone's own id for the note: [Relay.editNote] takes it.
  final String id;
  /// The words, with their styles as Markdown marks: `plainText` gives them bare.
  final String text;
  final DateTime at;
  final String? place;
  /// The server took it.
  final bool sent;
  /// It has an upload in the outbox, or waits for its pin, while sending is on.
  final bool waiting;

  /// Said into this phone, by a hold on *New note* or from Shortcuts.
  final bool voice;
  /// True while the phone writes its words.
  final bool writing;
  /// True when its words failed or took too long: the recording is kept, and *Try again* writes them again.
  final bool failed;
  /// The recording on this phone, to play: [Relay.play] takes it.
  final String? recording;
  final Duration? length;

  /// The note's files on this phone, in the order they were added.
  final List<EntryFile> files;
}

/// One file on a note, kept on this phone.
class EntryFile {
  const EntryFile({required this.name, required this.type, required this.size, required this.path});

  final String name;
  final String type;
  final int size;
  /// The app's copy, as a full path.
  final String path;

  /// A picture shows small in the note; any other file shows as a row with its name and size.
  bool get picture => type.startsWith('image/');
}

enum SyncStatus { idle, syncing, synced, offline, refused }

/// When one kind of data, health, places or the calendar, last reached the server, and how many of it wait to send.
class SendState {
  const SendState({this.at, this.waiting = 0});

  /// Null when none went yet.
  final DateTime? at;
  final int waiting;
}

/// The last time the person's own webhook did not take an upload: its answer's [status], or null for no answer. A
/// [file] is a file it refused as too large, which the phone dropped.
class WebhookProblem {
  const WebhookProblem({required this.at, this.status, this.file});

  final DateTime at;
  final int? status;
  final String? file;
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
  /// Calendar events and removals: when they last went, and how many wait.
  SendState get calendarSent;
  /// The phone's calendars, while the calendar is on; each has its own switch in Settings.
  List<PhoneCalendar> get calendars;
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
  /// Turns the calendar on, after the phone's permission, or off, which drops what of it did not go.
  Future<String?> setCalendar(bool on);
  /// Turns one of the phone's calendars on or off. Its events leave the space at the next send.
  Future<void> setCalendarShown(String id, bool on);

  /// How many notes never went to the server: the earlier-notes prompt asks about them when sending turns on.
  Future<int> earlierNotes();
  /// Turns sending on to [place], or to the place set before, with its key or webhook already kept. What waits moves
  /// there too. [sendEarlier] queues the earlier notes too, oldest first.
  Future<String?> startSending({required bool sendEarlier, SendPlace? place});

  /// The person's own webhook, when one is kept: its address and secret.
  String? get webhookAddress;
  String? get webhookSecret;
  /// The last answer from the webhook that was not 2xx, or null.
  WebhookProblem? get webhookProblem;
  /// A new `whsec_` secret to show, copy and save.
  String newWebhookSecret();
  /// Keeps the webhook's address and secret; returns why it could not.
  Future<String?> saveWebhook(String address, String secret);
  /// *Send a test*: a signed test message to [address]. Returns the words to show: the receiver's answer, or why not.
  Future<String> testWebhook(String address, String secret);
  /// Turns sending off: stops health, the calendar and location history and drops what of them did not go. Keeps notes
  /// and the key.
  Future<void> stopSending();

  /// Forgets the key and turns sending off.
  Future<void> disconnect();
  Future<void> sync();
  /// Keeps a note with words, files, or both, as [id] when given. Returns the words to show for files left out, such
  /// as one over 25 MB, or for a note with nothing in it; null when all of it was kept. With [sendNow] false it waits
  /// for the next sync, as the editor saves while the person types.
  Future<String?> addNote(String text, {List<NewFile> files = const [], String? id, bool sendNow = true});
  /// Keeps the person's change to note [id]: its new words and files added. A sent note's change goes at the next sync,
  /// and with [sendNow] at once. Returns the words to show for files left out; null when all of it was kept.
  Future<String?> editNote(String id, String text, {List<NewFile> files = const [], bool sendNow = true});
  /// Deletes note [id] from this phone, as Apple Notes does when you leave a note with no words: the editor calls it once
  /// the words are blank. Any upload or change of it still waiting goes too, so it is never sent; a copy the server
  /// took keeps its last words there. A note with a file or a recording stays: false then.
  Future<bool> dropEmptyNote(String id);
  /// Opens a note's file in an app on the phone.
  Future<void> openFile(EntryFile file);

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
  /// A hold on *New note*: starts a voice note. Returns the words to show when it can not, such as a refused microphone or one that
  /// did not start; it does not throw.
  Future<String?> startVoiceNote();
  /// A tap anywhere: keeps the note and writes its words. Returns the words to show for one too short to keep, for a
  /// microphone that did not stop, or for a note the phone could not keep; then nothing is kept. [listening] is null
  /// after it in every case.
  Future<String?> endVoiceNote();
  /// *Cancel*: keeps nothing.
  Future<void> cancelVoiceNote();
  /// *Try again* on a note whose words failed: writes the words of each such note again, from its kept recording.
  Future<void> writeWordsAgain();
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
