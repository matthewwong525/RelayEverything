import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'controller.dart';
import 'data/connection.dart';
import 'shortcuts/bridge.dart';
import 'sync/background.dart';
import 'sync/health.dart';
import 'sync/location.dart';
import 'sync/native.dart';
import 'sync/wake.dart';
import 'voice/model.dart';
import 'voice/recorder.dart';
import 'voice/transcriber.dart';

// The entry point Shortcuts' background engine starts. Exported, so a release build keeps it.
export 'shortcuts/entry.dart' show shortcutsMain;

/// Swift starts this by name when Health or a place wakes the closed iPhone app (ios/Runner/RelayBackground.swift).
/// Naming it here keeps `sync/wake.dart` in the build: a library that `main.dart` does not reach is left out.
const wakeEntryPoint = wakeRound;

/// Opens a note's file in the app the phone picks for its type.
Future<bool> openWithPhone(File file, String type) async {
  final result = await OpenFilex.open(file.path, type: type);
  return result.type == ResultType.done;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(backgroundSync);
  final model = SpeechModel(folder: getApplicationSupportDirectory, excludeFromBackup: excludeFromBackup);
  final voice = VoiceParts(model: model, recorder: VoiceRecorder(microphone: PhoneMicrophone(), folder: getApplicationSupportDirectory,
    excludeFromBackup: excludeFromBackup),
    transcriber: WhisperTranscriber(() async => (await model.file).path), player: PhonePlayer());
  final relay = RelayController(store: openStore(), vault: KeyVault(), places: PhonePlaces(), health: PhoneHealth(), schedule: scheduleSync,
    voice: voice, native: Platform.isIOS ? PhoneBackground() : null, folder: getApplicationSupportDirectory, opener: openWithPhone);
  // A Health or place wake while the app runs syncs here, in place of a second engine.
  if (Platform.isIOS) PhoneBackground.onWake(relay.sync);
  await relay.load();
  // *Start a voice note* from Shortcuts or the Action button. The timeline takes each request once it is on screen.
  final voiceRequests = StreamController<void>();
  runApp(RelayApp(relay: relay, voiceRequests: voiceRequests.stream));
  // While the app runs, Shortcuts' actions use this engine, so the open timeline shows a shortcut's note at once.
  unawaited(listenForShortcuts(ShortcutsBridge(relay, onVoice: () => voiceRequests.add(null))));
  // Each open, and each return to the app, sends what waits.
  AppLifecycleListener(onResume: relay.sync);
  await relay.sync();
}
