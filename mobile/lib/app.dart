import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'brand.dart';
import 'relay.dart';
import 'screens/home.dart';
import 'screens/note_editor.dart' show FilesPicker, Sharer;

final _light = brandTheme(Brightness.light);
final _dark = brandTheme(Brightness.dark);

/// On an iPhone, a named round button acts when the finger lifts, however long the press, and a long press shows no
/// name bubble, as in other iPhone apps. The name stays for VoiceOver, and a mouse still shows it on hover. Read in
/// [RelayApp.build], not in [_light], so a test's platform reaches it.
ThemeData _iPhoneButtons(ThemeData theme) => defaultTargetPlatform == TargetPlatform.iOS
  ? theme.copyWith(tooltipTheme: theme.tooltipTheme.copyWith(triggerMode: TooltipTriggerMode.manual))
  : theme;

/// Home, with or without a key: notes stay on this phone until the person turns sending on. The look follows the
/// person's *Appearance* pick, and the phone's own setting while it is *System*.
class RelayApp extends StatelessWidget {
  const RelayApp({super.key, required this.relay, this.opener, this.picker, this.sharer,
    this.voiceRequests});

  final Relay relay;
  final Opener? opener;
  /// The paperclip's photo and file picker; a test passes its own.
  final FilesPicker? picker;
  /// A note's *Share*; a test passes its own.
  final Sharer? sharer;
  /// *Start a voice note* from Shortcuts: each event opens the recording sheet.
  final Stream<void>? voiceRequests;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: relay,
      builder: (context, home) => MaterialApp(
        title: 'Relay Everything',
        theme: _iPhoneButtons(_light),
        darkTheme: _iPhoneButtons(_dark),
        themeMode: switch (relay.settings.appearance) {
          Appearance.light => ThemeMode.light,
          Appearance.dark => ThemeMode.dark,
          Appearance.system => ThemeMode.system,
        },
        home: home,
      ),
      child: HomeScreen(relay: relay, opener: opener, picker: picker, sharer: sharer,
        voiceRequests: voiceRequests),
    );
  }
}
