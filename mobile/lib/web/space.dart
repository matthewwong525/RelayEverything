import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Why a call to the person's space did not work: the server's [status], or null when no answer came, and the words to
/// show. A 401 means the browser's sign-in ended.
class SpaceRefused implements Exception {
  const SpaceRefused(this.status, this.message);

  final int? status;
  final String message;

  bool get signedOut => status == 401;

  @override
  String toString() => 'SpaceRefused($status, $message)';
}

/// The words to show when no answer came.
const noAnswer = 'Relay Everything did not answer. Check your connection and try again.';

/// The person's Relay Everything space, read and changed through the page's own routes under [base], such as
/// `https://example.com/apps/relay/`. In the browser the page's sign-in cookie goes with each call by itself, and the
/// browser adds the page's own Origin to each change, which the server needs. Nothing is kept in the browser.
class SpaceClient {
  SpaceClient({required this.base, http.Client? client, this.onSignedOut}) : _client = client ?? http.Client();

  /// The page's own address, ending in `/apps/relay/`.
  final Uri base;
  final http.Client _client;
  /// Runs when a route answers 401: the sign-in ended, so the app shows the sign-in again.
  final void Function()? onSignedOut;

  static const _timeout = Duration(seconds: 30);
  /// A file can be 25 MB, so its upload may take longer.
  static const _uploadTimeout = Duration(minutes: 5);

  /// A route of the person's space, such as `notes`.
  Uri api(String route, [Map<String, String>? query]) {
    final address = base.resolve('api/$route');
    return query == null || query.isEmpty ? address : address.replace(queryParameters: query);
  }

  /// A sign-in route, such as `methods` or `email`.
  Uri signIn(String route, [Map<String, String>? query]) {
    final address = base.resolve('sign-in/$route');
    return query == null || query.isEmpty ? address : address.replace(queryParameters: query);
  }

  static const _json = {'Accept': 'application/json', 'Content-Type': 'application/json'};

  Future<Map<String, dynamic>> get(String route, {Map<String, String>? query}) =>
    _call(() => _client.get(api(route, query), headers: const {'Accept': 'application/json'}));

  Future<Map<String, dynamic>> post(String route, [Object body = const <String, Object>{}]) =>
    _call(() => _client.post(api(route), headers: _json, body: jsonEncode(body)));

  Future<Map<String, dynamic>> patch(String route, Object body) =>
    _call(() => _client.patch(api(route), headers: _json, body: jsonEncode(body)));

  Future<Map<String, dynamic>> put(String route, Object body) =>
    _call(() => _client.put(api(route), headers: _json, body: jsonEncode(body)));

  Future<Map<String, dynamic>> delete(String route, {Map<String, String>? query}) =>
    _call(() => _client.delete(api(route, query), headers: const {'Accept': 'application/json'}));

  /// A POST to any of the page's addresses, such as a sign-in route.
  Future<Map<String, dynamic>> postTo(Uri address, [Object body = const <String, Object>{}]) =>
    _call(() => _client.post(address, headers: _json, body: jsonEncode(body)), signedOutOn401: false);

  /// A GET of any of the page's addresses, such as the sign-in methods.
  Future<Map<String, dynamic>> getFrom(Uri address) =>
    _call(() => _client.get(address, headers: const {'Accept': 'application/json'}), signedOutOn401: false);

  /// Sends one file's [bytes] to a route, with its own [headers], such as `POST attachments`.
  Future<Map<String, dynamic>> upload(String route, List<int> bytes, Map<String, String> headers) =>
    _call(() => _client.post(api(route), headers: {'Accept': 'application/json', ...headers}, body: bytes),
      timeout: _uploadTimeout);

  Future<Map<String, dynamic>> _call(Future<http.Response> Function() send,
    {Duration timeout = _timeout, bool signedOutOn401 = true}) async {
    final http.Response response;
    try {
      response = await send().timeout(timeout);
    } on Exception {
      throw const SpaceRefused(null, noAnswer);
    }
    final status = response.statusCode;
    Object? json;
    try {
      json = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      json = null;
    }
    if (status >= 200 && status < 300) {
      if (json is Map<String, dynamic>) return json;
      if (json == null && response.body.isEmpty) return const {};
      throw SpaceRefused(status, noAnswer);
    }
    if (status == 401 && signedOutOn401) onSignedOut?.call();
    throw SpaceRefused(status, messageOf(json) ?? _plain(status));
  }

  /// The server's own words in a refusal: `{error: {message}}` or `{error: "…"}`.
  static String? messageOf(Object? json) {
    if (json is! Map) return null;
    final error = json['error'];
    if (error is String && error.isNotEmpty) return error;
    if (error is Map && error['message'] is String) return error['message'] as String;
    return null;
  }

  static String _plain(int status) => switch (status) {
    401 => 'Sign in to Relay Everything.',
    403 => 'Relay Everything refused this.',
    404 => 'Relay Everything did not find this.',
    503 => 'This part is not set up on this server.',
    _ => 'Relay Everything could not do this. Try again.',
  };
}
