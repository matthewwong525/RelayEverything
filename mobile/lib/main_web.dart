import 'dart:async';

import 'package:flutter/material.dart';

import 'brand.dart';
import 'web/page_close.dart';
import 'web/settings_dialog.dart';
import 'web/space.dart';
import 'web/web_app.dart';
import 'web/web_relay.dart';

/// The Relay Everything page, built for the browser with `--base-href /apps/relay/`, and opened at a server's `/`.
/// It reaches no phone-only library: `test/web_imports_test.dart` fails on one.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerBrandLicenses();
  late final WebRelay relay;
  final client = SpaceClient(base: pageOf(Uri.base), onSignedOut: () => relay.signedOut());
  relay = WebRelay(client: client);
  // The phone's *Webhooks* and *AI apps* rows open `/#webhooks`: Settings opens there once. It is read before
  // the app starts, because the app then writes its own route in the address.
  SettingsPage? settingsAt = SettingsPage.ofPart(Uri.base.fragment);
  runApp(WebApp(relay: relay, client: client, takeSettingsAt: () {
    final page = settingsAt;
    settingsAt = null;
    return page;
  }));
  // A closing tab sends the deletes under *Undo* and the words that did not go.
  onPageClose(relay.pageClosing);
  unawaited(relay.start());
}

/// The page's files, API and sign-in, under `/apps/relay/` on the server that serves it, wherever the page opens.
Uri pageOf(Uri address) => Uri(scheme: address.scheme, host: address.host, port: address.hasPort ? address.port : null,
  path: '/apps/relay/');
