import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../relay.dart';
import 'account.dart' show AccountState, accountOf;
import 'folder.dart';

/// The commands that add the Relay Everything plugin to Claude Code, typed in Claude Code.
const claudeCodeCommands = ['/plugin marketplace add matthewwong525/RelayEverything', '/plugin install relay@relay'];

/// The commands that add the plugin to Codex, run in a terminal.
const codexCommands = ['codex plugin marketplace add matthewwong525/RelayEverything', 'codex plugin add relay@relay'];

/// The command that connects a computer, typed in Claude Code or Codex.
const connectCommand = '/relay:connect';

/// *AI chat transcripts*, opened from Home: what the plugin saves, the steps to add it to a computer, and, signed in to a
/// Relay Everything server, *Read them on the web*, which opens the saved chats on the person's page. The page makes no
/// request: the phone's key reads no chat.
class TranscriptsPage extends StatelessWidget {
  const TranscriptsPage({super.key, required this.relay, this.opener});

  final Relay relay;
  /// Opens the Relay Everything page; a test passes its own.
  final Opener? opener;

  @override
  Widget build(BuildContext context) {
    return FolderPage(relay: relay, title: 'AI chat transcripts', groups: (context) {
      final theme = Theme.of(context);
      final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
      // Only a Relay Everything server keeps chats: signed out or with the person's own webhook, no link shows.
      final server = accountOf(relay) == AccountState.signedIn ? relay.server : null;
      return [
        Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 0), child: Text('The Relay Everything plugin saves your Claude '
          'Code and Codex chats word for word. Do these steps one time on each computer.', style: theme.textTheme.bodyLarge)),
        const Group(children: [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 12), child: TranscriptSteps())]),
        if (server != null) Padding(padding: const EdgeInsets.only(top: 20),
          child: FilledButton(onPressed: () => _read(context, server), child: const Text('Read them on the web'))),
        Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 0), child: Text('Each chat from then on is saved. Older chats '
          'are not sent. To keep the chats of a project out, type /relay:saving off in that project.', style: muted)),
        Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text("The computer's key saves your chats and can "
          'read all your Relay Everything data. To stop it, turn it off in Devices on your Relay Everything page.',
          style: muted)),
      ];
    });
  }

  /// The saved chats on the person's Relay Everything page, in the phone's browser.
  Future<void> _read(BuildContext context, String server) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await (opener ?? openInBrowser)(Uri.parse('$server/#chats'))) {
      messenger.showSnackBar(const SnackBar(content: Text('The browser did not open. Try again.')));
    }
  }
}

/// The steps that save a computer's AI chats: add the plugin in Claude Code or Codex, type `/relay:connect`, then click
/// *Connect* on the link. The phone's page and the web page's chats show the same steps.
class TranscriptSteps extends StatelessWidget {
  const TranscriptSteps({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodyMedium;
    Widget step(int n, List<Widget> children) => Padding(padding: const EdgeInsets.only(top: 12), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 22, child: Text('$n.', style: text)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
      ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      step(1, [
        Text('In Claude Code, type these commands to add the plugin:', style: text),
        for (final command in claudeCodeCommands) CommandBox(command),
        const SizedBox(height: 10),
        Text('Or, for Codex, run these commands in a terminal:', style: text),
        for (final command in codexCommands) CommandBox(command),
      ]),
      step(2, [
        Text('In Claude Code or Codex, type this command:', style: text),
        const CommandBox(connectCommand),
      ]),
      step(3, [Text('Open the link that it shows. Make sure that the code on the page is the same as the code on your '
        'computer. Then click Connect.', style: text)]),
    ]);
  }
}

/// One command to type, in a box: selectable, with a button that copies it and then shows a check.
class CommandBox extends StatefulWidget {
  const CommandBox(this.command, {super.key});

  final String command;

  @override
  State<CommandBox> createState() => _CommandBoxState();
}

class _CommandBoxState extends State<CommandBox> {
  bool _copied = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.command));
    } on Exception {
      // Nothing was copied: the words stay selectable.
      return;
    }
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final brand = brandOf(context);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(color: brand.paper, border: Border.all(color: brand.line),
        borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(child: SelectableText(widget.command,
          style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: brand.ink))),
        IconButton(
          tooltip: _copied ? 'Copied' : 'Copy',
          onPressed: _copy,
          icon: Icon(_copied ? CupertinoIcons.checkmark : CupertinoIcons.doc_on_doc, size: 18, color: brand.accentText),
        ),
      ]),
    );
  }
}
