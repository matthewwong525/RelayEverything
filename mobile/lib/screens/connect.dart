import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../data/connection.dart' show defaultServer;
import '../relay.dart';
import 'back_to.dart';

/// *Sign in*: one *Sign in* button to Relay Everything, and one quiet link, *Don't want an account? Use your own
/// webhook*, which opens the webhook's setup in four steps: the address, the secret to copy, *Send a test*, and *Save*.
/// A phone that keeps a key offers it in one tap. The account card in Settings and a folder's *Sign in* open it, and it
/// closes with the place once that place is set up; leaving it changes nothing. With [privateOnly], *Only to my own
/// webhook* in Webhooks opens the setup alone: its *Save* keeps the webhook and closes with [SendPlace.webhook], and
/// Webhooks sends private data there; notes stay where they go. With [signInOnly], the webhook Account page's *Sign in
/// to Relay Everything* opens the sign-in alone: the phone sends to the webhook already.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.relay, Future<void> Function(String text)? copy,
    this.privateOnly = false, this.signInOnly = false}) : copy = copy ?? _copy;

  final Relay relay;
  /// The webhook's setup for health, places, the calendar and photos only, with no way to sign in.
  final bool privateOnly;
  /// The sign-in with no link to the webhook.
  final bool signInOnly;
  /// Puts the secret on the clipboard; a test passes its own.
  final Future<void> Function(String text) copy;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

Future<void> _copy(String text) => Clipboard.setData(ClipboardData(text: text));

class _ConnectScreenState extends State<ConnectScreen> {
  /// True once the person picked *Don't want an account? Use your own webhook*.
  late bool _webhookOpen = widget.privateOnly;
  late final _address = TextEditingController(text: widget.relay.webhookAddress ?? 'https://');
  late final _secret = TextEditingController(text: widget.relay.webhookSecret ?? widget.relay.newWebhookSecret());
  String? _problem;
  /// The receiver's answer to *Send a test*.
  String? _answer;
  bool _busy = false;

  @override
  void dispose() {
    _address.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _signIn(String server) => _try(() => widget.relay.signIn(server));

  /// A cancelled sign-in answers no problem and keeps no key, so the screen stays open.
  Future<void> _try(Future<String?> Function() connect) async {
    setState(() { _busy = true; _problem = null; });
    final problem = await connect();
    if (!mounted) return;
    setState(() { _busy = false; _problem = problem; });
    if (problem == null && widget.relay.connected) Navigator.of(context).pop(SendPlace.server);
  }

  Future<void> _test() async {
    setState(() { _busy = true; _answer = null; _problem = null; });
    final answer = await widget.relay.testWebhook(_address.text, _secret.text);
    if (!mounted) return;
    setState(() { _busy = false; _answer = answer; });
  }

  Future<void> _saveWebhook() async {
    setState(() { _busy = true; _problem = null; });
    final problem = await widget.relay.saveWebhook(_address.text, _secret.text);
    if (!mounted) return;
    setState(() { _busy = false; _problem = problem; });
    if (problem == null) Navigator.of(context).pop(SendPlace.webhook);
  }

  Future<void> _copySecret() async {
    await widget.copy(_secret.text.trim());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Secret copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return Scaffold(
      appBar: AppBar(leading: const BackTo('Back'), leadingWidth: BackTo.widthOf('Back'),
        title: Text(_webhookOpen ? 'My own webhook' : 'Sign in')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ...switch ((_webhookOpen, widget.relay.connected)) {
          (true, _) => _webhook(),
          (false, true) => _kept(),
          (false, false) => _server(),
        },
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_problem!, style: error)),
      ]),
    );
  }

  void _pick(bool webhook) => setState(() { _webhookOpen = webhook; _problem = null; _answer = null; });

  /// A quiet way in, below the one primary button.
  Widget _quiet(String label, VoidCallback onPressed, [IconData? icon]) => Align(
    alignment: Alignment.centerLeft,
    child: icon == null
      ? TextButton(onPressed: _busy ? null : onPressed, child: Text(label))
      : TextButton.icon(onPressed: _busy ? null : onPressed, icon: Icon(icon), label: Text(label)),
  );

  /// A key is kept already: the server it sends to, and one tap to send there.
  List<Widget> _kept() => [
    Text('This phone has a key for ${widget.relay.server ?? 'your server'}.'),
    const SizedBox(height: 16),
    FilledButton(onPressed: () => Navigator.of(context).pop(SendPlace.server), child: const Text('Send to Relay Everything')),
    if (!widget.signInOnly) ...[
      const SizedBox(height: 16),
      _quiet(_noAccount, () => _pick(true), CupertinoIcons.link),
    ],
  ];

  static const _noAccount = "Don't want an account? Use your own webhook";

  /// A numbered step of the webhook's setup.
  Widget _step(int number, String label) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text('$number. $label', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
  );

  List<Widget> _webhook() => [
    Text(widget.privateOnly
      ? 'The phone sends your health, places, calendar and photos straight to your server. Relay Everything never gets '
        'them. Your notes still sync through Relay Everything.'
      : 'Your notes go straight from this phone to your server. You need no account. Health and places go there too '
        'if you turn them on.'),
    _step(1, "Your webhook's address"),
    TextField(controller: _address, keyboardType: TextInputType.url, autocorrect: false,
      decoration: const InputDecoration(labelText: 'Address', helperText: 'It must start with https://.',
        border: OutlineInputBorder())),
    _step(2, 'Copy this secret to your receiver'),
    Row(spacing: 8, children: [
      Expanded(child: TextField(controller: _secret, autocorrect: false,
        decoration: const InputDecoration(labelText: 'Secret', helperText: 'It checks each message. You can paste your own.',
          border: OutlineInputBorder()))),
      OutlinedButton(onPressed: _busy ? null : _copySecret, child: const Text('Copy')),
    ]),
    _step(3, 'Check that it works'),
    Align(alignment: Alignment.centerLeft,
      child: OutlinedButton(onPressed: _busy ? null : _test, child: const Text('Send a test'))),
    if (_answer != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_answer!)),
    _step(4, 'Save'),
    FilledButton(onPressed: _busy ? null : _saveWebhook, child: const Text('Save')),
    const SizedBox(height: 16),
    Text('The phone sends only while it is on and has signal, so your data comes in groups. Your Relay Everything page '
      'and your AI can not read it.', style: Theme.of(context).textTheme.bodySmall),
    if (!widget.privateOnly) ...[
      const SizedBox(height: 16),
      _quiet('Sign in to Relay Everything instead', () => _pick(false)),
    ],
  ];

  /// One *Sign in*, and below it one quiet link to the webhook. A phone already set to another server keeps it: this
  /// shows only with no key kept.
  List<Widget> _server() => [
    Text(widget.signInOnly
      ? 'Sign in to keep your notes the same on all your devices, and let your AI read them. Health, places, calendar '
        'and photos still go only to your webhook.'
      : 'Sign in to keep your notes the same on all your devices, and let your AI read them.'),
    const SizedBox(height: 16),
    FilledButton(onPressed: _busy ? null : () => _signIn(defaultServer),
      child: Text(_busy ? 'Signing in…' : 'Sign in')),
    if (!widget.signInOnly) ...[
      const SizedBox(height: 16),
      _quiet(_noAccount, () => _pick(true), CupertinoIcons.link),
    ],
    const SizedBox(height: 16),
    Text('Your notes stay on this phone until you sign in.',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: brandOf(context).muted)),
  ];
}
