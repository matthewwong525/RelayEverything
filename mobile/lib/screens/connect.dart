import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/connection.dart' show defaultServer;
import '../relay.dart';

/// Opens the camera and returns the code it read.
typedef Scanner = Future<String?> Function(BuildContext context);

/// *Where should the phone send?*: the person's Relay Everything server, or their own webhook. For the server: sign in
/// to connect, or scan or paste a key from *Add a device*. For a webhook: its address and a secret to copy, with *Send a
/// test*. The sending switch opens it, and it closes with the place once that place is set up.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.relay, Scanner? scanner, Future<void> Function(String text)? copy})
    : scanner = scanner ?? _scan, copy = copy ?? _copy;

  final Relay relay;
  /// Opens the camera and returns the code it read; a test passes its own.
  final Scanner scanner;
  /// Puts the secret on the clipboard; a test passes its own.
  final Future<void> Function(String text) copy;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

Future<void> _copy(String text) => Clipboard.setData(ClipboardData(text: text));

Future<String?> _scan(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<String>(builder: (_) => const _ScanPage()));

class _ConnectScreenState extends State<ConnectScreen> {
  final _code = TextEditingController();
  late SendPlace _place = widget.relay.settings.place;
  late final _address = TextEditingController(text: widget.relay.webhookAddress ?? 'https://');
  late final _secret = TextEditingController(text: widget.relay.webhookSecret ?? widget.relay.newWebhookSecret());
  String? _problem;
  /// The receiver's answer to *Send a test*.
  String? _answer;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _address.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _connect(String code) => _try(() => widget.relay.connect(code));

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

  Future<void> _otherServer() async {
    final address = await showDialog<String>(context: context, builder: (context) => const ServerDialog(server: null));
    if (address != null && mounted) await _signIn(address);
  }

  Future<void> _scanned() async {
    final code = await widget.scanner(context);
    if (code != null) await _connect(code);
  }

  @override
  Widget build(BuildContext context) {
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return Scaffold(
      appBar: AppBar(title: const Text('Where should the phone send?')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<SendPlace>(
          segments: const [
            ButtonSegment(value: SendPlace.server, label: Text('Relay Everything')),
            ButtonSegment(value: SendPlace.webhook, label: Text('My own webhook')),
          ],
          selected: {_place},
          onSelectionChanged: _busy ? null : (chosen) => setState(() { _place = chosen.single; _problem = null; }),
        ),
        const SizedBox(height: 16),
        ...switch ((_place, widget.relay.connected)) {
          (SendPlace.webhook, _) => _webhook(),
          (SendPlace.server, true) => _kept(),
          (SendPlace.server, false) => _server(),
        },
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_problem!, style: error)),
      ]),
    );
  }

  /// A key is kept already: the server it sends to, and one tap to send there.
  List<Widget> _kept() => [
    Text('This phone has a key for ${widget.relay.server ?? 'your server'}.'),
    const SizedBox(height: 16),
    FilledButton(onPressed: () => Navigator.of(context).pop(SendPlace.server), child: const Text('Send to Relay Everything')),
  ];

  List<Widget> _webhook() => [
    const Text('The phone sends your notes, their files, and health and places if you turn them on, straight to your '
      'receiver. Nothing goes to Relay Everything, and you need no account.'),
    const SizedBox(height: 16),
    TextField(controller: _address, keyboardType: TextInputType.url, autocorrect: false,
      decoration: const InputDecoration(labelText: 'Address', helperText: 'It must start with https://.',
        border: OutlineInputBorder())),
    const SizedBox(height: 16),
    TextField(controller: _secret, autocorrect: false,
      decoration: const InputDecoration(labelText: 'Secret', border: OutlineInputBorder())),
    const SizedBox(height: 8),
    const Text('Copy the secret to your receiver. It checks each message with it. You can paste your own secret.'),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton(onPressed: _busy ? null : _copySecret, child: const Text('Copy')),
      OutlinedButton(onPressed: _busy ? null : _test, child: const Text('Send a test')),
      FilledButton(onPressed: _busy ? null : _saveWebhook, child: const Text('Save')),
    ]),
    if (_answer != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_answer!)),
    const SizedBox(height: 16),
    Text('The phone sends only while it is on and has signal, so your data comes in groups. Your Relay Everything page '
      'and your AI can not read it.', style: Theme.of(context).textTheme.bodySmall),
  ];

  List<Widget> _server() => [
    const Text('Sign in to Relay Everything, then tap Connect. This phone gets its own key, which can send but not read.'),
    const SizedBox(height: 16),
    FilledButton.icon(onPressed: _busy ? null : () => _signIn(defaultServer), icon: const Icon(Icons.login),
      label: Text(_busy ? 'Connecting…' : 'Sign in to connect')),
    TextButton(onPressed: _busy ? null : _otherServer, child: const Text('Use another server')),
    const SizedBox(height: 24),
    Text('Or', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8),
    const Text('Use a key from Add a device on your Relay Everything page. The page shows the key once, as a QR code.'),
    const SizedBox(height: 16),
    OutlinedButton.icon(onPressed: _busy ? null : _scanned, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan the QR code')),
    const SizedBox(height: 24),
    TextField(controller: _code, minLines: 2, maxLines: 4,
      decoration: const InputDecoration(labelText: 'Or paste the key', border: OutlineInputBorder())),
    const SizedBox(height: 8),
    OutlinedButton(onPressed: _busy ? null : () => _connect(_code.text), child: const Text('Connect')),
  ];
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan the QR code')),
      body: MobileScanner(onDetect: (capture) {
        final code = capture.barcodes.map((barcode) => barcode.rawValue).whereType<String>().firstOrNull;
        if (code == null || _done) return;
        _done = true;
        Navigator.of(context).pop(code);
      }),
    );
  }
}

/// A server's address, typed. Owns its text field, so the field lives until the dialog's closing animation ends.
class ServerDialog extends StatefulWidget {
  const ServerDialog({super.key, required this.server});

  final String? server;

  @override
  State<ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<ServerDialog> {
  late final _text = TextEditingController(text: widget.server ?? 'https://');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server'),
      content: TextField(controller: _text, keyboardType: TextInputType.url, autofocus: true,
        decoration: const InputDecoration(helperText: 'Your own server, or a preview address to try a change.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('Save')),
      ],
    );
  }
}
