import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/connection.dart' show defaultServer;
import '../relay.dart';
import 'back_to.dart';

/// Opens the camera and returns the code it read.
typedef Scanner = Future<String?> Function(BuildContext context);

/// *Sign in*: *Sign in to connect* to the person's Relay Everything server, and below it the quiet other ways: *Scan a
/// key* from *Add a device*, *Use another server*, and *Send to my own webhook instead*, which opens the webhook's
/// address and a secret to copy, with *Send a test*. A phone that keeps a key offers it in one tap. The Account row in
/// Settings and a folder's *Sign in* open it, and it closes with the place once that place is set up.
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
  /// True once the person picked *Send to my own webhook instead*.
  bool _webhookOpen = false;
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
    const SizedBox(height: 16),
    _quiet('Send to my own webhook instead', () => _pick(true), CupertinoIcons.link),
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
    const SizedBox(height: 16),
    _quiet('Sign in to Relay Everything instead', () => _pick(false)),
  ];

  List<Widget> _server() => [
    const Text('Sign in to Relay Everything, then tap Connect. This phone gets its own key. It sends your notes and keeps '
      'them the same as on your other devices. Notes stay on this phone until you sign in.'),
    const SizedBox(height: 16),
    FilledButton.icon(onPressed: _busy ? null : () => _signIn(defaultServer), icon: const Icon(CupertinoIcons.arrow_right_square),
      label: Text(_busy ? 'Connecting…' : 'Sign in to connect')),
    const SizedBox(height: 16),
    _quiet('Scan a key', _scanned, CupertinoIcons.qrcode_viewfinder),
    _quiet('Use another server', _otherServer, CupertinoIcons.globe),
    _quiet('Send to my own webhook instead', () => _pick(true), CupertinoIcons.link),
    const SizedBox(height: 24),
    Text('A key comes from Add a device on your Relay Everything page, which shows it once, as a QR code. On this same '
      'phone, copy the key and paste it here.', style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(height: 8),
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
      appBar: AppBar(leading: const BackTo('Back'), leadingWidth: BackTo.widthOf('Back'), title: const Text('Scan the QR code')),
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
