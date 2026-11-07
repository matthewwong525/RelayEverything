import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'controller.dart';
import 'data/connection.dart';
import 'sync/background.dart';
import 'sync/health.dart';
import 'sync/location.dart';
import 'sync/photos.dart';
import 'voice/model.dart';
import 'voice/recorder.dart';
import 'voice/transcriber.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(backgroundSync);
  final model = SpeechModel(folder: getApplicationSupportDirectory, excludeFromBackup: excludeFromBackup);
  final voice = VoiceParts(model: model, recorder: VoiceRecorder(microphone: PhoneMicrophone(), folder: getApplicationSupportDirectory,
    excludeFromBackup: excludeFromBackup),
    transcriber: WhisperTranscriber(() async => (await model.file).path), player: PhonePlayer());
  final relay = RelayController(store: openStore(), vault: KeyVault(), places: PhonePlaces(), health: PhoneHealth(), schedule: scheduleSync,
    voice: voice, photos: PhonePhotos(), network: PhoneNetwork());
  await relay.load();
  runApp(RelayApp(relay: relay));
  // Each open, and each return to the app, sends what waits and looks for new photos.
  AppLifecycleListener(onResume: relay.sync);
  await relay.sync();
}
