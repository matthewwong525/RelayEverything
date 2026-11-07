import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../controller.dart';
import '../data/connection.dart';
import '../sync/background.dart';
import '../sync/health.dart';
import '../sync/location.dart';
import 'bridge.dart';

/// The Dart side of Apple Shortcuts' actions when the app is not open: `ios/Runner/RelayIntents.swift` starts a
/// background engine here. It builds the app's own controller on the same store, so a shortcut's note is kept, pinned
/// and sent as a note typed in the app is, and opening it drains any note the inbox kept.
@pragma('vm:entry-point')
Future<void> shortcutsMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final relay = RelayController(store: openStore(), vault: KeyVault(), places: PhonePlaces(), health: PhoneHealth(),
    folder: getApplicationSupportDirectory);
  await relay.load();
  await listenForShortcuts(ShortcutsBridge(relay));
}
