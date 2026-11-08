import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'data/api.dart';
import 'data/attachments.dart';
import 'data/connection.dart';
import 'data/outbox.dart';
import 'data/sender.dart';
import 'data/settings.dart';
import 'data/sign_in.dart';
import 'data/store.dart';
import 'data/webhook.dart';
import 'relay.dart';
import 'share/inbox.dart';
import 'shortcuts/inbox.dart';
import 'sync/calendar.dart';
import 'sync/health.dart';
import 'sync/location.dart';
import 'sync/native.dart';
import 'voice/model.dart';
import 'voice/recorder.dart';
import 'voice/transcriber.dart';

// The first versions kept the server's timeline here. A device key reads nothing now, so load deletes it.
const _oldTimeline = 'timeline';

/// What voice notes need: the speech model, the microphone, the words and playback. All of it stays on this phone.
class VoiceParts {
  const VoiceParts({required this.model, required this.recorder, required this.transcriber, required this.player});

  final SpeechModel model;
  final VoiceRecorder recorder;
  final Transcriber transcriber;
  final VoicePlayer player;
}

/// Opens a file in an app on the phone; false when no app could.
typedef FileOpener = Future<bool> Function(File file, String type);

/// What [RelayController.keepNote] kept: the note, or null when it kept nothing, and the words to show for what it left
/// out.
class Kept {
  const Kept(this.note, this.problem);

  final LocalNote? note;
  final String? problem;
}

/// How long a voice note's words may take: 2 minutes, or the recording's [length] when it is longer. A 5-minute note
/// can take near a minute on an older phone.
Duration wordsLimitOf(Duration length) => length > const Duration(minutes: 2) ? length : const Duration(minutes: 2);

/// A random id for a note, so a resend is stored once.
String newClientId([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(16, (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// The app's one Relay: notes in the store, and the key in the vault. Notes stay on this phone; while sending is on,
/// it syncs on open, on a new note, on pull, and every hour in the background.
class RelayController extends Relay {
  RelayController({required this.store, required this.vault, required this.places, required this.health,
    RelayApi Function(Connection)? apiFor, http.Client Function()? signInClient, WebAuth? webAuth, DateTime Function()? clock,
    WebhookClient Function(Webhook webhook, String installId)? webhookFor, this.schedule, this.voice, this.native, this.folder,
    this.opener, this.share, this.calendar, Duration Function(Duration length)? wordsLimit})
    : _sender = Sender(apiFor, signInClient, webhookFor), _webAuth = webAuth ?? phoneWebAuth, _clock = clock ?? DateTime.now,
      _wordsLimit = wordsLimit ?? wordsLimitOf {
    voice?.model.addListener(notifyListeners);
    // A recording at its longest ends as if the person let go.
    voice?.recorder.onLongest = (recording) {
      _listening = null;
      notifyListeners();
      if (recording == null) return notice(_stopFailed);
      unawaited(_keepVoice(recording).then((problem) => problem == null ? null : notice(problem)));
    };
  }

  final Store store;
  final KeyVault vault;
  final Places places;
  final HealthSource health;
  /// The phone's calendars; with none, the calendar can not turn on.
  final CalendarSource? calendar;
  /// Turns the hourly background sync on or off.
  final Future<void> Function(bool on)? schedule;
  /// Voice notes; with none, the app has typed notes only.
  final VoiceParts? voice;
  /// The iPhone's Swift side, which keeps places and wakes the app while it is closed; null on Android.
  final NativeBackground? native;
  /// The app's support folder, where a note's files are kept in `attachments/`; with none, notes take no files.
  final Future<Directory> Function()? folder;
  /// Opens a note's file; with none, the app says it can not.
  final FileOpener? opener;
  /// The App Group the iPhone's share card writes to; null on Android, where the share card is this app's own window.
  final ShareGroup? share;
  final Sender _sender;
  final WebAuth _webAuth;
  final DateTime Function() _clock;
  /// How long a voice note's words may take, from its recording's length; a test makes it short.
  final Duration Function(Duration length) _wordsLimit;

  Connection? _connection;
  Webhook? _webhook;
  String? _installId;
  WebhookProblem? _problem;
  List<Entry> _entries = const [];
  SyncStatus _status = SyncStatus.idle;
  int _waiting = 0;
  Settings _settings = const Settings();
  StreamSubscription<Pin>? _history;
  Timer? _drainTimer;
  SendState _healthSent = const SendState(), _pointsSent = const SendState(), _calendarSent = const SendState();
  List<PhoneCalendar> _calendars = const [];
  Future<void>? _syncing;
  bool _again = false;
  DateTime? _listening;
  Future<bool>? _starting;
  final _writing = <Future<void>>{};
  // Voice notes whose words failed in this run of the app. The next open, or *Try again*, writes them again.
  final _wordsFailed = <String>{};
  final _pinning = <Future<void>>{};
  String? _root;

  @override bool get connected => _connection != null;
  @override String? get server => _connection?.server;
  @override List<Entry> get entries => _entries;
  @override SyncStatus get status => _status;
  @override int get waiting => _waiting;
  @override Settings get settings => _settings;
  @override SendState get healthSent => _healthSent;
  @override SendState get pointsSent => _pointsSent;
  @override SendState get calendarSent => _calendarSent;
  @override List<PhoneCalendar> get calendars => _calendars;
  @override bool get locationModes => native != null;
  @override String? get webhookAddress => _webhook?.address;
  @override String? get webhookSecret => _webhook?.secret;
  @override WebhookProblem? get webhookProblem => _problem;

  Outbound? get _api => _sender.api(_settings, connection: _connection, webhook: _webhook, installId: _installId);

  /// True when [place] has what it sends with: a key for the server, or a webhook's address and secret.
  bool _ready(SendPlace place) => place == SendPlace.server ? _connection != null : _webhook != null;

  /// Reads the key, the settings and the notes, so the app opens with no network. With [watch] false, as in the
  /// Android share card's window, it starts no location history: the app's own engine keeps it.
  Future<void> load({bool watch = true}) async {
    // The app is open, so the phone is unlocked: a key kept by an earlier version is saved again for locked-phone wakes.
    _connection = await vault.upgrade();
    _webhook = await vault.readWebhook();
    _installId = await store.installId();
    final saved = await store.get(settingsKey);
    _settings = Settings.decode(saved, hasKey: _connection != null);
    // A phone that lost its key or webhook, such as from a restore, can not send: sending reads as off until set again.
    if (_settings.sending && !_ready(_settings.place)) _settings = _settings.copyWith(sending: false);
    // The first version's settings, read once by the upgrade rule, are saved in today's shape.
    if (_settings.encode() != saved) await store.set(settingsKey, _settings.encode());
    final destination = destinationOf(_settings.place);
    if (await store.destination() != destination) await store.moveOutbox(destination);
    await store.remove(_oldTimeline);
    await _tellNative();
    await _tellShare();
    if (watch && _settings.history) _startHistory();
    // Nothing waits for a fix yet at start, so a note still waiting lost its wait when the app closed.
    await store.settleWaiting(send: _settings.sending);
    _root = (await folder?.call())?.path;
    // A shortcut that ran while the app could not answer left its note in the inbox.
    final root = _root;
    if (root != null) {
      await drainInbox(Directory(root), (request) async {
        final recording = request.recording;
        if (recording == null) {
          await keepNote(request.text, files: request.files, clientId: request.id, createdAt: request.createdAt, pin: false);
        } else {
          await keepRecording(request.text, recording: recording.path, durationMs: recording.durationMs, clientId: request.id,
            createdAt: request.createdAt, pin: false);
        }
      });
    }
    await _drainShare(refresh: false);
    await voice?.model.load();
    if (_settings.calendar) await _readCalendars();
    await _refreshLocal();
    // A voice note whose words the app's close cut short gets them now, from its kept recording.
    _track(_writePending(dropStray: true));
  }

  /// Keeps each note the iPhone's share card left, with no place. Load, each return to the app, and the hourly round
  /// run it before they send.
  Future<void> _drainShare({bool refresh = true}) async {
    final root = _root, group = share;
    if (root == null || group == null) return;
    try {
      final folder = await group.folder();
      if (folder == null) return;
      if (await drainShareInbox(folder, root, store, send: _settings.sending, clock: _clock) > 0 && refresh) {
        await _refreshLocal();
      }
    } on Exception {
      // A build with no App Group, or an engine with no Swift side: nothing to keep.
    }
  }

  /// Each return to the app: keeps what the share card left, shows what another engine added to the store, such as
  /// Android's share window, then sends what waits.
  Future<void> resume() async {
    await _drainShare(refresh: false);
    await _refreshLocal();
    await sync();
  }

  Entry _entryOfLocal(LocalNote note) => Entry(id: note.clientId, text: note.text, at: note.createdAt,
    // With sending off the phone looks up no place name, so a pin with no name reads as Pinned.
    place: note.pin == null ? null : note.pin!.place ?? 'Pinned',
    sent: note.sentAt != null, waiting: _settings.sending && note.sentAt == null && (note.queued || note.pinning),
    voice: note.kind == NoteKind.voice, writing: note.wordsPending && !_wordsFailed.contains(note.clientId),
    failed: note.wordsPending && _wordsFailed.contains(note.clientId), recording: note.audioPath,
    length: note.durationMs == null ? null : Duration(milliseconds: note.durationMs!),
    files: [for (final file in note.attachments)
      EntryFile(name: file.name, type: file.type, size: file.size, path: fullPath(file.path))]);

  /// The app's support folder, once [load] has read it.
  String? get filesRoot => _root;

  /// A path from the support folder, made full.
  String fullPath(String path) => _root == null || path.startsWith('/') ? path : '$_root/$path';

  /// The list shows this phone's own notes, newest first. Ring notes and recordings are on the person's Relay page.
  Future<void> _refreshLocal() async {
    final notes = await store.notes();
    _waiting = await store.waiting();
    _healthSent = SendState(at: await store.sentAt(sentHealth), waiting: await store.waitingReadings());
    _pointsSent = SendState(at: await store.sentAt(sentPoints), waiting: await store.waitingPoints());
    _problem = _problemOf(await store.get(webhookProblemKey));
    _calendarSent = SendState(at: await store.sentAt(sentCalendar), waiting: await store.waitingEvents());
    _entries = [for (final note in notes) _entryOfLocal(note)];
    notifyListeners();
  }

  @override
  Future<String?> connect(String code) async {
    final connection = Connection.parse(code);
    if (connection == null) return 'That is not a Relay Everything key. Scan the QR code again, or paste all of it.';
    try {
      await _sender.check(connection).key();
    } on ApiException catch (error) {
      // With no signal the key is kept and tried on the next sync.
      if (error.failure != Failure.offline) return 'The server did not take this key. Make a new key and try again.';
    }
    await vault.save(connection);
    _connection = connection;
    await _tellShare();
    notifyListeners();
    return null;
  }

  static const _badServer = 'Enter an address that starts with https:// and has no path.';
  static const _signInFailed = 'The server did not connect this phone. Sign in and try again.';

  @override
  Future<String?> signIn(String address) async {
    final server = Connection.serverOf(address);
    if (server == null) return _badServer;
    final verifier = newVerifier();
    final Uri? back;
    try {
      back = await _webAuth(signInUrl(server, challengeOf(verifier), Platform.isIOS ? 'iPhone' : 'Android phone'));
    } on Exception {
      return 'The sign-in did not open. Try again.';
    }
    final code = back?.queryParameters['code'];
    // Closed, or *Cancel* on the page: nothing to say.
    if (back == null || back.queryParameters['error'] == 'cancelled') return null;
    if (code == null) return _signInFailed;
    final Connection connection;
    try {
      connection = await _sender.trade(server, code, verifier);
      await _sender.check(connection).key();
    } on ApiException catch (error) {
      return error.failure == Failure.offline ? 'No connection. Try again when the phone is online.' : _signInFailed;
    }
    await vault.save(connection);
    _connection = connection;
    await _tellShare();
    notifyListeners();
    return null;
  }

  @override
  Future<String?> setServer(String text) async {
    final server = Connection.serverOf(text);
    if (server == null) return _badServer;
    if (_connection == null) return 'Connect a key first.';
    _connection = _connection!.withServer(server);
    await vault.save(_connection!);
    await _tellShare();
    notifyListeners();
    return null;
  }

  @override
  Future<int> earlierNotes() => store.earlierCount();

  static WebhookProblem? _problemOf(String? saved) {
    if (saved == null) return null;
    final json = jsonDecode(saved) as Map<String, dynamic>;
    return WebhookProblem(at: DateTime.fromMillisecondsSinceEpoch(json['at'] as int), status: json['status'] as int?,
      file: json['file'] as String?);
  }

  /// Moves what waits to [place] in one step, so nothing goes to the place left. A round sending there stops at its next
  /// upload, and a new round starts after it.
  @override
  Future<String?> startSending({required bool sendEarlier, SendPlace? place}) async {
    final to = place ?? _settings.place;
    if (!_ready(to)) return to == SendPlace.server ? 'Connect a key first.' : 'Set your webhook first.';
    await store.moveOutbox(destinationOf(to));
    if (sendEarlier) await store.queueEarlier();
    await _saveSettings(_settings.copyWith(sending: true, place: to));
    await _refreshLocal();
    final running = _syncing;
    unawaited(running == null ? sync() : running.then((_) => sync()));
    return null;
  }

  @override
  String newWebhookSecret() => makeWebhookSecret();

  /// Checks the address and secret, as both [saveWebhook] and [testWebhook] take them.
  static (Webhook?, String?) _webhookOf(String address, String secret) {
    final problem = Webhook.addressProblem(address) ?? Webhook.secretProblem(secret);
    return problem != null ? (null, problem) : (Webhook(address: address.trim(), secret: secret.trim()), null);
  }

  @override
  Future<String?> saveWebhook(String address, String secret) async {
    final (webhook, problem) = _webhookOf(address, secret);
    if (webhook == null) return problem;
    await vault.saveWebhook(webhook);
    _webhook = webhook;
    // A new address or secret starts with no failure to show.
    await store.remove(webhookProblemKey);
    _problem = null;
    notifyListeners();
    return null;
  }

  @override
  Future<String> testWebhook(String address, String secret) async {
    final (webhook, problem) = _webhookOf(address, secret);
    if (webhook == null) return problem!;
    final status = await _sender.tryWebhook(webhook, _installId ?? await store.installId()).test();
    return switch (status) {
      null => 'No answer from ${webhook.host}. Check the address, and that your receiver is running.',
      final ok when ok >= 200 && ok < 300 => 'Your receiver answered $ok. It works.',
      401 || 403 => 'Your receiver answered $status. Check that it has this secret.',
      _ => 'Your receiver answered $status.',
    };
  }

  @override
  Future<void> stopSending() async {
    await _saveSettings(_settings.copyWith(sending: false));
    _calendars = const [];
    await _stopHistory();
    // A round already sending finishes first, so nothing it read lands after the drop.
    await _syncing;
    await store.dropReadings();
    _status = SyncStatus.idle;
    await _refreshLocal();
  }

  @override
  Future<void> disconnect() async {
    await stopSending();
    await vault.forget();
    _connection = null;
    await _tellShare();
    notifyListeners();
  }

  Future<void> _saveSettings(Settings settings) async {
    _settings = settings;
    await store.set(settingsKey, settings.encode());
    await schedule?.call(settings.history || settings.health || settings.calendar);
    await _tellNative();
    await _tellShare();
    notifyListeners();
  }

  /// Tells the iPhone's share card whether it may send: only while sending to the server is on and a key is kept. While
  /// the phone sends to the person's own webhook, the card only keeps each share, and the app sends it.
  Future<void> _tellShare() async {
    final server = _settings.place == SendPlace.server;
    try {
      await share?.setSending(_settings.sending && server && _connection != null, later: _settings.sending && !server);
    } on Exception {
      // An engine with no Swift side; the next start tells it again.
    }
  }

  /// Tells Swift what it may read and keep while the app is closed: nothing while sending is off.
  Future<void> _tellNative() async {
    try {
      await native?.set(health: _settings.health, history: _settings.history, mode: _settings.mode);
    } on Exception {
      // An engine with no Swift side, such as a test's; the next start tells it again.
    }
  }

  static const _noLocation = 'Relay Everything may not read your location. Allow it in the phone\'s settings.';
  static const _sendFirst = 'Turn on Send my notes first.';

  @override
  Future<String?> setPinNotes(bool on) async {
    if (on && !await places.allow(always: false)) return _noLocation;
    await _saveSettings(_settings.copyWith(pinNotes: on));
    return null;
  }

  @override
  Future<String?> setHistory(bool on) async {
    if (on && !_settings.sending) return _sendFirst;
    if (on && !await places.allow(always: true)) return 'Relay Everything may not read your location all the time. Allow it in the phone\'s settings.';
    await _saveSettings(_settings.copyWith(history: on));
    if (on) {
      _startHistory();
    } else {
      await _stopHistory();
    }
    return null;
  }

  @override
  Future<String?> setLocationMode(LocationMode mode) async {
    await _saveSettings(_settings.copyWith(mode: mode));
    return null;
  }

  /// Android keeps its own stream. On iPhone, Swift keeps the points, and the open app moves them in each minute, so
  /// the timeline's pins do not wait for the next round.
  void _startHistory() {
    if (native == null) {
      _history ??= places.history().listen((point) => store.addPoint(point), onError: (_) {});
      return;
    }
    _drainTimer ??= Timer.periodic(const Duration(minutes: 1), (_) => unawaited(_drain()));
    unawaited(_drain());
  }

  Future<void> _stopHistory() async {
    _drainTimer?.cancel();
    _drainTimer = null;
    await _history?.cancel();
    _history = null;
  }

  Future<void> _drain() async {
    final swift = native;
    if (swift == null || !_settings.history) return;
    try {
      if (await drainPoints(store, swift, name: _settings.sending ? places.nameOf : null) > 0) await _refreshLocal();
    } on Exception {
      // Swift empties its file as it answers, but the points are in the store before any name lookup, so a failure
      // here costs at most a name.
    }
  }

  @override
  Future<String?> setHealth(bool on) async {
    if (on && !_settings.sending) return _sendFirst;
    if (on && !await health.allow()) return 'Relay Everything may not read your health data. Allow it in the phone\'s health settings.';
    // Health starts from now: the next rounds read new readings, and the last 90 days a week at a time.
    if (on) await startHealth(store, _clock());
    await _saveSettings(_settings.copyWith(health: on));
    if (on) unawaited(sync());
    return null;
  }

  /// At open, asks once more for health when this version reads types the phone was not asked for, such as after an
  /// update. Asked once, whatever the answer: the phone's health settings change it later. The asked types are kept
  /// only when the question closes, so a background round while it is open does not start the history read before
  /// the new types are allowed.
  Future<void> askNewHealthTypes() async {
    if (!_settings.health || await store.get(healthTypes) == askedTypes) return;
    try {
      await health.allow();
    } on Exception {
      // The next open does not ask again; the person allows types in the phone's health settings.
    } finally {
      await store.set(healthTypes, askedTypes);
    }
  }

  static const _noCalendar = 'Relay Everything may not read your calendar. Allow it in the phone\'s settings.';

  @override
  Future<String?> setCalendar(bool on) async {
    if (on && !_settings.sending) return _sendFirst;
    final source = calendar;
    if (on) {
      try {
        if (source == null || !await source.allow()) return _noCalendar;
      } on Exception {
        return _noCalendar;
      }
    }
    await _saveSettings(_settings.copyWith(calendar: on));
    if (on) {
      await _readCalendars();
      unawaited(sync());
    } else {
      // A round already reading finishes first, so nothing it queued stays after the drop.
      await _syncing;
      await store.dropCalendar();
      _calendars = const [];
      await _refreshLocal();
    }
    return null;
  }

  @override
  Future<void> setCalendarShown(String id, bool on) async {
    final off = {..._settings.calendarsOff};
    on ? off.remove(id) : off.add(id);
    await _saveSettings(_settings.copyWith(calendarsOff: off));
    unawaited(sync());
  }

  /// Lists the phone's calendars for Settings. A refused or failed read leaves the list as it was.
  Future<void> _readCalendars() async {
    try {
      _calendars = await calendar?.calendars() ?? const [];
    } on Exception {
      return;
    }
    notifyListeners();
  }

  static const _nothing = 'Give the note words or a file.';

  /// Keeps and shows the note at once; Save never waits for a fix. With pins on, the note settles only when the phone
  /// has a fix or gives up (up to 10 s), so a sync meanwhile sends the rest and leaves this note waiting.
  @override
  Future<String?> addNote(String text, {List<NewFile> files = const [], String? id, bool sendNow = true}) async =>
    (await keepNote(text, files: files, clientId: id, sendNow: sendNow)).problem;

  @override
  Future<String?> editNote(String id, String text, {List<NewFile> files = const [], bool sendNow = true}) async {
    final check = checkFiles(const [], files, already: (await store.attachmentsOf(id)).length);
    final (attachments, problems) = await _keepFiles(check.kept, check.problem);
    if (await store.editNote(id, text, files: attachments, send: _settings.sending, at: _clock())) await _refreshLocal();
    if (sendNow) unawaited(sync());
    return problems.isEmpty ? null : problems.join(' ');
  }

  @override
  Future<bool> dropEmptyNote(String id) async {
    if (!await store.dropEmptyNote(id)) return false;
    await _refreshLocal();
    return true;
  }

  /// Keeps each file's own copy, with [problem] and a line for each file the phone could not read.
  Future<(List<Attachment>, List<String>)> _keepFiles(Iterable<NewFile> files, String? problem) async {
    final problems = [?problem];
    final attachments = <Attachment>[];
    for (final file in files) {
      final kept = await _keepFile(file);
      if (kept == null) {
        problems.add('${file.name} could not be read, so it was not added.');
      } else {
        attachments.add(kept);
      }
    }
    return (attachments, problems);
  }

  /// Keeps a note with words, files, or both, as the paperclip and Shortcuts make it. Files past the limits are left out
  /// with a message. A note with nothing in it is kept not at all. A [clientId] this phone already keeps gives back that
  /// note, so a shortcut that ran twice keeps one. [pin] false keeps no place, for a note made earlier than now.
  Future<Kept> keepNote(String text, {List<NewFile> files = const [], String? clientId, DateTime? createdAt,
    bool pin = true, bool sendNow = true}) async {
    final id = clientId ?? newClientId();
    if (await store.hasNote(id)) {
      return Kept((await store.notes()).firstWhere((note) => note.clientId == id), null);
    }
    final check = checkFiles(const [], files);
    final (attachments, problems) = await _keepFiles(check.kept, check.problem);
    final words = text.trim();
    if (words.isEmpty && attachments.isEmpty) return Kept(null, [...problems, _nothing].join(' '));
    final note = LocalNote(clientId: id, text: words, createdAt: createdAt ?? _clock(), attachments: attachments);
    final pinned = pin && _settings.pinNotes;
    await store.addNote(note, waitForPin: pinned, send: _settings.sending);
    await _refreshLocal();
    if (pinned) {
      final job = _pinThenSync(id);
      _pinning.add(job);
      job.whenComplete(() => _pinning.remove(job));
    } else if (sendNow) {
      unawaited(sync());
    }
    return Kept(note, problems.isEmpty ? null : problems.join(' '));
  }

  /// Keeps a shortcut's recording, a WAV Swift left at [recording] from the support folder, as a voice note that waits
  /// for its words, with [text], the words typed with it, first. The note is kept before its recording moves to
  /// `voice/<id>.wav`, so the sweep for stray recordings never takes it. It pins as [keepNote] does, and a [clientId]
  /// already kept gives back that note. The words are written now when this engine has the voice parts, else at the
  /// app's next open. A recording that is not there keeps the typed words alone, or nothing.
  Future<Kept> keepRecording(String text, {required String recording, required int durationMs, String? clientId,
    DateTime? createdAt, bool pin = true}) async {
    final id = clientId ?? newClientId();
    if (await store.hasNote(id)) {
      return Kept((await store.notes()).firstWhere((note) => note.clientId == id), null);
    }
    final root = _root ?? (await folder?.call())?.path;
    final source = File('$root/$recording');
    if (root == null || !await source.exists()) return keepNote(text, clientId: id, createdAt: createdAt, pin: pin);
    final note = LocalNote(clientId: id, text: text.trim(), createdAt: createdAt ?? _clock(), kind: NoteKind.voice,
      audioPath: VoiceRecorder.pathOf(id), durationMs: durationMs, wordsPending: true);
    final pinned = pin && _settings.pinNotes;
    await store.addVoiceNote(note, waitForPin: pinned);
    try {
      final target = File('$root/${note.audioPath}');
      await target.parent.create(recursive: true);
      await source.rename(target.path);
    } on FileSystemException {
      await store.dropNote(id);
      rethrow;
    }
    await _refreshLocal();
    if (pinned) {
      final job = _pinThenSync(id);
      _pinning.add(job);
      job.whenComplete(() => _pinning.remove(job));
    }
    if (voice != null) _track(_write(note));
    return Kept(note, null);
  }

  /// Copies a file into `attachments/<id><.ext>`, or moves the app's own copy there. Null when it could not.
  Future<Attachment?> _keepFile(NewFile file) async {
    final root = _root ?? (await folder?.call())?.path;
    if (root == null) return null;
    return keepFile(root, file, newClientId());
  }

  /// Ends when each new note has its pin, and the sync after it is done. Shortcuts waits on it, so a note goes before the
  /// phone puts the app away.
  Future<void> settled() async {
    while (_pinning.isNotEmpty) {
      await Future.wait(List.of(_pinning));
    }
    await _syncing;
  }

  static const _noFile = 'This file is not on this phone.';
  static const _noApp = 'No app on this phone opens this file.';

  @override
  Future<void> openFile(EntryFile file) async {
    final found = File(file.path);
    if (!await found.exists()) return notice(_noFile);
    final open = opener;
    if (open == null || !await open(found, file.type)) notice(_noApp);
  }

  Future<void> _pinThenSync(String clientId) async {
    Pin? pin;
    try {
      pin = await places.here(name: _settings.sending);
    } on Exception {
      // No fix: the note is kept without a place.
    }
    await store.settlePin(clientId, pin, send: _settings.sending);
    await _refreshLocal();
    await sync();
  }

  /// One sync at a time; a second call waits for the one running. With sending off it does nothing. A call while a round
  /// runs asks for one more round after it, because that round read the outbox before the call's note was queued.
  @override
  Future<void> sync() {
    final running = _syncing;
    if (running != null) {
      _again = true;
      return running;
    }
    return _syncing = _rounds().whenComplete(() => _syncing = null);
  }

  /// Runs rounds until no call asked for another, or a round could not send everything.
  Future<void> _rounds() async {
    bool emptied;
    do {
      _again = false;
      emptied = await _sync();
    } while (_again && emptied && _settings.sending);
  }

  /// One round; true when the outbox emptied.
  Future<bool> _sync() async {
    final api = _api;
    if (api == null) return false;
    _status = SyncStatus.syncing;
    notifyListeners();
    // Sending can turn off while a round runs: from then on it reads, queues and sends nothing more.
    if (_settings.health) {
      try {
        await syncHealth(store, health, now: _clock());
      } on Exception {
        // The health store can be closed for a while, such as on a locked iPhone; the next round reads again.
      }
    }
    final source = calendar;
    if (_settings.calendar && source != null) {
      try {
        await syncCalendar(store, source, _settings, now: _clock());
      } on Exception {
        // A refused calendar removes nothing; the next round reads again.
      }
    }
    if (_settings.history) await _drain();
    if (_settings.sending) await store.queuePoints();
    final place = _settings.place;
    final result = await flush(store, api, clock: _clock, keepGoing: () => _settings.sending && _settings.place == place,
      folder: folder);
    _status = switch (result.failure) { Failure.refused => SyncStatus.refused, null => SyncStatus.synced, _ => SyncStatus.offline };
    // The stop's own state wins.
    if (!_settings.sending) _status = SyncStatus.idle;
    await _refreshLocal();
    return result.failure == null;
  }

  // Voice notes.

  static const _noMicrophone = 'Relay Everything may not use the microphone. Allow it in the phone\'s settings.';
  static const _microphoneFailed = 'The microphone did not start. Try again.';
  static const _noRecording = 'This recording is not on this phone.';
  static const _tooShort = 'Too short to keep. Nothing was saved.';
  static const _stopFailed = 'The microphone did not stop right. Nothing was saved.';
  static const _notSaved = 'The voice note did not save.';
  static const _noSpeech = 'No speech heard. Nothing was saved.';
  static const _wordsDidNotCome = 'The words did not come. Tap Try again on the note.';

  @override ModelState get speechModel => voice?.model.state ?? ModelState.missing;
  @override double get modelProgress => voice?.model.progress ?? 0;
  @override ModelProblem? get modelProblem => voice?.model.problem;
  @override int get modelBytes => voice?.model.bytes ?? modelSize;
  @override DateTime? get listening => _listening;

  @override
  void askSpeechModel() => voice?.model.ask();

  @override
  void notNowSpeechModel() => voice?.model.notNow();

  @override
  Future<void> getSpeechModel() async {
    final parts = voice;
    if (parts == null) return;
    // Notes kept while the model was away get their words once it is back.
    if (await parts.model.download()) _track(_writePending());
  }

  @override
  Future<void> removeSpeechModel() async {
    final parts = voice;
    if (parts == null) return;
    await parts.transcriber.close();
    await parts.model.remove();
  }

  @override
  Future<String?> startVoiceNote() async {
    final parts = voice;
    if (parts == null || parts.model.state != ModelState.ready || _starting != null || parts.recorder.recording) return null;
    final bool allowed;
    try {
      allowed = await (_starting = parts.recorder.start(newClientId()));
    } catch (_) {
      // The recorder keeps no state from a failed start, so the next press tries again.
      return _microphoneFailed;
    } finally {
      _starting = null;
    }
    if (!allowed) return _noMicrophone;
    // A quick release can end it before this line.
    if (parts.recorder.recording) {
      _listening = parts.recorder.startedAt;
      notifyListeners();
    }
    return null;
  }

  /// Waits for a start still running. A failed start has told the person already, so this does not throw.
  Future<void> _started() async {
    try {
      await _starting;
    } catch (_) {
      // startVoiceNote returned its message.
    }
  }

  @override
  Future<String?> endVoiceNote() async {
    final parts = voice;
    if (parts == null) return null;
    await _started();
    if (!parts.recorder.recording) return null;
    final Recording? recording;
    try {
      recording = await parts.recorder.stop();
    } catch (_) {
      // The recorder has ended and deleted the file all the same.
      return _stopFailed;
    } finally {
      _listening = null;
      notifyListeners();
    }
    if (recording == null) return _tooShort;
    return _keepVoice(recording);
  }

  @override
  Future<void> cancelVoiceNote() async {
    final parts = voice;
    if (parts == null) return;
    await _started();
    try {
      await parts.recorder.cancel();
    } catch (_) {
      // The recorder has ended and deleted the file all the same: nothing is kept.
    } finally {
      _listening = null;
      notifyListeners();
    }
  }

  @override
  Future<void> play(String recording) async {
    final parts = voice;
    if (parts == null) return;
    final file = await parts.recorder.fileOf(recording);
    // Phone backups leave recordings out, so a note restored to a new phone has its words but no recording.
    if (!await file.exists()) return notice(_noRecording);
    await parts.player.play(file);
  }

  /// Shows the note at once, with no words yet, and writes them in the background. Returns the words to show when the
  /// phone could not keep it, such as a full disk; then its recording is deleted too.
  Future<String?> _keepVoice(Recording recording) async {
    final note = LocalNote(clientId: recording.clientId, text: '', createdAt: recording.startedAt, kind: NoteKind.voice,
      audioPath: recording.audioPath, durationMs: recording.length.inMilliseconds, wordsPending: true);
    try {
      await store.addVoiceNote(note);
    } catch (_) {
      try {
        final file = await voice!.recorder.fileOf(recording.audioPath);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // The next open deletes a recording no note keeps.
      }
      return _notSaved;
    }
    await _refreshLocal();
    _track(_write(note));
    return null;
  }

  @override
  Future<void> writeWordsAgain() async {
    if (_wordsFailed.isEmpty) return;
    // Only the failed notes: a note whose words are being written now must not be written twice.
    final failed = Set.of(_wordsFailed);
    _wordsFailed.clear();
    await _refreshLocal();
    _track(_writePending(only: failed));
  }

  void _track(Future<void> job) {
    _writing.add(job);
    job.whenComplete(() => _writing.remove(job));
  }

  /// Ends when every voice note being written has its words or is gone. Tests wait on it.
  @visibleForTesting
  Future<void> wordsWritten() async {
    while (_writing.isNotEmpty) {
      await Future.wait(List.of(_writing));
    }
  }

  /// Writes the words of each voice note still waiting, oldest first, or only of the notes in [only]. With [dropStray],
  /// deletes recordings no note keeps, such as one the app's close cut off while the person still held the button.
  Future<void> _writePending({bool dropStray = false, Set<String>? only}) async {
    final parts = voice;
    if (parts == null) return;
    final pending = await store.pendingWords();
    if (dropStray) {
      final kept = {for (final note in await store.notes()) if (note.audioPath != null) note.audioPath};
      final folder = (await parts.recorder.fileOf(VoiceRecorder.pathOf('x'))).parent;
      if (await folder.exists()) {
        await for (final file in folder.list()) {
          final path = 'voice/${file.uri.pathSegments.last}';
          if (file is! File || kept.contains(path)) continue;
          // A shortcut's recording can land meanwhile: its note is kept before the recording moves here.
          if (await store.keepsRecording(path)) continue;
          await _deleteRecording(file);
        }
      }
    }
    for (final note in pending) {
      if (only == null || only.contains(note.clientId)) await _write(note);
    }
  }

  /// Writes one voice note's words, after the words typed with it. No words: a note with typed words keeps them and its
  /// recording; one without goes with its recording, and the app says it heard no speech. It waits while the model is
  /// away; failed words, or words past the time limit, show *Try again* on the note.
  Future<void> _write(LocalNote note) async {
    final parts = voice;
    if (parts == null) return;
    final file = await parts.recorder.fileOf(note.audioPath ?? VoiceRecorder.pathOf(note.clientId));
    if (!await file.exists()) {
      // Typed words stay, with no recording to write.
      if (note.text.trim().isNotEmpty) return _keepTyped(note);
      await store.dropNote(note.clientId);
      await _refreshLocal();
      return;
    }
    if (parts.model.state != ModelState.ready) return;
    final String words;
    try {
      // The limit counts from when the note before ends or passes its limit, and stops only this note's writing.
      words = await parts.transcriber.words(file, limit: _wordsLimit(Duration(milliseconds: note.durationMs ?? 0)));
    } on Object catch (error, stack) {
      // Any error, an Error too, such as an ArgumentError from the speech engine: the note must never wait silently.
      debugPrint('Voice note ${note.clientId}: the words failed: $error\n$stack');
      final first = _wordsFailed.isEmpty;
      _wordsFailed.add(note.clientId);
      await _refreshLocal();
      if (first && !_disposed) notice(_wordsDidNotCome);
      return;
    }
    if (words.isEmpty) {
      if (note.text.trim().isNotEmpty) return _keepTyped(note);
      await store.dropNote(note.clientId);
      await _deleteRecording(file);
      await _refreshLocal();
      notice(_noSpeech);
      return;
    }
    if (await store.setWords(note.clientId, words, send: _settings.sending)) {
      await _refreshLocal();
      await sync();
    }
  }

  /// Deletes a recording, or does nothing when the sweep for stray recordings deleted it first.
  Future<void> _deleteRecording(File file) async {
    try {
      await file.delete();
    } on PathNotFoundException {
      // Gone already.
    }
  }

  /// Ends a voice note's wait with only the words typed with it, such as a shortcut's label over a silent recording.
  Future<void> _keepTyped(LocalNote note) async {
    if (await store.setWords(note.clientId, '', send: _settings.sending)) {
      await _refreshLocal();
      await sync();
    }
  }

  bool _disposed = false;

  // Words written after the app closed its controller change the store only.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _history?.cancel();
    _drainTimer?.cancel();
    voice?.model.removeListener(notifyListeners);
    super.dispose();
  }
}
