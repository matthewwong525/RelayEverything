import 'package:flutter/material.dart';

import '../relay.dart';
import '../screens/connect_ai.dart';
import '../screens/email_notes.dart';
import '../screens/folder.dart' show Opener, openInBrowser;
import 'settings_parts.dart';
import 'space.dart';

/// What *Connect your AI* reads in the browser: the person's computers and the AI connector's apps, or null for the
/// apps when the server has no connector.
typedef _AiAnswer = (Connections, Map<String, dynamic>?);

/// *Connect your AI* in the browser's main pane: the same two parts as on the phone, with *Disconnect*, after a
/// confirm, beside each computer and each AI app. *Saved chats* opens the saved chats.
class WebConnectAiPage extends StatelessWidget {
  const WebConnectAiPage({super.key, required this.client, required this.onSavedChats, this.opener});

  final SpaceClient client;
  final VoidCallback onSavedChats;
  final Opener? opener;

  Future<_AiAnswer> _load() async {
    final connections = Connections.fromJson(await client.get('connections'));
    Map<String, dynamic>? apps;
    try {
      apps = await client.get('ai-apps');
    } on SpaceRefused catch (refused) {
      // A server with no AI connector answers 503: the page says so.
      if (refused.status != 503) rethrow;
    }
    return (connections, apps);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBody(title: 'Connect your AI', line: connectAiAbout, children: [
      SpaceView<_AiAnswer>(what: 'Your AI connections', load: _load, builder: (context, answer, act) {
        final (connections, ai) = answer;
        final address = ai?['address'];
        return ConnectAiParts(
          computers: connections.computers,
          apps: [
            for (final app in ai == null ? const <Map<String, dynamic>>[] : listOf(ai, 'apps'))
              (id: '${app['id']}', name: '${app['name']}',
                since: app['connectedAt'] is int ? DateTime.fromMillisecondsSinceEpoch(app['connectedAt'] as int) : null),
          ],
          address: address is String ? address : null,
          appsNote: ai == null ? 'The AI connector is not set up on this server.' : null,
          onSavedChats: onSavedChats,
          onGetPlugin: () => (opener ?? openInBrowser)(Uri.parse(pluginGuide)),
          onDisconnectComputer: (computer) => _disconnectComputer(context, computer, act),
          onDisconnectApp: (app) => _disconnectApp(context, app, act),
        );
      }),
    ]);
  }

  Future<void> _disconnectComputer(BuildContext context, ConnectedDevice computer, Act act) async {
    if (!await confirm(context, title: 'Disconnect ${computer.name}?', action: 'Disconnect',
      body: 'It stops saving chats and can not read Relay Everything any more. Its saved chats stay. To use it again, '
        'type /relay:connect on it.')) {
      return;
    }
    await act(() => client.post('devices/off', {'id': computer.id}));
  }

  Future<void> _disconnectApp(BuildContext context, ConnectedApp app, Act act) async {
    if (!await confirm(context, title: 'Disconnect ${app.name}?', action: 'Disconnect',
      body: 'It can not read or add to Relay Everything any more. To use it again, connect it again from the app.')) {
      return;
    }
    await act(() => client.post('ai-apps-disconnect', {'id': app.id}));
  }
}

/// *Email notes* in the browser's main pane: what it does, then the shared notes address and the private one, each with
/// *Copy*, and *New address* for the private one.
class WebEmailNotesPage extends StatelessWidget {
  const WebEmailNotesPage({super.key, required this.client});

  final SpaceClient client;

  @override
  Widget build(BuildContext context) {
    return SettingsBody(title: 'Email notes', line: emailNotesAbout, children: [
      SpaceView<Connections>(what: 'Your notes addresses', load: () async => Connections.fromJson(await client.get('connections')),
        builder: (context, connections, act) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (connections.sharedAddress == null && connections.notesAddress == null)
            const Note('Email notes are not set up on this server.')
          else ...[
            EmailNotesParts(email: connections.email, sharedAddress: connections.sharedAddress,
              privateAddress: connections.notesAddress, onNewAddress: () => _newAddress(context, act)),
            const Note('Email is not sealed on the way. Do not send health or location details this way.'),
          ],
        ])),
    ]);
  }

  Future<void> _newAddress(BuildContext context, Act act) async {
    if (!await confirm(context, title: 'Make a new address?', action: 'New address',
      body: 'Mail to your old address stops making notes at once. Change every mail rule and contact that uses it.')) {
      return;
    }
    await act(() => client.post('inbox/address'));
  }
}
