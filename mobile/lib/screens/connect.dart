import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/connection.dart' show defaultServer;
import '../relay.dart';

/// Opens the camera and returns the code it read.
typedef Scanner = Future<String?> Function(BuildContext context);

/// Sign in to connect, or scan or paste a key from *Add a device*. The sending switch opens it the first time, and it
/// closes with true once the phone keeps a key.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.relay, Scanner? scanner}) : scanner = scanner ?? _scan;

  final Relay relay;
  /// Opens the camera and returns the code it read; a test passes its own.
  final Scanner scanner;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

Future<String?> _scan(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<String>(builder: (_) => const _ScanPage()));

class _ConnectScreenState extends State<ConnectScreen> {
  final _code = TextEditingController();
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
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
    if (problem == null && widget.relay.connected) Navigator.of(context).pop(true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Relay Everything')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Sign in to Relay Everything, then tap Connect. This phone gets its own key, which can send but not read.'),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _busy ? null : () => _signIn(defaultServer), icon: const Icon(Icons.login),
          label: Text(_busy ? 'Connecting…' : 'Sign in to connect')),
        TextButton(onPressed: _busy ? null : _otherServer, child: const Text('Use another server')),
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),
        const Text('Or use a key from Add a device on your Relay Everything page. The page shows the key once, as a QR code.'),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: _busy ? null : _scanned, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan the QR code')),
        const SizedBox(height: 24),
        TextField(controller: _code, minLines: 2, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Or paste the key', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _busy ? null : () => _connect(_code.text), child: const Text('Connect')),
        if (_problem != null) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ]),
    );
  }
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
