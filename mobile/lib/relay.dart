import 'package:flutter/foundation.dart';

import 'dart:async';
import 'dart:convert';

import 'data/files.dart';
import 'data/phone_calendar.dart';
import 'data/settings.dart';
import 'voice/model.dart';

export 'data/files.dart' show NewFile, sizeLabel;
export 'data/phone_calendar.dart' show PhoneCalendar;
export 'data/settings.dart' show Appearance, LocationMode, LocationSend, SendPlace, Settings;
export 'voice/model.dart' show ModelState, ModelProblem;

/// How long *Undo* shows after a note is deleted. The delete runs when its bar closes.
const undoTime = Duration(seconds: 5);

/// The longest a delete waits with no *Undo* bar to close it, as after a close: longer than [undoTime] with the bar's
/// own show and hide, and its wait behind a bar that closes, so a delete never runs while *Undo* still shows.
const deleteAfter = Duration(seconds: 10);

/// What [Relay.dropEmptyNote] did: a file or recording [kept] the note, a note never sent or queued was [dropped] at
/// once, or a note the server has or may get is [deleting], with *Undo*.
enum Emptied { kept, dropped, deleting }

/// One row of the timeline: a note typed or said on this phone, or one from elsewhere that a pull brought.
class Entry {
  const Entry({this.id = '', required this.text, required this.at, this.sent = false, this.waiting = false, this.voice = false,
    this.writing = false, this.failed = false, this.why, this.noWords = false, this.recording, this.length, this.files = const [],
    this.from});

  /// The phone's own id for the note: [Relay.editNote] takes it.
  final String id;
  /// The words, with their styles as Markdown marks: `plainText` gives them bare.
  final String text;
  final DateTime at;
  /// The server took it.
  final bool sent;
  /// It has an upload in the outbox while sending is on.
  final bool waiting;

  /// Said into this phone, by a hold on *New note* or from Shortcuts.
  final bool voice;
  /// True while the phone writes its words.
  final bool writing;
  /// True when its words failed or took too long: the recording is kept, and *Try again* writes them again.
  final bool failed;
  /// Why its words failed, such as `the speech engine stopped (code -6).`; null when they did not fail. It stays on
  /// the phone.
  final String? why;
  /// True for a watch note in which the phone found no words: it keeps its recording to play, and is not sent.
  final bool noWords;
  /// The recording on this phone, to play: [Relay.play] takes it.
  final String? recording;
  final Duration? length;

  /// The note's files, in the order they were added.
  final List<EntryFile> files;

  /// Where a note from elsewhere was made, such as `Email` or another phone; null for a note from this phone.
  final String? from;
}

/// One file on a note: kept on this phone, or, for a note from elsewhere, in the person's space until opened. In the
/// browser, each file stays in the person's space and [url] reads it.
class EntryFile {
  const EntryFile({this.id = '', required this.name, required this.type, required this.size, this.path = '', this.url});

  /// The file's id, which a download takes.
  final String id;
  final String name;
  final String type;
  final int size;
  /// The app's copy, as a full path; empty while the file is only in the person's space.
  final String path;

  bool get onPhone => path.isNotEmpty;

  /// The server's address for the file, which the browser reads; null on the phone, and while the file is on its way.
  final String? url;

  /// The file can show now: on this phone, or in the person's space for the browser.
  bool get ready => onPhone || url != null;

  /// A picture shows small in the note; any other file shows as a row with its name and size.
  bool get picture => type.startsWith('image/');
}

/// The recording that plays or is paused now: which one, how far it is, whether it plays, and its length when known.
@immutable
class Playback {
  const Playback({required this.recording, required this.at, required this.playing, this.length});

  /// The note's recording, as [Entry.recording] names it.
  final String recording;
  final Duration at;
  final bool playing;
  /// The recording's length as the player reads it, null until it knows. The browser gets no length with a note, so its
  /// player uses this one.
  final Duration? length;

  @override
  bool operator ==(Object other) => other is Playback && other.recording == recording && other.at == at &&
    other.playing == playing && other.length == length;

  @override
  int get hashCode => Object.hash(recording, at, playing, length);
}

/// No recording plays: the [Relay.playback] of a relay that plays none.
final ValueListenable<Playback?> noPlayback = ValueNotifier<Playback?>(null);

enum SyncStatus { idle, syncing, synced, offline, refused }

/// Where the app runs: the phone app, or the browser at the person's Relay Everything page. The browser shows no part
/// that only a phone can do, such as health, places, voice notes or the speech model.
enum RelayPlatform { phone, web }

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

/// One of the person's phones or computers, as `GET connections` names it: no key. [since] is when it connected, and
/// [lastChat] when a computer last saved a chat.
class ConnectedDevice {
  const ConnectedDevice({required this.id, required this.name, this.computer = false, this.since, this.lastChat});

  final String id;
  final String name;
  /// A computer with the plugin, in place of a phone.
  final bool computer;
  final DateTime? since;
  final DateTime? lastChat;

  static ConnectedDevice? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['name'] is! String) return null;
    DateTime? at(Object? ms) => ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    return ConnectedDevice(id: json['id'] as String, name: json['name'] as String, computer: json['kind'] == 'computer',
      since: at(json['since']), lastChat: at(json['lastChatAt']));
  }

  Map<String, Object> toJson() => {'id': id, 'name': name, 'kind': computer ? 'computer' : 'phone',
    if (since case final since?) 'since': since.millisecondsSinceEpoch,
    if (lastChat case final lastChat?) 'lastChatAt': lastChat.millisecondsSinceEpoch};
}

/// A connected AI app: its name, and the day it connected when the server says.
typedef AiApp = ({String name, DateTime? since});

/// The account's email and what the person connected, as the server last answered: their phones and computers, AI
/// apps and webhooks by name, and their two notes addresses. No key, webhook address, secret or send state.
class Connections {
  const Connections({this.email, this.aiApps = const [], this.webhooks = const [], this.devices = const [], this.thisDevice,
    this.notesAddress, this.sharedAddress, this.addressesKnown = false});

  /// The email of the account this phone's key belongs to; null from a server older than this field, and in a copy
  /// kept before it.
  final String? email;
  final List<AiApp> aiApps;
  final List<String> webhooks;
  /// The person's phones and computers that can still send, oldest first.
  final List<ConnectedDevice> devices;
  /// This phone's own id among [devices]; null from an older server.
  final String? thisDevice;
  /// The private address that takes mail from anyone, and `notes@`, which takes mail only from the sign-in email. Null
  /// when the server takes no email, and from an older server.
  final String? notesAddress;
  final String? sharedAddress;
  /// Whether the answer said anything about the two addresses. False in a copy kept by an older build of the app, and
  /// from a server older than these fields: then the phone can't tell that the server takes no email.
  final bool addressesKnown;

  List<ConnectedDevice> get phones => [for (final device in devices) if (!device.computer) device];
  List<ConnectedDevice> get computers => [for (final device in devices) if (device.computer) device];

  /// Reads `GET connections`' answer, or its copy kept on this phone. A name that is not text is left out.
  factory Connections.fromJson(Map<String, dynamic> json) {
    List<String> names(Object? list) =>
      [for (final item in list is List ? list : const []) if (item is Map && item['name'] is String) item['name'] as String];
    String? text(Object? value) => value is String && value.isNotEmpty ? value : null;
    final apps = json['aiApps'];
    return Connections(email: text(json['email']), webhooks: names(json['webhooks']),
      aiApps: [for (final app in apps is List ? apps : const []) if (app is Map && app['name'] is String)
        (name: app['name'] as String, since: app['connectedAt'] is int ? DateTime.fromMillisecondsSinceEpoch(app['connectedAt'] as int) : null)],
      devices: [for (final device in json['devices'] is List ? json['devices'] as List : const [])
        ?ConnectedDevice.fromJson(device)],
      thisDevice: text(json['thisDevice']), notesAddress: text(json['notesAddress']), sharedAddress: text(json['sharedAddress']),
      addressesKnown: json.containsKey('notesAddress') || json.containsKey('sharedAddress'));
  }

  static Connections? decode(String? saved) => saved == null ? null : Connections.fromJson(jsonDecode(saved) as Map<String, dynamic>);

  String encode() => jsonEncode({if (email != null) 'email': email,
    'aiApps': [for (final app in aiApps) {'name': app.name, if (app.since case final since?) 'connectedAt': since.millisecondsSinceEpoch}],
    'webhooks': [for (final name in webhooks) {'name': name}],
    'devices': [for (final device in devices) device.toJson()],
    if (thisDevice != null) 'thisDevice': thisDevice,
    if (addressesKnown || notesAddress != null) 'notesAddress': notesAddress,
    if (addressesKnown || sharedAddress != null) 'sharedAddress': sharedAddress});
}

/// What the screens read and do. The app's controller is one; a test's fake is another.
abstract class Relay extends ChangeNotifier {
  /// The phone app, or the browser. A screen hides each phone-only part on the web.
  RelayPlatform get platform => RelayPlatform.phone;
  bool get web => platform == RelayPlatform.web;

  bool get connected;
  String? get server;
  List<Entry> get entries;
  SyncStatus get status;
  int get waiting;
  Settings get settings;

  /// Health readings and location points: when each last went, and how many wait. Their folders show them.
  SendState get healthSent;
  SendState get pointsSent;
  /// Calendar events and removals: when they last went, and how many wait.
  SendState get calendarSent;
  /// The phone's calendars, while the calendar is on; each has its own switch in the Calendar folder.
  List<PhoneCalendar> get calendars;
  /// True on iPhone, where *Location history* has two ways to keep places.
  bool get locationModes;

  /// The account's email, the person's phones and computers, AI apps, webhooks and notes addresses, as their Relay
  /// Everything server last answered; null before an answer, and after sending stops.
  Connections? get connections;
  /// Asks the server for [connections], only while sending to a Relay Everything server; else it makes no request.
  Future<void> refreshConnections();
  /// *Sign out* beside another of the person's phones: its key stops at its next request. Returns the words to show
  /// when it could not, else null, and reads [connections] again.
  Future<String?> signOutPhone(String id);
  /// The Home headers the person folded, such as *On this phone*. The phone keeps them.
  Set<String> get folded;
  Future<void> setFolded(String header, bool folded);

  /// Each returns null on success, or the words to show when it failed.
  Future<String?> connect(String code);
  /// *Sign in*: the person signs in on [server] inside the app and confirms, and this phone gets its own
  /// key. Null also when the person closed the sign-in: then [connected] stays false.
  Future<String?> signIn(String server);
  Future<String?> setLocationMode(LocationMode mode);
  /// *What to send*: stays, trips and points, only stays and trips, or only points. *Only stays and trips* drops the points
  /// still waiting on this phone, and says so; *Only points* makes no stay or trip and asks for no motion.
  Future<String?> setLocationSend(LocationSend send);
  Future<String?> setServer(String server);
  /// *System*, *Light* or *Dark*: the app's look, which the phone keeps.
  Future<void> setAppearance(Appearance appearance);
  Future<String?> setHistory(bool on);
  Future<String?> setHealth(bool on);
  /// Turns the calendar on, after the phone's permission, or off, which drops what of it did not go.
  Future<String?> setCalendar(bool on);
  /// Turns one of the phone's calendars on or off. Its events leave the space at the next send.
  Future<void> setCalendarShown(String id, bool on);
  /// Turning on asks for photo access; only photos taken from then on go, to the server or the webhook, as the rest.
  /// Turning off drops the photos still waiting on this phone; the ones sent stay where they went.
  Future<String?> setPhotos(bool on);
  /// Off: photos wait for Wi-Fi.
  Future<String?> setPhotosOnMobileData(bool on);

  /// How many notes never went to the server: the earlier-notes prompt asks about them when sending turns on [to] a
  /// place, or the place set before. From the person's own webhook to a Relay Everything server, the notes that went only
  /// to the webhook count too.
  Future<int> earlierNotes({SendPlace? to});
  /// Turns sending on to [place], or to the place set before, with its key or webhook already kept. What waits moves
  /// there too. [sendEarlier] queues the earlier notes too, oldest first, as [earlierNotes] counts them. [privateTo]
  /// also sets where health, places, the calendar and photos go, as [setPrivatePlace] does, in the same step.
  Future<String?> startSending({required bool sendEarlier, SendPlace? place, SendPlace? privateTo});

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
  /// *Health, places, calendar and photos* on the Account page: [SendPlace.server] sends them to Relay Everything with
  /// the notes; [SendPlace.webhook] sends them only to the person's own webhook, kept first with [saveWebhook], while
  /// notes still sync. What of them waits moves too. [Settings.privateTo] keeps the choice.
  Future<String?> setPrivatePlace(SendPlace place);
  /// True while health, places, the calendar and photos should go only to the webhook, but the phone lost it, such as in
  /// a restore: they wait on the phone until the person sets it again.
  bool get privateWebhookMissing;
  /// Turns sending off: stops health, the calendar, location history and photos, and drops what of them did not go.
  /// Keeps notes and the key.
  Future<void> stopSending();

  /// *Sign out*: forgets the key, turns sending off, and deletes the notes from elsewhere.
  Future<void> disconnect();
  Future<void> sync();
  /// Sends this phone's notes, then reads the notes changed elsewhere: at start, on return to the app, and on pull-down.
  /// It ends with the notes, while health, places, the calendar and photos may still send after them.
  Future<void> pullNotes();
  /// The note open in the editor, which a pull leaves as it is.
  String? openNote;
  /// The open editor's words now, saved or not, so a closing browser page can still send them.
  ({String id, String text})? Function()? editorWords;
  /// Keeps a note with words, files, or both, as [id] when given. Returns the words to show for files left out, such
  /// as one over 25 MB, or for a note with nothing in it; null when all of it was kept. With [sendNow] false it waits
  /// for the next sync, as the editor saves while the person types.
  Future<String?> addNote(String text, {List<NewFile> files = const [], String? id, bool sendNow = true});
  /// Keeps the person's change to note [id]: its new words and files added. A sent note's change goes at the next sync,
  /// and with [sendNow] at once. Returns the words to show for files left out; null when all of it was kept.
  Future<String?> editNote(String id, String text, {List<NewFile> files = const [], bool sendNow = true});
  /// Deletes note [id], as Apple Notes does when you leave a note with no words: the editor calls it once the words are
  /// blank. A note never sent, with no upload, goes from this phone at once; a sent note, or one whose upload waits or
  /// is on its way, is deleted everywhere, as [deleteNote] does, with *Undo*. A note with a file or a recording stays.
  Future<Emptied> dropEmptyNote(String id);
  /// Deletes note [id]: it leaves the list at once, and [undoDelete] brings it back until [endUndo], or [deleteAfter] with
  /// no bar. Then it goes from this phone, and a sent note also from the person's space, their other phones and
  /// webhooks, at the next send.
  Future<void> deleteNote(String id);
  /// Brings back note [id], deleted and not yet gone, as it was. Nothing of the delete left the phone.
  Future<void> undoDelete(String id);
  /// The *Undo* bar of note [id] closed with no *Undo*: the delete runs now. A note brought back or gone stays as it is.
  Future<void> endUndo(String id);
  /// Opens a note's file in an app on the phone. A file not on the phone downloads first, with sending on.
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
  /// The sound level from 0 to 1 while the phone listens, only to draw the recording screen; null when it does not.
  Stream<double>? get level;
  /// True once a first voice note started on this phone, from any start: *New note* then shows no *Hold to talk*.
  bool get holdTipSeen;
  /// A hold on *New note*: starts a voice note. Returns the words to show when it can not, such as a refused microphone or one that
  /// did not start; it does not throw.
  Future<String?> startVoiceNote();
  /// A tap anywhere or the back gesture: keeps the note and writes its words. Returns the words to show for one too
  /// short to keep, for a microphone that did not stop, or for a note the phone could not keep; then nothing is kept.
  /// [listening] is null after it in every case.
  Future<String?> endVoiceNote();
  /// The X, *Cancel*: keeps nothing.
  Future<void> cancelVoiceNote();
  /// *Try again* on a note whose words failed: writes the words of each such note again, from its kept recording.
  Future<void> writeWordsAgain();
  /// Plays a voice note's recording: from this phone, or in the browser from the person's space. The recording that is
  /// paused plays on from where it stopped; another one stops it.
  Future<void> play(String recording);
  /// The recording that plays or is paused now, and how far it is; null when none. It changes many times a second while
  /// a recording plays, so only the player listens to it, not the whole page.
  ValueListenable<Playback?> get playback => noPlayback;
  /// Pauses the recording that plays, where it is.
  Future<void> pause() async {}
  /// Moves the recording that plays or is paused to [at].
  Future<void> seek(Duration at) async {}
  /// The recording's loudness from 0 to 1, in [bars] parts, read from its file on this phone and kept by no one. Empty
  /// when it can not be read, such as in the browser or for a file that is not a WAV.
  Future<List<double>> waveOf(String recording, {int bars = 48}) async => const [];

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
