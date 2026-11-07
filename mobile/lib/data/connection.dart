import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The shared Relay Everything server, where *Sign in to connect* goes unless the person names their own.
const defaultServer = 'https://app.relayeverything.com';

/// Where this phone sends, and its own device key. A key comes in one of two forms: a key the Relay Everything page
/// made (`rek_…`, sent as `Authorization: Bearer`), or an older Cloudflare Access service token (sent in Access's two
/// headers). The phone takes both, so a phone keeps sending while its person moves to a new key.
class Connection {
  /// An Access service token, made by `relay-device-key.mjs create`.
  const Connection({required this.server, required String this.clientId, required String this.clientSecret}) : key = null;

  /// A key from *Add a device* on the Relay Everything page.
  const Connection.bearer({required this.server, required String this.key}) : clientId = null, clientSecret = null;

  final String server;
  final String? clientId;
  final String? clientSecret;
  final String? key;

  /// The form of a page-made key: `rek_` and 32 random bytes in base64url, with no padding.
  static final keyForm = RegExp(r'^rek_[A-Za-z0-9_-]{43}$');

  Connection withServer(String server) =>
    key != null ? Connection.bearer(server: server, key: key!) : Connection(server: server, clientId: clientId!, clientSecret: clientSecret!);

  /// The headers that carry this key on every call.
  Map<String, String> get headers =>
    key != null ? {'Authorization': 'Bearer $key'} : {'CF-Access-Client-Id': clientId!, 'CF-Access-Client-Secret': clientSecret!};

  /// The code the Relay Everything page or `relay-device-key.mjs create` shows as a QR code, scanned or pasted. It
  /// holds either `key` or both `clientId` and `clientSecret`, never both forms. Null when it is not one.
  static Connection? parse(String text) {
    try {
      final code = jsonDecode(text.trim());
      if (code is! Map || code['relay'] != 1) return null;
      final server = serverOf(code['server']);
      if (server == null) return null;
      final key = code['key'], id = code['clientId'], secret = code['clientSecret'];
      if (key != null) {
        if (id != null || secret != null || key is! String || !keyForm.hasMatch(key)) return null;
        return Connection.bearer(server: server, key: key);
      }
      if (id is! String || secret is! String || id.isEmpty || secret.isEmpty) return null;
      return Connection(server: server, clientId: id, clientSecret: secret);
    } on FormatException {
      return null;
    }
  }

  /// An https address with no path, as the app sends to; null for anything else.
  static String? serverOf(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || (uri.path.isNotEmpty && uri.path != '/') || uri.hasQuery) return null;
    return uri.origin;
  }
}

/// The key's home: the Keychain on iPhone and the Keystore on Android, never the app's database. On iPhone the key
/// opens after the first unlock since the phone started, so a wake while the phone is locked can still send.
class KeyVault {
  KeyVault([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _server = 'relay.server', _id = 'relay.clientId', _secret = 'relay.clientSecret', _key = 'relay.key';
  static const _names = [_server, _id, _secret, _key];

  /// Every read and write names this, as the Keychain's default opens an item only while the phone is unlocked.
  static const iOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device);

  Future<Connection?> read() async {
    final values = await _storage.readAll(iOptions: iOptions);
    final server = values[_server], id = values[_id], secret = values[_secret], key = values[_key];
    if (server == null) return null;
    if (key != null) return Connection.bearer(server: server, key: key);
    if (id == null || secret == null) return null;
    return Connection(server: server, clientId: id, clientSecret: secret);
  }

  /// Saves a key kept by an earlier version again, with [iOptions], so a locked-phone wake can read it. Run it only
  /// with the app open: the phone is unlocked then, so the old items can be read. Returns the key, as [read] does.
  Future<Connection?> upgrade() async {
    final values = await _storage.readAll(iOptions: iOptions);
    for (final name in _names) {
      final value = values[name];
      if (value != null) await _storage.write(key: name, value: value, iOptions: iOptions);
    }
    return read();
  }

  /// Saves the key in its own form and removes the other form, so a new key replaces an old one whole.
  Future<void> save(Connection connection) async {
    await _storage.write(key: _server, value: connection.server, iOptions: iOptions);
    final kept = connection.key != null ? {_key: connection.key!} : {_id: connection.clientId!, _secret: connection.clientSecret!};
    for (final name in [_id, _secret, _key]) {
      final value = kept[name];
      value == null ? await _storage.delete(key: name, iOptions: iOptions) : await _storage.write(key: name, value: value, iOptions: iOptions);
    }
  }

  Future<void> forget() async {
    for (final key in _names) {
      await _storage.delete(key: key, iOptions: iOptions);
    }
  }
}
