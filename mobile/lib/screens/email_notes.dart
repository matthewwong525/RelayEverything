import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../relay.dart';
import 'account.dart' show AccountState, accountOf;
import 'folder.dart';

/// What *Email notes* and its row on Home say it does.
const emailNotesLine = 'Email a note to your own address';

/// What the page says at its top.
const emailNotesAbout = 'Send or forward an email, and it becomes a note, with its files.';

/// The two addresses of *Email notes*, on the phone and the web: the shared notes address, which takes mail only from
/// the person's sign-in [email], and their private address, which takes mail from anyone. Each has *Copy*; with
/// [onNewAddress], as on the web, the private one also has *New address*.
class EmailNotesParts extends StatelessWidget {
  const EmailNotesParts({super.key, this.email, this.sharedAddress, this.privateAddress, this.onNewAddress, this.copy});

  final String? email;
  final String? sharedAddress;
  final String? privateAddress;
  final VoidCallback? onNewAddress;
  /// Puts an address on the clipboard; a test passes its own.
  final Future<void> Function(String text)? copy;

  @override
  Widget build(BuildContext context) {
    Widget address(String text, String line) => ListTile(
      title: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(line),
      trailing: TextButton(onPressed: () => _copy(context, text), style: quietButton(context), child: const Text('Copy')),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (sharedAddress case final shared?) Group(title: email == null ? 'From your sign-in email' : 'From $email', children: [
        address(shared, 'Takes mail only from the email you sign in with.'),
      ]),
      if (privateAddress case final private?) Group(title: 'From any address', children: [
        address(private, 'For a forward rule. Anyone with it can add a note, so keep it private.'),
        if (onNewAddress case final onNewAddress?) Align(alignment: Alignment.centerLeft, child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: TextButton(onPressed: onNewAddress, style: quietButton(context), child: const Text('New address')))),
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

/// *Email notes* on the phone, opened from Home: what it does, then both addresses from what `GET connections` last
/// answered. Signed out it makes no request, shows no address, and offers *Sign in*.
class EmailNotesPage extends StatefulWidget {
  const EmailNotesPage({super.key, required this.relay, this.copy});

  final Relay relay;
  final Future<void> Function(String text)? copy;

  @override
  State<EmailNotesPage> createState() => _EmailNotesPageState();
}

class _EmailNotesPageState extends State<EmailNotesPage> {
  Relay get relay => widget.relay;

  @override
  void initState() {
    super.initState();
    // It asks only while the phone sends to a Relay Everything server.
    relay.refreshConnections();
  }

  @override
  Widget build(BuildContext context) {
    return FolderPage(relay: relay, title: 'Email notes', groups: (context) {
      final brand = brandOf(context);
      final muted = TextStyle(fontSize: 13, color: brand.muted);
      final state = accountOf(relay);
      final connections = state == AccountState.signedIn ? relay.connections : null;
      // A copy kept by an older build, or an older server, says nothing of the addresses: then it shows neither line.
      final none = connections != null && connections.addressesKnown && connections.sharedAddress == null &&
        connections.notesAddress == null;
      return [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(emailNotesAbout, style: muted)),
        if (connections != null) EmailNotesParts(email: connections.email, sharedAddress: connections.sharedAddress,
          privateAddress: connections.notesAddress, copy: widget.copy),
        if (none) Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text('Your Relay Everything server does not take email.', style: muted)),
        if (state != AccountState.signedIn) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 0), child: Text('Sign in to get your addresses.', style: muted)),
          Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton(
            onPressed: () => choosePlace(context, relay, keepWebhook: state == AccountState.webhook),
            child: const Text('Sign in'))),
        ],
      ];
    });
  }
}
