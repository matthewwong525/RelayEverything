import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'data/api.dart';
import 'data/attachments.dart';
import 'data/client_id.dart';
import 'data/connection.dart';
import 'data/note_sync.dart';
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
import 'sync/motion.dart';
import 'sync/native.dart';
import 'sync/photos.dart';
import 'sync/stay_round.dart';
import 'voice/model.dart';
import 'voice/playback.dart';
import 'voice/recorder.dart';
import 'voice/transcriber.dart';

// The tests and older callers read the id maker from here.
export 'data/client_id.dart' show newClientId;

// The first versions kept the server's timeline here. A device key reads nothing now, so load deletes it.
const _oldTimeline = 'timeline';

/// The `state` keys for the last `GET connections` answer, and for the Home headers the person folded.
const connectionsKey = 'connections', foldedKey = 'home.folded';

/// Set once the app asked for motion: a no is final until the person changes it in the phone's settings.
const motionAskedKey = 'motion.asked';

/// The `state` key set once a first voice note starts, so *New note* stops showing *Hold to talk*.
const holdTipKey = 'holdTipSeen';

/// The `state` key set once, at the load that moved to Relay Everything a phone that sent health and places only to its
/// own webhook: Home then says so once, and clearing it removes the key.
const throughServerKey = 'notice.throughServer';

/// After a sync, the names are read again only this long after the last read: they change only on the person's page.
const _namesEvery = Duration(minutes: 10);

/// What voice notes need: the speech model, the microphone, the words and playback. Each runs on this phone.
class VoiceParts {
  const VoiceParts({required this.model, required this.recorder, required this.transcriber, required this.player});

  final SpeechModel model;
  final VoiceRecorder recorder;
  final Transcriber transcriber;
  final SoundPlayer player;
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

/// The app's one Relay: notes in the store, and the key in the vault. Notes stay on this phone; while sending is on,
/// it syncs on open, on a new note, on pull, and every hour in the background.
class RelayController extends Relay {
  RelayController({required this.store, required this.vault, this.places, this.health,
    RelayApi Function(Connection)? apiFor, http.Client Function()? signInClient, WebAuth? webAuth, DateTime Function()? clock,
    WebhookClient Function(Webhook webhook, String installId)? webhookFor, this.schedule, this.voice, this.native, this.folder,
    this.opener, this.share, this.calendar, this.photos, this.network, this.motion, Duration Function(Duration length)? wordsLimit,
    this.platform = RelayPlatform.phone, SoundPlayer? player})
    : _sender = Sender(apiFor, signInClient, webhookFor), _webAuth = webAuth ?? phoneWebAuth, _clock = clock ?? DateTime.now,
      _wordsLimit = wordsLimit ?? wordsLimitOf, _ownPlayer = player {
    voice?.model.addListener(notifyListeners);
    // A recording at its longest ends as if the person let go.
    voice?.recorder.onLongest = (recording) {
      final fix = _takeVoiceFix();
      _listening = null;
      notifyListeners();
      final into = _into;
      _into = null;
      if (recording == null) return notice(_stopFailed);
      unawaited(_keepVoice(recording, fix, into: into).then((problem) => problem == null ? null : notice(problem)));
    };
  }

  final Store store;
  final KeyVault vault;
  /// Where the phone is, and its health store; with none, as on the Mac, location history and health can not turn on.
  final Places? places;
  final HealthSource? health;
  /// The phone app, or the Mac app, which keeps notes the same way with the computer page's layout.
  @override
  final RelayPlatform platform;
  /// The phone's calendars; with none, the calendar can not turn on.
  final CalendarSource? calendar;
  /// Turns the hourly background sync on or off.
  final Future<void> Function(bool on)? schedule;
  /// Voice notes; with none, the app has typed notes only.
  final VoiceParts? voice;
  /// Plays recordings with no [voice], as on the Mac.
  final SoundPlayer? _ownPlayer;
  SoundPlayer? get _player => voice?.player ?? _ownPlayer;
  /// The iPhone's Swift side, which keeps places and wakes the app while it is closed; null on Android.
  final NativeBackground? native;
  /// The app's support folder, where a note's files are kept in `attachments/`; with none, notes take no files.
  final Future<Directory> Function()? folder;
  /// Opens a note's file; with none, the app says it can not.
  final FileOpener? opener;
  /// The App Group the iPhone's share card writes to; null on Android, where the share card is this app's own window.
  final ShareGroup? share;
  /// The photo library and the network kind; with either missing, *Photos* can not turn on.
  final PhotoSource? photos;
  final Network? network;
  /// The motion sensors, for a trip's mode; with none, the mode comes from speed.
  final Motion? motion;
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
  StreamSubscription<Link>? _links;
  /// The phone's network as it last changed; null until it does.
  Link? _link;
  Timer? _drainTimer;
  List<Entry> _deleted = const [];
  /// Notes whose delete the store is still writing: the list leaves them out at once, before the store has it.
  final _moving = <String>{};
  /// When this run last deleted for good the notes past their 30 days in *Recently Deleted*.
  DateTime? _purgedAt;
  SendState _healthSent = const SendState(), _pointsSent = const SendState(), _calendarSent = const SendState();
  List<PhoneCalendar> _calendars = const [];
  Connections? _connections;
  DateTime? _namesAt;
  Set<String> _folded = const {};
  bool _holdTipSeen = false;
  bool _throughServer = false;
  Future<void>? _syncing;
  /// A pull of notes asked for and not yet read, and the one reading now; [pullNotes] ends with them.
  Completer<void>? _pull, _reading;
  bool _again = false;
  DateTime? _listening;
  Future<bool>? _starting;
  final _writing = <Future<void>>{};
  // Voice notes whose words failed in this run of the app, each with its reason. The next open, a return to the app, or
  // *Try again* writes them again.
  final _wordsFailed = <String, String>{};
  // Voice notes the app told about as failed, for the app's life: a note that fails again on each return tells once.
  final _toldWordsFailed = <String>{};
  // True once a note's failure showed the notice since the last try again: several notes that fail together tell once.
  bool _toldSinceAgain = false;
  // Each new note's location point, while its fix is taken: [settled] waits on them.
  final _pointing = <Future<void>>{};
  // The fix an in-app voice note took as it started; it becomes a point only if the note is kept.
  Future<Pin?>? _voiceFix;
  String? _root;

  @override bool get connected => _connection != null;
  @override String? get server => _connection?.server;
  @override List<Entry> get entries => _entries;
  @override List<Entry> get deleted => _deleted;
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
  @override Connections? get connections => _connections;
  @override Set<String> get folded => _folded;
  @override bool get holdTipSeen => _holdTipSeen;
  @override bool get throughServerNotice => _throughServer;

  Outbound? get _api => _sender.api(_settings, connection: _connection, webhook: _webhook, installId: _installId);

  /// Moves what waits to where [settings] sends, in one step.
  Future<void> _moveOutbox(Settings settings) => store.moveOutbox(destinationOf(settings.place));

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
    // A phone that sent health, places, the calendar and photos only to its own webhook now sends them to Relay
    // Everything, with what waits: Home says so once. The flag goes first, as the save below drops the old choice.
    if (_settings.sending && Settings.hadPrivateWebhook(saved)) await store.set(throughServerKey, 'true');
    // The first version's settings, read once by the upgrade rule, are saved in today's shape.
    if (_settings.encode() != saved) await store.set(settingsKey, _settings.encode());
    if (await store.outboxMoves(destinationOf(_settings.place))) await _moveOutbox(_settings);
    _throughServer = await store.get(throughServerKey) != null;
    await store.remove(_oldTimeline);
    _connections = Connections.decode(await store.get(connectionsKey));
    _folded = {for (final header in jsonDecode(await store.get(foldedKey) ?? '[]') as List) if (header is String) header};
    _holdTipSeen = await store.get(holdTipKey) != null;
    await _tellNative();
    await _tellShare();
    if (watch && _settings.history) _startHistory();
    if (watch) await _watchMotion();
    if (watch) _watchNetwork();
    _root = (await folder?.call())?.path;
    // A shortcut that ran while the app could not answer, or the Apple Watch, left its note in the inbox.
    await drainShortcutsInbox();
    await _drainShare(refresh: false);
    await voice?.model.load();
    if (_settings.calendar) await _readCalendars();
    await _refreshLocal();
    // A voice note whose words the app's close cut short gets them now, from its kept recording.
    _track(_writePending(strayBefore: DateTime.now()));
  }

  /// Keeps each note in the shortcuts inbox, from Shortcuts or the Apple Watch, with no point: at load, each return to
  /// the app, and each `inboxChanged` from Swift. One drain runs at a time; a call during one makes it look again after.
  Future<void> drainShortcutsInbox() {
    final running = _inboxRun;
    if (running != null) {
      _inboxAgain = true;
      return running;
    }
    return _inboxRun = _drainShortcuts().whenComplete(() => _inboxRun = null);
  }

  Future<void>? _inboxRun;
  bool _inboxAgain = false;

  Future<void> _drainShortcuts() async {
    final root = _root;
    if (root == null) return;
    do {
      _inboxAgain = false;
      await drainInbox(Directory(root), _keepInboxRequest);
    } while (_inboxAgain);
  }

  Future<void> _keepInboxRequest(InboxRequest request) async {
    final recording = request.recording;
    if (recording == null) {
      await keepNote(request.text, files: request.files, clientId: request.id, createdAt: request.createdAt, point: false);
    } else {
      await keepRecording(request.text, recording: recording.path, durationMs: recording.durationMs, clientId: request.id,
        createdAt: request.createdAt, point: false, fromWatch: request.fromWatch);
    }
  }

  /// Keeps each note the iPhone's share card left, with no point. Load, each return to the app, and the hourly round
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

  /// Each return to the app: keeps what the inbox and the share card hold, writes the words of each note whose words
  /// failed again, shows what another engine added to the store, such as Android's share window, then sends what waits.
  Future<void> resume() async {
    await drainShortcutsInbox();
    await _drainShare(refresh: false);
    await writeWordsAgain();
    await _refreshLocal();
    await pullNotes();
  }

  Entry _entryOfLocal(LocalNote note) => Entry(id: note.clientId, text: note.text, at: note.createdAt,
    sent: note.mine && note.sentAt != null, waiting: _settings.sending && note.sentAt == null && note.queued,
    recordings: [for (final (index, file) in note.attachments.indexed) if (file.recording)
      _recordingOf(note, file, note.attachments.take(index).where((other) => !other.recording).length)],
    files: [for (final file in note.attachments) if (!file.recording) EntryFile(id: file.id, name: file.name, type: file.type,
      size: file.size, path: file.path.isEmpty ? '' : fullPath(file.path))],
    from: note.mine ? null : note.device ?? 'elsewhere', pinned: note.pinned, deletedAt: note.deletedAt);

  /// A recording on this phone plays from its path; one only in the person's space by its id, which downloads it. One
  /// whose bytes are still on the phone that made it is not ready.
  EntryRecording _recordingOf(LocalNote note, Attachment file, int filesBefore) => EntryRecording(id: file.id,
    filesBefore: filesBefore, ready: file.path.isNotEmpty || file.ready,
    recording: file.path.isEmpty ? file.id : file.path, length: Duration(milliseconds: file.lengthMs ?? 0),
    transcript: file.transcript, top: file.top, failed: _wordsFailed.containsKey(file.id), why: _wordsFailed[file.id],
    writing: file.transcript == null && note.mine && file.path.isNotEmpty && !file.hereOnly &&
      !_wordsFailed.containsKey(file.id));

  /// The app's support folder, once [load] has read it.
  String? get filesRoot => _root;

  /// A path from the support folder, made full.
  String fullPath(String path) => _root == null || path.startsWith('/') ? path : '$_root/$path';

  /// The list shows this phone's notes and those a pull brought, newest first.
  Future<void> _refreshLocal() async {
    // At the start, and once a day while the app stays open: a note 30 days in *Recently Deleted* goes for good.
    final now = _clock();
    if (_purgedAt == null || now.difference(_purgedAt!) >= const Duration(days: 1)) {
      _purgedAt = now;
      await store.purgeDeleted(now);
    }
    final notes = await store.notes();
    _deleted = [for (final note in await store.deletedNotes()) _entryOfLocal(note)];
    _waiting = await store.waiting();
    _healthSent = SendState(at: await store.sentAt(sentHealth), waiting: await store.waitingReadings());
    _pointsSent = SendState(at: await store.sentAt(sentPoints), waiting: await store.waitingPoints());
    _problem = _problemOf(await store.get(webhookProblemKey));
    _calendarSent = SendState(at: await store.sentAt(sentCalendar), waiting: await store.waitingEvents());
    _entries = [for (final note in notes) if (!_moving.contains(note.clientId)) _entryOfLocal(note)];
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
      back = await _webAuth(signInUrl(server, challengeOf(verifier), phoneName()));
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
    // The names and the notes from elsewhere came from the server before, which may be another person's space.
    _namesAt = null;
    await _keepConnections(null);
    // A pull already reading the old server finishes first, so nothing it read lands after the delete.
    await _reading?.future;
    await store.dropSynced();
    await _refreshLocal();
    return null;
  }

  @override
  Future<int> earlierNotes({SendPlace? to}) => store.earlierCount(fromWebhook: _fromWebhook(to ?? _settings.place));

  /// True when the phone moves from the person's own webhook to a Relay Everything server: the notes that went only to
  /// the webhook are not on the person's space, so they count as earlier notes.
  bool _fromWebhook(SendPlace to) => _settings.place == SendPlace.webhook && to == SendPlace.server;

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
    final fromWebhook = _fromWebhook(to);
    final next = _settings.copyWith(sending: true, place: to);
    await _moveOutbox(next);
    if (sendEarlier) await store.queueEarlier(fromWebhook: fromWebhook);
    // A pin made while sending was off goes now: no pull would bring that note back to send it.
    if (to == SendPlace.server) await store.queueUnsentPins();
    // The photos waiting on this phone go to the new place too, as the outbox does.
    await _saveSettings(next);
    await _refreshLocal();
    _syncAfter();
    return null;
  }

  /// Starts a round after the one running, or now.
  void _syncAfter() {
    final running = _syncing;
    unawaited(running == null ? sync() : running.then((_) => sync()));
  }

  @override
  Future<void> dismissThroughServerNotice() async {
    if (!_throughServer) return;
    _throughServer = false;
    notifyListeners();
    await store.remove(throughServerKey);
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
    await _watchMotion();
    // A round already sending finishes first, so nothing it read lands after the drop.
    await _syncing;
    await store.dropReadings();
    await dropPhotoQueue(store);
    _status = SyncStatus.idle;
    await _refreshLocal();
  }

  @override
  Future<void> disconnect() async {
    await stopSending();
    await vault.forget();
    _connection = null;
    // A pull already reading finishes first, so nothing it read lands after the delete.
    await _reading?.future;
    await store.dropSynced();
    await _tellShare();
    await _refreshLocal();
  }

  Future<void> _saveSettings(Settings settings) async {
    _settings = settings;
    await store.set(settingsKey, settings.encode());
    // Off, or sending to the person's own webhook: the phone keeps no names from the server.
    if (_sender.reader(settings, connection: _connection) == null) {
      _namesAt = null;
      if (_connections != null) await _keepConnections(null);
    }
    await schedule?.call(settings.history || settings.health || settings.calendar || settings.photos);
    await _tellNative();
    await _tellShare();
    notifyListeners();
  }

  @override
  Future<void> refreshConnections() async {
    final reader = _sender.reader(_settings, connection: _connection);
    if (reader == null) return;
    _namesAt = _clock();
    Connections? found;
    try {
      found = Connections.fromJson(await reader.connections());
    } on ApiException catch (error) {
      // With no signal the last answer stays. A server from before this route refuses it: then no names show.
      if (error.failure == Failure.offline) return;
    }
    // Sending can stop while the answer comes: then the phone keeps nothing.
    if (_sender.reader(_settings, connection: _connection) != null) await _keepConnections(found);
  }

  @override
  Future<String?> signOutPhone(String id) async {
    final reader = _sender.reader(_settings, connection: _connection);
    if (reader == null) return 'Sign in to Relay Everything first.';
    try {
      await reader.post('devices/off', {'id': id});
    } on ApiException catch (error) {
      return switch (error.failure) {
        Failure.offline => 'Relay Everything did not answer. Check your connection and try again.',
        _ => 'Relay Everything did not sign out this phone. Sign it out on your Relay Everything page.',
      };
    }
    await refreshConnections();
    return null;
  }

  Future<void> _keepConnections(Connections? value) async {
    _connections = value;
    value == null ? await store.remove(connectionsKey) : await store.set(connectionsKey, value.encode());
    notifyListeners();
  }

  @override
  Future<void> setFolded(String header, bool folded) async {
    _folded = folded ? {..._folded, header} : ({..._folded}..remove(header));
    notifyListeners();
    await store.set(foldedKey, jsonEncode(_folded.toList()..sort()));
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

  static const _sendFirst = 'Sign in first, in Settings.';

  @override
  Future<void> setAppearance(Appearance appearance) => _saveSettings(_settings.copyWith(appearance: appearance));

  @override
  Future<String?> setHistory(bool on) async {
    if (on && !_settings.sending) return _sendFirst;
    if (on && !(await places?.allow(always: true) ?? false)) return 'Relay Everything may not read your location all the time. Allow it in the phone\'s settings.';
    if (on && _settings.locationSend != LocationSend.points) await _askMotion();
    await _saveSettings(_settings.copyWith(history: on));
    if (on) {
      _startHistory();
    } else {
      await _stopHistory();
      // A round already stepping finishes first, so nothing it read lands after the drop.
      await _syncing;
      await _endTimeline();
    }
    await _watchMotion();
    return null;
  }

  @override
  Future<String?> setLocationSend(LocationSend send) async {
    final before = _settings.locationSend;
    if (send == before) return null;
    if (_settings.history && before == LocationSend.points) await _askMotion();
    await _saveSettings(_settings.copyWith(locationSend: send));
    await _syncing;
    String? said;
    if (send == LocationSend.stays) {
      if (await store.dropPoints() > 0) said = 'The points still waiting on this phone were dropped.';
    }
    if (send == LocationSend.points) await _endTimeline();
    await _watchMotion();
    await _refreshLocal();
    return said;
  }

  /// Stops making stays: with sending on, the open stay goes as ended first, so the server does not keep it ongoing.
  Future<void> _endTimeline() => _settings.sending ? store.closeTimeline() : store.dropTimeline();

  /// Asks for motion once, when location history starts to make stays and trips. A no leaves the mode to speed.
  Future<void> _askMotion() async {
    final sensors = motion;
    if (sensors == null || await store.get(motionAskedKey) != null) return;
    try {
      await sensors.allow();
    } on Exception {
      // No motion sensors: the mode comes from speed.
    } finally {
      await store.set(motionAskedKey, '1');
    }
  }

  /// While the app is open, notes that wait send as soon as the connection comes back, with no tap: from no network, or
  /// after a round that found the phone offline. With sending off, or nothing waiting, nothing leaves.
  void _watchNetwork() {
    final kind = network;
    if (kind == null || _links != null) return;
    _links = kind.changes().listen((link) {
      final back = link != Link.none && (_link == Link.none || _status == SyncStatus.offline);
      _link = link;
      if (back && _settings.sending && _waiting > 0) unawaited(sync());
    }, onError: (_) {});
  }

  /// Tells Android to keep motion changes only while location history makes stays and trips.
  Future<void> _watchMotion() async {
    try {
      await motion?.watch(_settings.stays);
    } on Exception {
      // No Google Play services, or a test's engine: the mode comes from speed.
    }
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
      _history ??= places?.history().listen((point) => store.addPoint(point, send: _settings.locationSend), onError: (_) {});
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
      final moved = await drainPoints(store, swift, name: _settings.sending ? places?.nameOf : null, send: _settings.locationSend);
      if (moved > 0) await _refreshLocal();
    } on Exception {
      // Swift empties its file as it answers, but the points are in the store before any name lookup, so a failure
      // here costs at most a name.
    }
  }

  @override
  Future<String?> setHealth(bool on) async {
    if (on && !_settings.sending) return _sendFirst;
    if (on && !(await health?.allow() ?? false)) return 'Relay Everything may not read your health data. Allow it in the phone\'s health settings.';
    // Health starts from now: the next rounds read new readings, and the last 90 days a week at a time.
    await (on ? startHealth(store, _clock()) : stopHealth(store));
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
      await health?.allow();
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

  static const _noPhotos = 'Photo access is off. Turn it on in the phone\'s Settings.';

  @override
  Future<String?> setPhotos(bool on) async {
    if (on == _settings.photos) return null;
    if (!on) {
      await _saveSettings(_settings.copyWith(photos: false, photosOnMobileData: false));
      // A round already reading or sending finishes first, so nothing it queued stays after the drop.
      await _syncing;
      await dropPhotoQueue(store);
      return null;
    }
    if (!_settings.sending) return _sendFirst;
    final source = photos;
    if (source == null || network == null || !await source.allow()) return _noPhotos;
    // Photos start from now: the library from before never goes.
    await dropPhotoQueue(store);
    final since = '${_clock().millisecondsSinceEpoch}';
    await store.set(photosSince, since);
    await store.set(photosAfter, since);
    await _saveSettings(_settings.copyWith(photos: true));
    unawaited(sync());
    return null;
  }

  @override
  Future<String?> setPhotosOnMobileData(bool on) async {
    if (on && !_settings.photos) return 'Turn on Photos first.';
    await _saveSettings(_settings.copyWith(photosOnMobileData: on));
    if (on) unawaited(sync());
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

  /// Keeps, shows and queues the note at once; Save never waits for a fix. With location history on, its point follows
  /// when the phone has a fix or gives up (up to 10 s).
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
  Future<void> pinNote(String id, bool pinned) async {
    final server = _settings.sending && _settings.place == SendPlace.server;
    if (!await store.pinNote(id, pinned, send: server, at: _clock())) return;
    await _refreshLocal();
    if (server) unawaited(sync());
  }

  @override
  Future<Emptied> dropEmptyNote(String id) async {
    if (!await store.isBare(id)) return Emptied.kept;
    if (!await store.dropEmptyNote(id)) {
      await deleteForever(id);
      return Emptied.deleted;
    }
    await _refreshLocal();
    notifyListeners();
    return Emptied.dropped;
  }

  @override
  Future<void> deleteNote(String id) async {
    // Before any wait: a swiped row must leave the list in the same frame.
    _moving.add(id);
    _entries = [for (final entry in _entries) if (entry.id != id) entry];
    notifyListeners();
    final moved = await store.deleteNote(id, _clock());
    _moving.remove(id);
    if (moved) deletedNow(id);
    await _refreshLocal();
    if (moved) unawaited(sync());
  }

  @override
  Future<void> recover(String id) async {
    if (!await store.recover(id)) return;
    await _refreshLocal();
    unawaited(sync());
  }

  @override
  Future<void> deleteForever(String id) async {
    _deleted = [for (final entry in _deleted) if (entry.id != id) entry];
    notifyListeners();
    final queued = await store.deleteForever(id);
    await _refreshLocal();
    if (queued) unawaited(sync());
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
  /// note, so a shortcut that ran twice keeps one. While location history is on, the note adds one location point at
  /// its time; [point] false adds none, for a note made earlier than now.
  Future<Kept> keepNote(String text, {List<NewFile> files = const [], String? clientId, DateTime? createdAt,
    bool point = true, bool sendNow = true}) async {
    final id = clientId ?? newClientId();
    if (await store.hasNote(id)) {
      return Kept([...await store.notes(), ...await store.deletedNotes()].firstWhere((note) => note.clientId == id), null);
    }
    final check = checkFiles(const [], files);
    final (attachments, problems) = await _keepFiles(check.kept, check.problem);
    final words = text.trim();
    if (words.isEmpty && attachments.isEmpty) return Kept(null, [...problems, _nothing].join(' '));
    final note = LocalNote(clientId: id, text: words, createdAt: createdAt ?? _clock(), attachments: attachments);
    await store.addNote(note, send: _settings.sending);
    await _refreshLocal();
    if (sendNow) unawaited(sync());
    if (point) _pointAt(note.createdAt);
    return Kept(note, problems.isEmpty ? null : problems.join(' '));
  }

  /// Keeps a shortcut's recording, a WAV Swift left at [recording] from the support folder, as a voice note that waits
  /// for the recording's words, with [text], the words given with it, as its text. The note is kept before its
  /// recording moves to `attachments/<id>.wav`, so a second drain of the same request finds it. It adds a point as
  /// [keepNote] does, and a [clientId] already kept gives back that note. The words are written now when this engine
  /// has the voice parts, else at the app's next open. A recording that is not there keeps the given words alone, or
  /// nothing. [fromWatch] marks a note the Apple Watch handed over: it is never deleted for having no words.
  Future<Kept> keepRecording(String text, {required String recording, required int durationMs, String? clientId,
    DateTime? createdAt, bool point = true, bool fromWatch = false}) async {
    final id = clientId ?? newClientId();
    if (await store.hasNote(id)) {
      return Kept([...await store.notes(), ...await store.deletedNotes()].firstWhere((note) => note.clientId == id), null);
    }
    final root = _root ?? (await folder?.call())?.path;
    final source = File('$root/$recording');
    if (root == null || !await source.exists()) return keepNote(text, clientId: id, createdAt: createdAt, point: point);
    final file = _newRecording(await source.length(), durationMs, top: true);
    final note = LocalNote(clientId: id, text: text.trim(), createdAt: createdAt ?? _clock(), kind: NoteKind.voice,
      wordsPending: true, fromWatch: fromWatch, attachments: [file]);
    await store.addVoiceNote(note);
    try {
      await _moveTo(source, '$root/${file.path}');
    } on FileSystemException {
      await store.dropNote(id);
      rethrow;
    }
    await _refreshLocal();
    if (point) _pointAt(note.createdAt);
    if (voice != null) _track(_write(note, file));
    return Kept(note, null);
  }

  /// A new recording's file row, at `attachments/<id>.wav`, whose words are not written yet.
  static Attachment _newRecording(int size, int lengthMs, {bool top = false}) {
    final id = newClientId();
    return Attachment(id: id, name: 'Recording.wav', type: 'audio/wav', size: size, path: 'attachments/$id.wav',
      lengthMs: lengthMs, wordsPending: true, top: top);
  }

  static Future<void> _moveTo(File source, String target) async {
    await File(target).parent.create(recursive: true);
    await source.rename(target);
  }

  /// Copies a file into `attachments/<id><.ext>`, or moves the app's own copy there. Null when it could not.
  Future<Attachment?> _keepFile(NewFile file) async {
    final root = _root ?? (await folder?.call())?.path;
    if (root == null) return null;
    return keepFile(root, file, newClientId());
  }

  /// Ends when each new note's point is kept, and the sync after it is done. Shortcuts waits on it, so a note goes
  /// before the phone puts the app away.
  Future<void> settled() async {
    while (_pointing.isNotEmpty) {
      await Future.wait(List.of(_pointing));
    }
    await _syncing;
  }

  static const _noFile = 'This file is not on this phone.';
  static const _noApp = 'No app on this phone opens this file.';
  static const _sendToDownload = 'Sign in to Relay Everything to download this file.';
  static const _notDownloaded = 'The file did not download. Try again.';

  @override
  Future<void> openFile(EntryFile file) async {
    final found = file.onPhone ? File(file.path) : await _download(file);
    if (found == null) return;
    if (!await found.exists()) return notice(_noFile);
    final open = opener;
    if (open == null || !await open(found, file.type)) notice(_noApp);
  }

  /// Downloads one file of a note from elsewhere into `attachments/`, or a ring note's recording, and keeps its place.
  Future<File?> _download(EntryFile file) async => (await _downloadTo(file))?.$1;

  /// [_download], with the file's path from the support folder.
  Future<(File, String)?> _downloadTo(EntryFile file) async {
    final root = _root, api = _sender.reader(_settings, connection: _connection);
    if (root == null || api == null) {
      notice(_sendToDownload);
      return null;
    }
    final audio = file.id.startsWith(recordingPrefix);
    final path = 'attachments/${file.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-')}${extensionOf(file.name)}';
    try {
      final bytes = await api.download(audio ? file.id.substring(recordingPrefix.length) : file.id, audio: audio);
      final target = File('$root/$path');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes);
      await store.fileKept(file.id, path);
      await _refreshLocal();
      return (target, path);
    } on ApiException {
      notice(_notDownloaded);
    } on FileSystemException {
      notice(_notDownloaded);
    }
    return null;
  }

  /// While location history is on, takes one fix and keeps it as a location point at a new note's time [at], then
  /// sends. Off, it reads no place.
  void _pointAt(DateTime at) {
    if (_settings.history) _point(at, _here());
  }

  /// One fix of where the phone is now; null when there is none.
  Future<Pin?> _here() async {
    try {
      return await places?.here(name: _settings.sending);
    } on Exception {
      return null;
    }
  }

  /// Keeps [fix] as the point at [at], and [settled] waits for it.
  void _point(DateTime at, Future<Pin?> fix) {
    final job = _pointThenSync(at, fix);
    _pointing.add(job);
    job.whenComplete(() => _pointing.remove(job));
  }

  Future<void> _pointThenSync(DateTime at, Future<Pin?> here) async {
    try {
      final fix = await here;
      // History may have turned off while the fix was taken.
      if (fix == null || !_settings.history) return;
      await store.addPoint(Pin(at: at, lat: fix.lat, lon: fix.lon, accuracy: fix.accuracy, place: fix.place),
        send: _settings.locationSend);
    } on Exception {
      // No fix: no point is kept.
      return;
    }
    await _refreshLocal();
    await sync();
  }

  /// One sync at a time; a second call waits for the one running. With sending off it does nothing. A call while a round
  /// runs asks for one more round after it, because that round read the outbox before the call's note was queued; it
  /// also stops the health, places, calendar and photos of the round running at their next upload, so the note goes
  /// first.
  @override
  Future<void> sync() {
    final running = _syncing;
    if (running != null) {
      _again = true;
      return running;
    }
    return _syncing = _rounds().whenComplete(() => _syncing = null);
  }

  /// Sends this phone's notes, then reads the notes changed elsewhere, and ends there: the round goes on with health,
  /// places, the calendar and photos after it. Calls before the read starts share it.
  @override
  Future<void> pullNotes() {
    final pull = _pull ??= Completer<void>();
    unawaited(sync());
    return pull.future;
  }

  /// Ends the pull asked for, read or not.
  void _endPull(Completer<void>? pull) {
    if (pull != null && !pull.isCompleted) pull.complete();
  }

  /// Runs rounds until no call asked for another, or a round could not send the notes. Each round sends the notes and
  /// pulls first, then health, places, the calendar and photos; a call or a pull that comes in the second part stops it,
  /// and the next round starts with the notes again. After a full send, the names of what the person connected are read
  /// again, at most each [_namesEvery].
  Future<void> _rounds() async {
    try {
      while (true) {
        _again = false;
        final emptied = await _notesPart();
        // Also when the notes could not go, such as after a note turned down holds the rest: then no round follows, so a
        // call that came does not stop it.
        await _dataPart(yieldToNotes: emptied);
        if (!emptied || !_settings.sending) break;
        if (_again || _pull != null) continue;
        final namesAt = _namesAt;
        if (namesAt == null || _clock().difference(namesAt) >= _namesEvery) await refreshConnections();
        // A call while the names were read gets its round.
        if (!_again && _pull == null) break;
      }
    } finally {
      // A pull this round could not read, such as with no signal: it ends with the round, so no wait is left open.
      final pull = _pull;
      _pull = null;
      _endPull(pull);
    }
  }

  /// The notes part of a round: sends this phone's notes, their changes, deletes and files, then reads the notes changed
  /// elsewhere when a pull waits. The line on Home comes from this part alone. True when the notes' uploads emptied.
  Future<bool> _notesPart() async {
    final api = _api;
    if (api == null) return false;
    _status = SyncStatus.syncing;
    notifyListeners();
    final place = _settings.place;
    // A switch of place while the round runs stops it at its next upload; a new round follows.
    final result = await flush(store, api, clock: _clock, notes: true, folder: folder,
      keepGoing: () => _settings.sending && _settings.place == place);
    _status = switch (result.failure) { Failure.refused => SyncStatus.refused, null => SyncStatus.synced, _ => SyncStatus.offline };
    // The stop's own state wins.
    if (!_settings.sending) _status = SyncStatus.idle;
    await _refreshLocal();
    // The pull waiting from here; one asked for while it reads waits for the next round.
    final pull = _reading = _pull;
    _pull = null;
    try {
      // Only after the notes' uploads emptied, so this phone's own changes are on the server before it reads.
      if (pull != null && _status == SyncStatus.synced) {
        try {
          await syncNotes(store, _sender, settings: _settings, connection: _connection, editing: openNote, onPage: _refreshLocal);
        } on ApiException catch (error) {
          _status = error.failure == Failure.refused ? SyncStatus.refused : SyncStatus.offline;
          notifyListeners();
        }
      }
    } finally {
      _reading = null;
      _endPull(pull);
    }
    return result.failure == null;
  }

  /// The second part of a round: health, the calendar, the points, stays and trips, their uploads, and photos. It never
  /// changes the line on Home, which is about notes; a failure here waits for a later round. With [yieldToNotes], it
  /// stops at its next read or upload while a note or a pull waits, so they go first in the next round.
  Future<void> _dataPart({required bool yieldToNotes}) async {
    final api = _api;
    if (api == null) return;
    final place = _settings.place;
    // Sending can turn off, the place can change, and a note or a pull can come while it runs: from then on it reads,
    // queues and sends nothing more.
    bool still() => _settings.sending && _settings.place == place && !(yieldToNotes && (_again || _pull != null));
    final healthSource = health;
    if (still() && _settings.health && healthSource != null) {
      try {
        await syncHealth(store, healthSource, now: _clock());
      } on Exception {
        // The health store can be closed for a while, such as on a locked iPhone; the next round reads again.
      }
    }
    final source = calendar;
    if (still() && _settings.calendar && source != null) {
      try {
        await syncCalendar(store, source, _settings, now: _clock());
      } on Exception {
        // A refused calendar removes nothing; the next round reads again.
      }
    }
    if (still() && _settings.history) await _drain();
    if (still() && _settings.stays) {
      try {
        await syncStays(store, _settings, motion: motion, now: _clock(),
          namer: stayNamer(_settings, places: places, native: native, calendar: calendar));
      } on Exception {
        // The points stay in the store, and the next round steps them again.
      }
    }
    if (still() && _settings.locationSend != LocationSend.stays) await store.queuePoints();
    // To the same place as the notes, after them, so an upload here that fails holds back no note.
    final data = !still() ? const FlushResult()
      : await flush(store, api, clock: _clock, keepGoing: still, folder: folder, notes: false);
    // New photos, as in the background round: after the outbox, so a photo waiting for Wi-Fi holds back nothing else.
    // A refused photo with a key that still answers, such as on an older server with no photos, comes back as null.
    Failure? photoFailure;
    final library = photos;
    final kind = network;
    if (still() && _settings.photos && library != null && kind != null) {
      photoFailure = await syncPhotos(store, api, library, kind, settings: _settings, send: data.failure == null,
        now: _clock(), keepGoing: () async => _settings.photos && still());
    }
    // A turned-off key refuses the notes too, so Home says so, though no note waited; any other failure here waits.
    if ((data.failure ?? photoFailure) == Failure.refused) _status = SyncStatus.refused;
    if (!_settings.sending) _status = SyncStatus.idle;
    await _refreshLocal();
  }

  // Voice notes.

  static const _noMicrophone = 'Relay Everything may not use the microphone. Allow it in the phone\'s settings.';
  static const _microphoneFailed = 'The microphone did not start. Try again.';
  static const _noRecording = 'This recording is not on this phone.';
  static const _tooShort = 'Too short to keep. Nothing was saved.';
  static const _stopFailed = 'The microphone did not stop right. Nothing was saved.';
  static const _notSaved = 'The voice note did not save.';
  static const _full = 'This note holds $maxFiles files already. Nothing was recorded.';
  static const _noSpeech = 'No speech heard. Nothing was saved.';
  static const _wordsDidNotCome = 'The words did not come. Tap Try again on the note.';

  @override ModelState get speechModel => voice?.model.state ?? ModelState.missing;
  @override double get modelProgress => voice?.model.progress ?? 0;
  @override ModelProblem? get modelProblem => voice?.model.problem;
  @override int get modelBytes => voice?.model.bytes ?? modelSize;
  @override DateTime? get listening => _listening;
  @override Stream<double>? get level => _listening == null ? null : voice?.recorder.levels;

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
  Future<String?> startVoiceNote({String? into}) async {
    final parts = voice;
    if (parts == null || parts.model.state != ModelState.ready || _starting != null || parts.recorder.recording) return null;
    if (into != null && (await store.attachmentsOf(into)).length >= maxFiles) return _full;
    _into = into;
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
    // A recording can last 5 minutes: the fix at its start is where the note was made.
    _voiceFix = _settings.history ? _here() : null;
    if (!_holdTipSeen) {
      _holdTipSeen = true;
      try {
        await store.set(holdTipKey, 'true');
      } catch (_) {
        // The voice note records all the same; the tip then shows again at the next open.
      }
    }
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
    final fix = _takeVoiceFix();
    if (!parts.recorder.recording) return null;
    final into = _into;
    _into = null;
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
    return _keepVoice(recording, fix, into: into);
  }

  /// The note a recording started with *Record* goes into; null for a new voice note.
  String? _into;

  /// The fix the voice note took as it started, now that it ends; a note that is not kept drops it.
  Future<Pin?>? _takeVoiceFix() {
    final fix = _voiceFix;
    _voiceFix = null;
    return fix;
  }

  @override
  Future<void> cancelVoiceNote() async {
    final parts = voice;
    if (parts == null) return;
    await _started();
    _voiceFix = null;
    _into = null;
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
    final player = _player;
    if (player == null) return;
    var path = recording;
    // A recording only in the person's space, named by its id, downloads first.
    if (!recording.contains('/')) {
      final file = [for (final note in await store.notes()) ...note.attachments].where((file) => file.id == recording).firstOrNull;
      if (file == null) return;
      final got = await _downloadTo(EntryFile(id: file.id, name: file.name, type: file.type, size: file.size));
      if (got == null) return;
      path = got.$2;
    }
    final file = await _fileOf(path);
    // Phone backups leave recordings out, so a note restored to a new phone may have its words but no recording.
    if (!await file.exists()) return notice(_noRecording);
    await player.play(path, file.uri);
  }

  /// A recording's file, from its path in the support folder.
  Future<File> _fileOf(String path) async {
    final parts = voice;
    return parts == null ? File(fullPath(path)) : parts.recorder.fileOf(path);
  }

  @override
  ValueListenable<Playback?> get playback => _player ?? noPlayback;

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seek(Duration at) async => _player?.seek(at);

  /// Reads the recording's waves away from the page, so a 5-minute recording does not stall it.
  @override
  Future<List<double>> waveOf(String recording, {int bars = 48}) async {
    if (!recording.contains('/')) return const [];
    try {
      return await compute(readWave, ((await _fileOf(recording)).path, bars));
    } on Exception {
      return const [];
    }
  }

  @override
  Future<void> editTranscript(String recording, String transcript) async {
    if (!await store.setTranscript(recording, transcript.trim(), send: _settings.sending, at: _clock(), edit: true)) return;
    await _refreshLocal();
    if (_settings.sending) unawaited(sync());
  }

  /// Shows the recording at once in a new voice note, or in note [into], with no words yet, and writes them in the
  /// background. Returns the words to show when the phone could not keep it, such as a full disk; then its recording is
  /// deleted too. A kept new note adds [fix], the fix taken as it started, as its point.
  Future<String?> _keepVoice(Recording recording, Future<Pin?>? fix, {String? into}) async {
    final parts = voice!;
    final source = await parts.recorder.fileOf(recording.audioPath);
    final File target;
    final LocalNote note;
    final Attachment file;
    var full = false;
    try {
      file = _newRecording(await source.length(), recording.length.inMilliseconds, top: into == null);
      target = await _fileOf(file.path);
      await _moveTo(source, target.path);
    } catch (_) {
      await _deleteQuietly(source);
      return _notSaved;
    }
    try {
      if (into != null && await store.hasNote(into)) {
        full = !await store.addRecording(into, file);
        if (full) throw StateError('full');
        note = (await store.notes()).firstWhere((note) => note.clientId == into);
      } else {
        // A new note from the bars has no words yet, so the recording makes it, under where the words go.
        note = LocalNote(clientId: into ?? recording.clientId, text: '', createdAt: recording.startedAt,
          kind: into == null ? NoteKind.voice : NoteKind.typed, wordsPending: true, attachments: [file]);
        await store.addVoiceNote(note);
      }
    } catch (_) {
      await _deleteQuietly(target);
      return full ? _full : _notSaved;
    }
    await _refreshLocal();
    _track(_write(note, file));
    if (fix != null && into == null) _point(note.createdAt, fix);
    return null;
  }

  /// Deletes [file] if it is there; the next open deletes a recording no note keeps.
  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Left for the next open.
    }
  }

  @override
  Future<void> writeWordsAgain() async {
    if (_wordsFailed.isEmpty) return;
    // Only the failed recordings: one whose words are being written now must not be written twice.
    final failed = Set.of(_wordsFailed.keys);
    _wordsFailed.clear();
    _toldSinceAgain = false;
    await _refreshLocal();
    _track(_writePending(only: failed));
  }

  void _track(Future<void> job) {
    _writing.add(job);
    job.whenComplete(() => _writing.remove(job));
  }

  /// Ends when every recording being written has its words, and its note is sent while sending is on, or is gone or
  /// failed. A watch note's hand-off waits on it, so iOS gives the app time to finish.
  Future<void> wordsSettled() async {
    while (_writing.isNotEmpty) {
      await Future.wait(List.of(_writing));
    }
  }

  /// [wordsSettled], by the name the tests use.
  @visibleForTesting
  Future<void> wordsWritten() => wordsSettled();

  /// Writes the words of each recording still without them, oldest note first, or only of the recordings in [only].
  /// With [strayBefore], deletes recordings no note keeps, such as one the app's close cut off while the person still
  /// held the button: a kept recording moves out of `voice/` at once, and one written since [strayBefore] is new.
  Future<void> _writePending({DateTime? strayBefore, Set<String>? only}) async {
    final parts = voice;
    if (parts == null) return;
    if (strayBefore != null) {
      final folder = (await parts.recorder.fileOf(VoiceRecorder.pathOf('x'))).parent;
      if (await folder.exists()) {
        await for (final file in folder.list()) {
          if (file is File && (await _changedAt(file)).isBefore(strayBefore)) await _deleteRecording(file);
        }
      }
    }
    for (final (note, file) in await store.pendingWords()) {
      if (only == null || only.contains(file.id)) await _write(note, file);
    }
  }

  /// Writes the words of [note]'s recording [file]. No words: a new voice note with nothing else in it goes with its
  /// recording, and the app says it heard no speech; any other recording stays, with *No words heard*. It waits while
  /// the model is away; failed words, or words past the time limit, show *Try again* on the recording, and its note
  /// goes without them.
  Future<void> _write(LocalNote note, Attachment file) async {
    final parts = voice;
    if (parts == null) return;
    final sound = await _fileOf(file.path);
    final there = await sound.exists();
    if (there && parts.model.state != ModelState.ready) return;
    String words;
    try {
      // A recording gone, such as after a restore to a new phone, has no words to write.
      if (!there) throw const _Gone();
      // The limit counts from when the recording before ends or passes its limit, and stops only this one's writing.
      words = await parts.transcriber.words(sound, limit: _wordsLimit(Duration(milliseconds: file.lengthMs ?? 0)));
    } on _Gone {
      words = '';
    } on Object catch (error, stack) {
      // Any error, an Error too, such as an ArgumentError from the speech engine: the note must never wait silently.
      debugPrint('Recording ${file.id}: the words failed: $error\n$stack');
      // The notice shows once for each recording: not again when the same one fails on a return to the app.
      final tell = _toldWordsFailed.add(file.id) && !_toldSinceAgain;
      if (tell) _toldSinceAgain = true;
      _wordsFailed[file.id] = whyNoWords(error);
      await _setWords(file, null, note);
      if (tell && !_disposed) notice(_wordsDidNotCome);
      return;
    }
    if (words.isEmpty && await _silentNewNote(note.clientId)) {
      await store.dropNote(note.clientId);
      if (there) await _deleteRecording(sound);
      await _refreshLocal();
      if (there) notice(_noSpeech);
      return;
    }
    await _setWords(file, words, note);
  }

  /// Keeps a recording's words, or null for failed ones, and sends its note while sending is on.
  Future<void> _setWords(Attachment file, String? words, LocalNote note) async {
    final kept = await store.setTranscript(file.id, words, send: _settings.sending, at: _clock());
    // A recording that failed again changes nothing in the store, yet now shows *Try again*.
    await _refreshLocal();
    if (kept && _settings.sending) await sync();
  }

  /// True for a voice note held on *New note* with nothing but its one recording: no speech in it keeps nothing. A
  /// watch note, words given or typed with it, or another file keep the note.
  Future<bool> _silentNewNote(String clientId) async {
    final note = (await store.notes()).where((note) => note.clientId == clientId).firstOrNull;
    return note != null && note.kind == NoteKind.voice && !note.fromWatch && note.sentAt == null &&
      note.text.trim().isEmpty && note.attachments.length == 1;
  }

  /// Deletes a recording, or does nothing when the sweep for stray recordings deleted it first.
  /// When [file] last changed; a file gone meanwhile counts as new, so nothing deletes it.
  static Future<DateTime> _changedAt(File file) async {
    try {
      return await file.lastModified();
    } on FileSystemException {
      return DateTime.now();
    }
  }

  Future<void> _deleteRecording(File file) async {
    try {
      await file.delete();
    } on PathNotFoundException {
      // Gone already.
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
    _links?.cancel();
    _drainTimer?.cancel();
    voice?.model.removeListener(notifyListeners);
    super.dispose();
  }
}

/// A recording whose file is gone: [RelayController] treats it as one with no speech.
class _Gone implements Exception {
  const _Gone();
}
