import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../data/connection.dart';
import '../data/sender.dart';
import '../share/inbox.dart';
import 'background.dart';
import 'health.dart';
import 'location.dart';
import 'native.dart';

/// One round when the iPhone wakes the closed app, for new Health readings or a new place. Swift runs it in its own
/// engine, ends it when it answers `done` on `relay/wake`, and stops waiting after 25 s.
@pragma('vm:entry-point')
Future<void> wakeRound() async {
  WidgetsFlutterBinding.ensureInitialized();
  var done = false;
  try {
    final store = openStore();
    try {
      done = await backgroundRound(store, connection: await KeyVault().read(), health: PhoneHealth(), sender: Sender(),
        native: Platform.isIOS ? PhoneBackground() : null, places: PhonePlaces(), folder: getApplicationSupportDirectory,
        share: Platform.isIOS ? PhoneShareGroup() : null);
    } finally {
      await store.close();
    }
  } on Exception {
    // The next wake, or the hourly round, tries again.
  }
  await const MethodChannel('relay/wake').invokeMethod('done', done);
}
