import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../brand.dart';
import '../screens/folder.dart' show Group, Opener, openInBrowser;
import 'settings_parts.dart';
import 'space.dart';

/// Where the iPhone app comes from until its first App Store release: TestFlight, on the App Store.
const appStoreLink = 'https://apps.apple.com/app/testflight/id899247664';
/// Where the Android app comes from: the newest release on GitHub, as the website's install page says.
const androidLink = 'https://github.com/matthewwong525/RelayEverything/releases/latest';

/// The kinds of data only the phone sends, each in the browser's *Other connections*.
enum ConnectionKind {
  location('Location', 'your places', CupertinoIcons.location),
  health('Health', 'your health data', CupertinoIcons.heart),
  calendar('Calendar', 'your calendar', CupertinoIcons.calendar),
  photos('Photos', 'your new photos', CupertinoIcons.photo);

  const ConnectionKind(this.title, this.what, this.icon);

  final String title;
  final String what;
  final IconData icon;
}

/// A phone connection in the browser, for now: it says the phone sends this data, and the store buttons lead to the
/// app. It never reads or shows health, place or calendar data. *Photos* also shows how many photos the space holds,
/// with *Delete all photos*, when it has a [client].
class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key, required this.kind, this.client, this.opener});

  final ConnectionKind kind;
  final SpaceClient? client;
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final text = Theme.of(context).textTheme;
    final open = opener ?? openInBrowser;
    final client = this.client;
    return Material(type: MaterialType.transparency, child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: brand.accentSoft, shape: BoxShape.circle),
            child: Icon(kind.icon, size: 34, color: brand.accentText)),
          const SizedBox(height: 20),
          Text(kind.title, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Your phone sends ${kind.what} to Relay Everything. Get the app on your phone, then turn on ${kind.title} '
            'in its Home.', textAlign: TextAlign.center, style: text.bodyLarge?.copyWith(color: brand.muted)),
          const SizedBox(height: 24),
          Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(onPressed: () => open(Uri.parse(appStoreLink)), icon: const Icon(CupertinoIcons.device_phone_portrait),
              label: const Text('App Store')),
            OutlinedButton.icon(onPressed: () => open(Uri.parse(androidLink)), icon: const Icon(CupertinoIcons.arrow_down_circle),
              label: const Text('Android')),
          ]),
          TextButton(onPressed: () => open(Uri.parse(installPage)), child: const Text('How to install the app')),
          if (kind == ConnectionKind.photos && client != null) ...[
            const SizedBox(height: 16),
            _PhotoCount(client: client),
          ],
        ])),
    )));
  }
}

/// How many photos the phones sent, and *Delete all photos*. It never shows a photo: the AI reads them.
class _PhotoCount extends StatelessWidget {
  const _PhotoCount({required this.client});

  final SpaceClient client;

  @override
  Widget build(BuildContext context) {
    final danger = brandOf(context).danger;
    return SpaceView<int>(what: 'Photos', load: () async => (await client.get('photos'))['count'] as int? ?? 0,
      builder: (context, count, act) => Group(children: [
        ListTile(
          title: Text(switch (count) {
            0 => 'No photos yet',
            1 => '1 photo sent from your phones.',
            _ => '${thousands(count)} photos sent from your phones.',
          }),
          subtitle: const Text('Your AI can see them. Turn photos off in the phone app.'),
        ),
        if (count > 0) ListTile(
          title: Text('Delete all photos', style: TextStyle(color: danger)),
          onTap: () async {
            if (await confirm(context, title: 'Delete all photos?', action: 'Delete all photos',
              body: 'This deletes every photo your phones sent, and your AI can not see them any more. Notes, health and '
                'places stay. You can not undo this.')) {
              await act(() => client.post('photos/delete', {'confirm': 'delete'}));
            }
          },
        ),
      ]));
  }
}
