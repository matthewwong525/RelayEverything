import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../data/connection.dart';
import '../data/outbox.dart';
import '../data/sender.dart';
import '../data/settings.dart';
import '../data/store.dart';
import 'health.dart';

/// The hourly task's name; iPhone also lists it in Info.plist and AppDelegate.swift.
const syncTask = 'com.matthewwong525.relay.sync';

// The app and the background round share one connection, so their writes never collide.
Store openStore() => Store(driftDatabase(name: 'relay', native: const DriftNativeOptions(shareAcrossIsolates: true)));

/// The background round: health since the last read, the location points kept, then every waiting upload. With
/// sending off it reads, keeps and sends nothing.
@pragma('vm:entry-point')
void backgroundSync() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final connection = await KeyVault().read();
    if (connection == null) return true;
    final store = openStore();
    try {
      return await backgroundRound(store, connection: connection, health: PhoneHealth(), sender: Sender(),
        folder: getApplicationSupportDirectory);
    } on Exception {
      return false;
    } finally {
      await store.close();
    }
  });
}

/// One background round, apart from the plugin that runs it so a test can drive it. True when it is done.
Future<bool> backgroundRound(Store store, {required Connection? connection, required HealthSource health, required Sender sender,
  DateTime? now, Future<Directory> Function()? folder}) async {
  final settings = Settings.decode(await store.get(settingsKey), hasKey: connection != null);
  final api = sender.api(settings, connection);
  if (api == null) return true;
  if (settings.health) await syncHealth(store, health, now: now);
  await store.queuePoints();
  return (await flush(store, api, folder: folder)).failure == null;
}

/// Turns the hourly round on while sending and history or health are on, and off otherwise.
Future<void> scheduleSync(bool on) async {
  if (!on) return Workmanager().cancelByUniqueName(syncTask);
  await Workmanager().registerPeriodicTask(syncTask, syncTask, frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected), existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);
}
