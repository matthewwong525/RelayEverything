import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../relay.dart';

/// Opens the camera and returns the code it read.
typedef Scanner = Future<String?> Function(BuildContext context);

/// Scan the key's QR code, or paste it. The sending switch opens it the first time, and it closes with true once the
/// phone keeps a key.
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

  Future<void> _connect(String code) async {
    setState(() { _busy = true; _problem = null; });
    final problem = await widget.relay.connect(code);
    if (!mounted) return;
    setState(() { _busy = false; _problem = problem; });
    if (problem == null) Navigator.of(context).pop(true);
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
        const Text('Make a key for this phone on your Relay Everything page: tap Add a device. The page shows the key once, as a QR code.'),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _busy ? null : _scanned, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan the QR code')),
        const SizedBox(height: 24),
        TextField(controller: _code, minLines: 2, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Or paste the key', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _busy ? null : () => _connect(_code.text), child: Text(_busy ? 'Connecting…' : 'Connect')),
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
