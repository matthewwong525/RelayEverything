import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../data/connection.dart' show defaultServer;
import '../relay.dart';
import 'account.dart' show AccountState, accountOf;
import 'days.dart' show daysAgo, shortDay;
import 'folder.dart';
import 'timeline.dart' show openPage;
import 'transcripts.dart';

/// The address a person adds in Claude, ChatGPT or another AI app to connect it to Relay Everything.
const aiConnectorAddress = 'https://mcp.relayeverything.com';

/// The website's page on the plugin for Claude Code and Codex.
const pluginGuide = 'https://relayeverything.com/connections/claude-code/';

/// What *Connect your AI* and its row on Home say it does.
const connectAiLine = 'Let your AI read your notes';

/// What the page says at its top.
const connectAiAbout = 'Let your AI read your notes, health and places, and add notes when you ask.';

/// A computer's line: when the plugin last saved a chat.
String computerLine(DateTime? lastChat, DateTime now) {
  if (lastChat == null) return 'Plugin · no chat saved yet';
  return switch (daysAgo(lastChat.toLocal(), now)) {
    <= 0 => 'Plugin · saved a chat today',
    1 => 'Plugin · saved a chat yesterday',
    _ => 'Plugin · last chat ${shortDay(lastChat, now)}',
  };
}

/// A connected AI app on *Connect your AI*: its name, the day it connected, and on the web its id to disconnect.
typedef ConnectedApp = ({String? id, String name, DateTime? since});

/// The two parts of *Connect your AI*, on the phone and the web: *Claude Code and Codex*, with each computer and its
/// last saved chat, *Saved chats* and *Get the plugin*; then *Claude, ChatGPT and other AI apps*, with the AI
/// connector's [address] to copy and each app with the day it connected. Null [computers] and [apps] list none, as
/// when signed out. With [onDisconnectComputer] and [onDisconnectApp], as on the web, each row has *Disconnect*; with
/// [onManage], as on the phone, a last row opens the Relay Everything page.
class ConnectAiParts extends StatelessWidget {
  const ConnectAiParts({super.key, this.computers, this.apps, this.address, required this.onSavedChats,
    required this.onGetPlugin, this.onDisconnectComputer, this.onDisconnectApp, this.onManage, this.appsNote, this.copy});

  final List<ConnectedDevice>? computers;
  final List<ConnectedApp>? apps;
  /// The AI connector's address; null when this server has none.
  final String? address;
  final VoidCallback onSavedChats;
  final VoidCallback onGetPlugin;
  final ValueChanged<ConnectedDevice>? onDisconnectComputer;
  final ValueChanged<ConnectedApp>? onDisconnectApp;
  final VoidCallback? onManage;
  /// Words in place of the address, such as that the connector is not set up.
  final String? appsNote;
  /// Puts the address on the clipboard; a test passes its own.
  final Future<void> Function(String text)? copy;

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    final now = DateTime.now();
    final computers = this.computers ?? const <ConnectedDevice>[];
    final apps = this.apps ?? const <ConnectedApp>[];
    Widget disconnect(VoidCallback onPressed) =>
      TextButton(onPressed: onPressed, style: quietButton(context), child: const Text('Disconnect'));
    Widget out(String label, VoidCallback onTap) => ListTile(
      title: Text(label, style: TextStyle(color: brand.accentText, fontWeight: FontWeight.w500)),
      trailing: Icon(CupertinoIcons.arrow_up_right_square, color: brand.muted),
      onTap: onTap,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Group(title: 'Claude Code and Codex', children: [
        for (final computer in computers) ListTile(
          leading: Icon(CupertinoIcons.device_laptop, color: brand.accentText),
          title: Text(computer.name),
          subtitle: Text(computerLine(computer.lastChat, now)),
          trailing: onDisconnectComputer == null ? null : disconnect(() => onDisconnectComputer!(computer)),
        ),
        FolderRow(icon: CupertinoIcons.chat_bubble_2, title: 'Saved chats', line: 'Only the plugin saves your chats',
          onTap: onSavedChats),
        out('Get the plugin', onGetPlugin),
      ]),
      Group(title: 'Claude, ChatGPT and other AI apps', children: [
        if (address case final address?) ListTile(
          title: Text(hostOf(address), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Add it in your AI app: Settings, Connectors'),
          trailing: TextButton(onPressed: () => _copy(context, address), style: quietButton(context), child: const Text('Copy')),
        ) else if (appsNote case final note?) ListTile(subtitle: Text(note)),
        for (final app in apps) ListTile(
          leading: Icon(CupertinoIcons.sparkles, color: brand.accentText),
          title: Text(app.name),
          subtitle: app.since == null ? null : Text('Connected ${shortDay(app.since!, now)}'),
          trailing: onDisconnectApp == null ? null : disconnect(() => onDisconnectApp!(app)),
        ),
        if (onManage case final onManage? when apps.isNotEmpty || computers.isNotEmpty)
          out('Disconnect on your Relay Everything page', onManage),
      ]),
    ]);
  }

  Future<void> _copy(BuildContext context, String text) async {
    final messenger = ScaffoldMessenger.of(context);
    var copied = true;
    try {
      await (copy ?? (text) => Clipboard.setData(ClipboardData(text: text)))(text);
    } on Exception {
      copied = false;
    }
    messenger.showSnackBar(SnackBar(content: Text(copied ? 'Copied.' : 'Copy did not work. Select the text and copy it.')));
  }
}

/// *Connect your AI* on the phone, opened from Home: [ConnectAiParts] from what `GET connections` last answered.
/// Disconnecting opens the Relay Everything page. Signed out it makes no request, shows only the AI connector's
/// address, and offers *Sign in*.
class ConnectAiPage extends StatefulWidget {
  const ConnectAiPage({super.key, required this.relay, this.opener, this.copy});

  final Relay relay;
  /// Opens the Relay Everything page or the website; a test passes its own.
  final Opener? opener;
  final Future<void> Function(String text)? copy;

  @override
  State<ConnectAiPage> createState() => _ConnectAiPageState();
}

class _ConnectAiPageState extends State<ConnectAiPage> {
  Relay get relay => widget.relay;

  @override
  void initState() {
    super.initState();
    // It asks only while the phone sends to a Relay Everything server.
    relay.refreshConnections();
  }

  @override
  Widget build(BuildContext context) {
    return FolderPage(relay: relay, title: 'Connect your AI', groups: (context) {
      final signedIn = accountOf(relay) == AccountState.signedIn;
      final connections = signedIn ? relay.connections : null;
      // The public connector serves Relay Everything's own server; another server's address is on its page.
      final server = relay.server;
      final public = !signedIn || server == null || server == defaultServer;
      return [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(connectAiAbout,
          style: TextStyle(fontSize: 13, color: brandOf(context).muted))),
        ConnectAiParts(
          computers: connections?.computers,
          apps: [for (final app in connections?.aiApps ?? const <AiApp>[]) (id: null, name: app.name, since: app.since)],
          address: public ? aiConnectorAddress : null,
          appsNote: public ? null : 'Find the address to add on your Relay Everything page.',
          copy: widget.copy,
          onSavedChats: () => openPage(context, TranscriptsPage(relay: relay, opener: widget.opener)),
          onGetPlugin: () => _openGuide(context),
          onManage: signedIn ? () => openRelayPage(context, relay, '#ai-apps', opener: widget.opener) : null,
        ),
        if (!signedIn) Padding(padding: const EdgeInsets.only(top: 20), child: FilledButton(
          onPressed: () => choosePlace(context, relay, keepWebhook: accountOf(relay) == AccountState.webhook),
          child: const Text('Sign in'))),
      ];
    });
  }

  Future<void> _openGuide(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await (widget.opener ?? openInBrowser)(Uri.parse(pluginGuide))) {
      messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
    }
  }
}
