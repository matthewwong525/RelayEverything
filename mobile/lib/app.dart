import 'package:flutter/material.dart';

import 'relay.dart';
import 'screens/compose.dart' show FilesPicker;
import 'screens/connect.dart' show Scanner;
import 'screens/timeline.dart';

/// The timeline, with or without a key: notes stay on this phone until the person turns sending on.
class RelayApp extends StatelessWidget {
  const RelayApp({super.key, required this.relay, this.scanner, this.opener, this.picker, this.voiceRequests});

  final Relay relay;
  final Scanner? scanner;
  final Opener? opener;
  /// The paperclip's photo and file picker; a test passes its own.
  final FilesPicker? picker;
  /// *Start a voice note* from Shortcuts: each event opens the recording sheet.
  final Stream<void>? voiceRequests;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Relay Everything',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
      home: TimelineScreen(relay: relay, scanner: scanner, opener: opener, picker: picker, voiceRequests: voiceRequests),
    );
  }
}
