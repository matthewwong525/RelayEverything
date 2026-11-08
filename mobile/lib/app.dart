import 'package:flutter/material.dart';

import 'brand.dart';
import 'relay.dart';
import 'screens/connect.dart' show Scanner;
import 'screens/note_editor.dart' show FilesPicker, Sharer;
import 'screens/timeline.dart';

/// The timeline, with or without a key: notes stay on this phone until the person turns sending on.
class RelayApp extends StatelessWidget {
  const RelayApp({super.key, required this.relay, this.scanner, this.opener, this.picker, this.sharer,
    this.voiceRequests});

  final Relay relay;
  final Scanner? scanner;
  final Opener? opener;
  /// The paperclip's photo and file picker; a test passes its own.
  final FilesPicker? picker;
  /// A note's *Share*; a test passes its own.
  final Sharer? sharer;
  /// *Start a voice note* from Shortcuts: each event opens the recording sheet.
  final Stream<void>? voiceRequests;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Relay Everything',
      theme: brandTheme(Brightness.light),
      darkTheme: brandTheme(Brightness.dark),
      home: TimelineScreen(relay: relay, scanner: scanner, opener: opener, picker: picker, sharer: sharer,
        voiceRequests: voiceRequests),
    );
  }
}
