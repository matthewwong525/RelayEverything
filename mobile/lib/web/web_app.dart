import 'package:flutter/material.dart';

import '../brand.dart';
import '../relay.dart';
import 'settings_dialog.dart';
import 'shell.dart';
import 'sign_in.dart';
import 'space.dart';
import 'web_relay.dart';

final _light = brandTheme(Brightness.light);
final _dark = brandTheme(Brightness.dark);

/// The Relay Everything page in the browser: the sign-in, or the notes once the person is signed in. The look follows
/// *Appearance* for this visit, and the browser's own setting while it is *System*.
class WebApp extends StatelessWidget {
  const WebApp({super.key, required this.relay, required this.client, this.page, this.navigate, this.takeSettingsAt,
    this.takePlaceAt});

  final WebRelay relay;
  final SpaceClient client;
  /// The page's address, with its `next` and `signIn` query; the browser's own when null.
  final Uri? page;
  /// Moves the window to an address, as the Apple and Google sign-ins do; a test passes its own.
  final Future<void> Function(Uri address)? navigate;
  /// Gives, once, the Settings page the page's first address named, such as `#webhooks`; null after that. The shell reads
  /// it only as it starts, so a later rebuild or a shell after a new sign-in opens nothing.
  final SettingsPage? Function()? takeSettingsAt;
  /// Gives, once, the place the page's first address named, such as `#email-notes`; null after that, as [takeSettingsAt].
  final WebPlace? Function()? takePlaceAt;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: relay,
      builder: (context, _) => MaterialApp(
        title: 'Relay Everything',
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        themeMode: switch (relay.settings.appearance) {
          Appearance.light => ThemeMode.light,
          Appearance.dark => ThemeMode.dark,
          Appearance.system => ThemeMode.system,
        },
        home: switch (relay.signInState) {
          WebSignIn.checking => const _Loading(),
          WebSignIn.signedOut => SignInScreen(client: client, page: page, navigate: navigate, onSignedIn: relay.start),
          WebSignIn.signedIn => WebShell(relay: relay, client: client, settingsAt: takeSettingsAt?.call(),
            placeAt: takePlaceAt?.call()),
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: RelayMark(size: 56)));
}
