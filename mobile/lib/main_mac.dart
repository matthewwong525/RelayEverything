import 'dart:async';
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'controller.dart';
import 'data/connection.dart';
import 'data/store.dart';
import 'mac/mac_app.dart';
import 'mac/updates.dart';
import 'relay.dart';
import 'sync/photos.dart' show PhoneNetwork;
import 'voice/playback.dart';

/// How often the open Mac app reads the notes changed elsewhere, besides each return to the window and each return of
/// the network.
const macPullEvery = Duration(minutes: 5);

/// Opens a note's file in the Mac's own app for its type, such as a sound file in the Mac's player.
Future<bool> openWithMac(File file, String type) => launchUrl(Uri.file(file.path));

/// The Mac app (`flutter build macos -t lib/main_mac.dart`): notes on the Mac, sent once signed in, with no phone-only
/// source; `test/mac_imports_test.dart` fails on one. Once the window shows, it checks for a new version.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBrandLicenses();
  const updates = MacUpdates();
  final relay = RelayController(store: Store(driftDatabase(name: 'relay')), vault: KeyVault(), platform: RelayPlatform.mac,
    folder: getApplicationSupportDirectory, opener: openWithMac, network: PhoneNetwork(), player: SoundPlayer(),
    updates: updates);
  await relay.load();
  runApp(MacApp(relay: relay));
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(updates.checkInBackground()));
  Timer.periodic(macPullEvery, (_) => unawaited(relay.pullNotes()));
  await relay.pullNotes();
}
