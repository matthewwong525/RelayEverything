import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../data/api.dart';
import '../data/connection.dart';
import '../data/note_sync.dart';
import '../data/outbox.dart';
import '../data/sender.dart';
import '../data/settings.dart';
import '../data/store.dart';
import '../share/inbox.dart';
import 'calendar.dart';
import 'health.dart';
import 'location.dart';
import 'native.dart';
import 'photos.dart';

/// The hourly task's name; iPhone also lists it in Info.plist and AppDelegate.swift.
const syncTask = 'com.matthewwong525.relay.sync';

// The app and the background round share one connection, so their writes never collide.
Store openStore() => Store(driftDatabase(name: 'relay', native: const DriftNativeOptions(shareAcrossIsolates: true)));

/// The background round: health since the last read, the calendar's changes, the location points kept, then every
/// waiting upload, then new photos, each to the server or the person's own webhook. With sending off it reads, keeps and
/// sends nothing.
@pragma('vm:entry-point')
void backgroundSync() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final store = openStore();
    try {
      return await savedRound(store, KeyVault(), health: PhoneHealth(), sender: Sender(),
        native: Platform.isIOS ? PhoneBackground() : null, places: PhonePlaces(), folder: getApplicationSupportDirectory,
        share: Platform.isIOS ? PhoneShareGroup() : null, calendar: PhoneCalendarSource(), photos: PhonePhotos(),
        network: PhoneNetwork(), pull: true);
    } on Exception {
      return false;
    } finally {
      await store.close();
    }
  });
}

/// A [backgroundRound] with the key and the webhook kept in [vault]. The hourly task and an iPhone wake both start
/// here, so each sends to the place the settings name, the webhook too.
Future<bool> savedRound(Store store, KeyVault vault, {required HealthSource health, required Sender sender,
  NativeBackground? native, Places? places, DateTime? now, Future<Directory> Function()? folder, ShareGroup? share,
  CalendarSource? calendar, PhotoSource? photos, Network? network, bool pull = false}) async =>
  backgroundRound(store, connection: await vault.read(), webhook: await vault.readWebhook(), health: health, sender: sender,
    native: native, places: places, now: now, folder: folder, share: share, calendar: calendar, photos: photos,
    network: network, pull: pull);

/// One background round, apart from the plugin that runs it so a test can drive it: the hourly task and an iPhone
/// wake share it. With [share], it first keeps the notes the iPhone's share card left. With [native], it moves the
/// points Swift kept. True when it is done; a calendar that could not be read, such as where the iPhone's background
/// engine has no calendar, does not hold the round back.
/// It sends notes to the place the settings name: the server with [connection], or the person's own [webhook], which
/// needs no key. Health, points, the calendar and photos go to [Settings.privatePlace]: the same place, or only the
/// webhook, flushed apart after the notes, so one place that fails holds back nothing for the other. With no webhook
/// for them, they wait on the phone and never go to the server. The photo step runs after the outbox, so a photo
/// waiting for Wi-Fi holds back no note; it runs only with [photos] and [network] given. With [pull], it ends by
/// reading notes changed elsewhere, after the notes' flush emptied.
Future<bool> backgroundRound(Store store, {required Connection? connection, Webhook? webhook, required HealthSource health,
  required Sender sender, NativeBackground? native, Places? places, DateTime? now, Future<Directory> Function()? folder,
  ShareGroup? share, CalendarSource? calendar, PhotoSource? photos, Network? network, bool pull = false}) async {
  final settings = Settings.decode(await store.get(settingsKey), hasKey: connection != null);
  final installId = settings.privatePlace == SendPlace.webhook ? await store.installId() : null;
  final api = sender.api(settings, connection: connection, webhook: webhook, installId: installId);
  if (api == null) return true;
  final privateApi = sender.privateApi(settings, connection: connection, webhook: webhook, installId: installId);
  if (share != null && folder != null) {
    try {
      final group = await share.folder();
      if (group != null) await drainShareInbox(group, (await folder()).path, store, send: settings.sending);
    } on Exception {
      // The app keeps them on its next open.
    }
  }
  if (native != null && settings.history) await drainPoints(store, native, name: places?.nameOf);
  var read = true;
  if (settings.health) {
    try {
      await syncHealth(store, health, now: now);
    } on Exception {
      // A locked iPhone refuses Health reads: the points still go, and the next round reads the same readings again.
      read = false;
    }
  }
  if (settings.calendar && calendar != null) {
    try {
      await syncCalendar(store, calendar, settings, now: now);
    } on Exception {
      // A refused calendar removes nothing; the next round reads again.
    }
  }
  await store.queuePoints();
  final notes = await flush(store, api, folder: folder);
  // Private data to its own place: flushed apart, so it waits behind no note. With no client for it, such as a webhook
  // lost in a restore, it waits; that is no failure of the round, as no retry can send it before the person sets it.
  final apart = privateApi != null && privateApi.destination != api.destination;
  final private = apart ? await flush(store, privateApi, folder: folder) : notes;
  Failure? failure;
  if (photos != null && network != null && settings.photos) {
    // The app can turn photos off while this round runs: it reads the switch again before each photo.
    failure = await syncPhotos(store, privateApi, photos, network, settings: settings, send: private.failure == null,
      now: now, keepGoing: () async {
        final now = Settings.decode(await store.get(settingsKey), hasKey: true);
        return now.photos && now.place == settings.place && now.privatePlace == settings.privatePlace;
      });
  }
  // Only after the outbox emptied, so this phone's own changes are on the server before it reads.
  if (pull && notes.failure == null) {
    try {
      await syncNotes(store, sender, settings: settings, connection: connection);
    } on ApiException {
      return false;
    }
  }
  // A refused photo from a key that still answers, such as on an older server with no photos, comes back as null; a
  // turned-off key fails the round, as for the notes.
  return notes.failure == null && private.failure == null && read && failure == null;
}

/// Turns the hourly round on while sending and history, health, the calendar or photos are on, and off otherwise.
Future<void> scheduleSync(bool on) async {
  if (!on) return Workmanager().cancelByUniqueName(syncTask);
  await Workmanager().registerPeriodicTask(syncTask, syncTask, frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected), existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);
}
