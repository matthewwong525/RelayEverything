import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/connection.dart';
import '../data/outbox.dart';
import '../data/sender.dart';
import '../data/settings.dart';
import '../data/store.dart';
import 'health.dart';
import 'photos.dart';

/// The hourly task's name; iPhone also lists it in Info.plist and AppDelegate.swift.
const syncTask = 'com.matthewwong525.relay.sync';

// The app and the background round share one connection, so their writes never collide.
Store openStore() => Store(driftDatabase(name: 'relay', native: const DriftNativeOptions(shareAcrossIsolates: true)));

/// The background round: health since the last read, the location points kept, every waiting upload, then new photos.
/// With sending off it reads, keeps and sends nothing.
@pragma('vm:entry-point')
void backgroundSync() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final connection = await KeyVault().read();
    if (connection == null) return true;
    final store = openStore();
    try {
      return await backgroundRound(store, connection: connection, health: PhoneHealth(), sender: Sender(), photos: PhonePhotos(),
        network: PhoneNetwork());
    } on Exception {
      return false;
    } finally {
      await store.close();
    }
  });
}

/// One background round, apart from the plugin that runs it so a test can drive it. True when it is done. The photo
/// step runs after the outbox, so a photo waiting for Wi-Fi holds back no note; it runs only with [photos] and
/// [network] given.
Future<bool> backgroundRound(Store store, {required Connection? connection, required HealthSource health, required Sender sender,
  PhotoSource? photos, Network? network, DateTime? now}) async {
  final settings = Settings.decode(await store.get(settingsKey), hasKey: connection != null);
  final api = sender.api(settings, connection);
  if (api == null) return true;
  if (settings.health) await syncHealth(store, health, now: now);
  await store.queuePoints();
  final notes = await flush(store, api);
  if (photos == null || network == null || !settings.photos) return notes.failure == null;
  // The app can turn photos off while this round runs: it reads the switch again before each photo.
  final failure = await syncPhotos(store, api, photos, network, settings: settings, send: notes.failure == null, now: now,
    keepGoing: () async => Settings.decode(await store.get(settingsKey), hasKey: true).photos);
  // A refused photo from a key that still answers, such as on an older server with no photos, comes back as null; a
  // turned-off key fails the round, as for the notes.
  return notes.failure == null && failure == null;
}

/// Turns the hourly round on while sending and history, health or photos are on, and off otherwise.
Future<void> scheduleSync(bool on) async {
  if (!on) return Workmanager().cancelByUniqueName(syncTask);
  await Workmanager().registerPeriodicTask(syncTask, syncTask, frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected), existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);
}
