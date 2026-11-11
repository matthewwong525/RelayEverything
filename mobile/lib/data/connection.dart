import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The shared Relay Everything server, where *Sign in* goes. A phone that kept a key for another server still sends there.
const defaultServer = 'https://app.relayeverything.com';

/// Where this phone sends, and its own device key. A key comes in one of two forms: a key the Relay Everything page
/// made (`rek_…`, sent as `Authorization: Bearer`), or an older Cloudflare Access service token (sent in Access's two
/// headers). The phone takes both, so a phone keeps sending while its person moves to a new key.
class Connection {
  /// An older Access service token, from before the page made keys.
  const Connection({required this.server, required String this.clientId, required String this.clientSecret}) : key = null;

  /// A key the phone gets by signing in, or an older one from the Relay Everything page.
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

  /// The code the Relay Everything page shows as a QR code, scanned or pasted. It
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

/// The person's own webhook: an `https://` address, and the `whsec_` secret the phone signs each message with. It needs
/// no Relay Everything account or key.
class Webhook {
  const Webhook({required this.address, required this.secret});

  final String address;
  final String secret;

  String get host => Uri.parse(address).host;

  /// Why [text] can not be a webhook's address, or null when it can. A home or private address, such as
  /// `https://192.168.1.20/relay`, is allowed: only the person's own phone sends to it.
  static String? addressProblem(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != 'https') return 'The address must start with https://.';
    if (uri.userInfo.isNotEmpty) return 'Take the user name and password out of the address.';
    if (uri.host.isEmpty) return 'Enter the whole address, such as https://db.example.com/relay.';
    return null;
  }

  /// Why [text] can not be a secret, or null when it can: `whsec_` and 16 to 64 bytes in base64, as Standard Webhooks
  /// libraries take.
  static String? secretProblem(String text) {
    const problem = 'The secret must be whsec_ and then base64, as your receiver shows it.';
    final value = text.trim();
    if (!value.startsWith('whsec_')) return problem;
    try {
      final bytes = base64.decode(value.substring(6));
      return bytes.length < 16 || bytes.length > 64 ? problem : null;
    } on FormatException {
      return problem;
    }
  }
}

/// The App Group the iPhone app shares with its share extension: a folder, settings, and the Keychain items below.
const appGroup = 'group.com.matthewwong525.relayApp';

/// The key's home: the Keychain on iPhone and the Keystore on Android, never the app's database. On iPhone the key
/// opens after the first unlock since the phone started, so a wake while the phone is locked can still send.
///
/// On iPhone the key lives in the App Group's Keychain group, under its own service name, so the share extension
/// sends with the same key. Earlier versions kept it in the app's own group: [upgrade] moves it once, writing the new
/// items and reading them back before it deletes the old ones. A build with no App Group, such as an unsigned
/// simulator build, keeps using the app's own group.
class KeyVault {
  KeyVault([FlutterSecureStorage? storage, bool? shared])
    : _storage = storage ?? const FlutterSecureStorage(), _shared = shared ?? Platform.isIOS;

  final FlutterSecureStorage _storage;
  /// True on iPhone. Android has one home only, so it never moves anything.
  final bool _shared;
  static const _server = 'relay.server', _id = 'relay.clientId', _secret = 'relay.clientSecret', _key = 'relay.key';
  static const _names = [_server, _id, _secret, _key];
  static const _webhookAddress = 'relay.webhook.address', _webhookSecret = 'relay.webhook.secret';

  /// The service name of the shared items: a different one from the old items', so a delete of an old item never
  /// matches a new one. `ios/ShareExtension/ShareSender.swift` reads the same group and service.
  static const sharedService = 'relay.shared';

  /// The app's own group, where earlier versions kept the key. Every read and write names an accessibility, as the
  /// Keychain's default opens an item only while the phone is unlocked.
  static const iOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device);

  /// The App Group's Keychain group, which the share extension reads too.
  static const sharedOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device,
    groupId: appGroup, accountName: sharedService);

  Future<Connection?> read() async {
    if (_shared) {
      final connection = _parse(await _readShared());
      if (connection != null) return connection;
    }
    return _parse(await _storage.readAll(iOptions: iOptions));
  }

  /// The shared items, or none when this build has no App Group.
  Future<Map<String, String>> _readShared() async {
    try {
      return await _storage.readAll(iOptions: sharedOptions);
    } on PlatformException {
      return const {};
    }
  }

  static Connection? _parse(Map<String, String> values) {
    final server = values[_server], id = values[_id], secret = values[_secret], key = values[_key];
    if (server == null) return null;
    if (key != null) return Connection.bearer(server: server, key: key);
    if (id == null || secret == null) return null;
    return Connection(server: server, clientId: id, clientSecret: secret);
  }

  /// Run it only with the app open, as the phone is unlocked then. On iPhone it moves a key kept in the app's own group
  /// to the shared group: write, read back, then delete the old items. A stop between the steps loses nothing: the
  /// next open finds the new items and deletes what is left of the old. Elsewhere, and with no App Group, it saves the
  /// old items again with [iOptions], so a locked-phone wake can read them. Returns the key, as [read] does.
  Future<Connection?> upgrade() async {
    final old = await _storage.readAll(iOptions: iOptions);
    if (_shared) {
      // Whole shared items only: a stop part way through a move leaves a part, which is moved again.
      final moved = _parse(await _readShared());
      if (moved != null) {
        await _deleteOld(old.keys);
        return moved;
      }
      if (old[_server] != null && await _moveToShared(old)) {
        await _deleteOld(old.keys);
        return read();
      }
    }
    for (final name in _names) {
      final value = old[name];
      if (value != null) await _storage.write(key: name, value: value, iOptions: iOptions);
    }
    return _parse(old);
  }

  /// Writes [values] to the shared group and reads them back. False when they did not all land there.
  Future<bool> _moveToShared(Map<String, String> values) async {
    try {
      for (final name in _names.reversed) {
        final value = values[name];
        if (value != null) await _storage.write(key: name, value: value, iOptions: sharedOptions);
      }
    } on PlatformException {
      return false;
    }
    final back = await _readShared();
    return _names.every((name) => back[name] == values[name]);
  }

  Future<void> _deleteOld(Iterable<String> names) async {
    for (final name in names.where(_names.contains)) {
      await _storage.delete(key: name, iOptions: iOptions);
    }
  }

  /// Saves the key in its own form and removes the other form, so a new key replaces an old one whole. On iPhone it
  /// goes to the shared group, or to the app's own group when the build has none.
  Future<void> save(Connection connection) async {
    if (_shared) {
      try {
        await _save(connection, sharedOptions);
        await _deleteOld(_names);
        return;
      } on PlatformException {
        // No App Group in this build: the app's own group, as before.
      }
    }
    await _save(connection, iOptions);
  }

  Future<void> _save(Connection connection, IOSOptions options) async {
    await _storage.write(key: _server, value: connection.server, iOptions: options);
    final kept = connection.key != null ? {_key: connection.key!} : {_id: connection.clientId!, _secret: connection.clientSecret!};
    for (final name in [_id, _secret, _key]) {
      final value = kept[name];
      value == null ? await _storage.delete(key: name, iOptions: options) : await _storage.write(key: name, value: value, iOptions: options);
    }
  }

  /// Deletes the key from both groups.
  Future<void> forget() async {
    if (_shared) {
      try {
        for (final name in _names) {
          await _storage.delete(key: name, iOptions: sharedOptions);
        }
      } on PlatformException {
        // No App Group in this build: nothing is there.
      }
    }
    for (final name in _names) {
      await _storage.delete(key: name, iOptions: iOptions);
    }
  }

  /// The person's own webhook, kept in the app's own group: the share card never sends to it.
  Future<Webhook?> readWebhook() async {
    final values = await _storage.readAll(iOptions: iOptions);
    final address = values[_webhookAddress], secret = values[_webhookSecret];
    return address == null || secret == null ? null : Webhook(address: address, secret: secret);
  }

  Future<void> saveWebhook(Webhook webhook) async {
    await _storage.write(key: _webhookAddress, value: webhook.address, iOptions: iOptions);
    await _storage.write(key: _webhookSecret, value: webhook.secret, iOptions: iOptions);
  }

  Future<void> forgetWebhook() async {
    await _storage.delete(key: _webhookAddress, iOptions: iOptions);
    await _storage.delete(key: _webhookSecret, iOptions: iOptions);
  }
}
