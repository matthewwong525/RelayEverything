import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../data/api.dart';
import '../data/connection.dart';
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
/// waiting upload, to the server or the person's own webhook, then new photos, to the server only. With sending off it
/// reads, keeps and sends nothing.
@pragma('vm:entry-point')
void backgroundSync() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final store = openStore();
    try {
      return await savedRound(store, KeyVault(), health: PhoneHealth(), sender: Sender(),
        native: Platform.isIOS ? PhoneBackground() : null, places: PhonePlaces(), folder: getApplicationSupportDirectory,
        share: Platform.isIOS ? PhoneShareGroup() : null, calendar: PhoneCalendarSource(), photos: PhonePhotos(),
        network: PhoneNetwork());
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
  CalendarSource? calendar, PhotoSource? photos, Network? network}) async =>
  backgroundRound(store, connection: await vault.read(), webhook: await vault.readWebhook(), health: health, sender: sender,
    native: native, places: places, now: now, folder: folder, share: share, calendar: calendar, photos: photos,
    network: network);

/// One background round, apart from the plugin that runs it so a test can drive it: the hourly task and an iPhone
/// wake share it. With [share], it first keeps the notes the iPhone's share card left. With [native], it moves the
/// points Swift kept. True when it is done; a calendar that could not be read, such as where the iPhone's background
/// engine has no calendar, does not hold the round back.
/// It sends to the place the settings name: the server with [connection], or the person's own [webhook], which needs no
/// key. The photo step runs after the outbox, so a photo waiting for Wi-Fi holds back no note; it runs only with
/// [photos] and [network] given, and only to the server: a photo never goes to a webhook.
Future<bool> backgroundRound(Store store, {required Connection? connection, Webhook? webhook, required HealthSource health,
  required Sender sender, NativeBackground? native, Places? places, DateTime? now, Future<Directory> Function()? folder,
  ShareGroup? share, CalendarSource? calendar, PhotoSource? photos, Network? network}) async {
  final settings = Settings.decode(await store.get(settingsKey), hasKey: connection != null);
  final api = sender.api(settings, connection: connection, webhook: webhook,
    installId: settings.place == SendPlace.webhook ? await store.installId() : null);
  if (api == null) return true;
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
  if (photos == null || network == null || !settings.photos || api is! RelayApi) return notes.failure == null && read;
  // The app can turn photos off while this round runs: it reads the switch again before each photo.
  final failure = await syncPhotos(store, api, photos, network, settings: settings, send: notes.failure == null, now: now,
    keepGoing: () async => Settings.decode(await store.get(settingsKey), hasKey: true).photos);
  // A refused photo from a key that still answers, such as on an older server with no photos, comes back as null; a
  // turned-off key fails the round, as for the notes.
  return notes.failure == null && read && failure == null;
}

/// Turns the hourly round on while sending and history, health, the calendar or photos are on, and off otherwise.
Future<void> scheduleSync(bool on) async {
  if (!on) return Workmanager().cancelByUniqueName(syncTask);
  await Workmanager().registerPeriodicTask(syncTask, syncTask, frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected), existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);
}
