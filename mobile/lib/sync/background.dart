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
import '../share/inbox.dart';
import 'health.dart';
import 'location.dart';
import 'native.dart';

/// The hourly task's name; iPhone also lists it in Info.plist and AppDelegate.swift.
const syncTask = 'com.matthewwong525.relay.sync';

// The app and the background round share one connection, so their writes never collide.
Store openStore() => Store(driftDatabase(name: 'relay', native: const DriftNativeOptions(shareAcrossIsolates: true)));

/// The background round: health since the last read, the location points kept, then every waiting upload, to the
/// server or the person's own webhook. With sending off it reads, keeps and sends nothing.
@pragma('vm:entry-point')
void backgroundSync() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final store = openStore();
    try {
      return await savedRound(store, KeyVault(), health: PhoneHealth(), sender: Sender(),
        native: Platform.isIOS ? PhoneBackground() : null, places: PhonePlaces(), folder: getApplicationSupportDirectory,
        share: Platform.isIOS ? PhoneShareGroup() : null);
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
  NativeBackground? native, Places? places, DateTime? now, Future<Directory> Function()? folder, ShareGroup? share}) async =>
  backgroundRound(store, connection: await vault.read(), webhook: await vault.readWebhook(), health: health, sender: sender,
    native: native, places: places, now: now, folder: folder, share: share);

/// One background round, apart from the plugin that runs it so a test can drive it: the hourly task and an iPhone
/// wake share it. With [share], it first keeps the notes the iPhone's share card left. With [native], it moves the
/// points Swift kept. True when it is done.
/// It sends to the place the settings name: the server with [connection], or the person's own [webhook], which needs no
/// key.
Future<bool> backgroundRound(Store store, {required Connection? connection, Webhook? webhook, required HealthSource health,
  required Sender sender, NativeBackground? native, Places? places, DateTime? now, Future<Directory> Function()? folder,
  ShareGroup? share}) async {
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
  await store.queuePoints();
  return (await flush(store, api, folder: folder)).failure == null && read;
}

/// Turns the hourly round on while sending and history or health are on, and off otherwise.
Future<void> scheduleSync(bool on) async {
  if (!on) return Workmanager().cancelByUniqueName(syncTask);
  await Workmanager().registerPeriodicTask(syncTask, syncTask, frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected), existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);
}
