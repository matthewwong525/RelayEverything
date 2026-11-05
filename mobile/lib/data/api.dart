import 'dart:convert';

import 'package:http/http.dart' as http;

import 'connection.dart';

/// Why a call did not land: the key was refused, the server turned the body down, or the network or server failed.
enum Failure { refused, rejected, offline }

class ApiException implements Exception {
  const ApiException(this.failure, this.status);

  final Failure failure;
  final int? status;

  @override
  String toString() => 'ApiException($failure, $status)';
}

/// Relay's device routes, each call carrying this phone's key in Cloudflare Access's two headers. A device key only
/// adds data: the server refuses it on every route that reads.
class RelayApi {
  RelayApi(this.connection, [http.Client? client]) : _client = client ?? http.Client();

  final Connection connection;
  final http.Client _client;
  static const _timeout = Duration(seconds: 30);

  Uri _uri(String route) => Uri.parse('${connection.server}/apps/relay/api/$route');

  Map<String, String> get _headers =>
    {'CF-Access-Client-Id': connection.clientId, 'CF-Access-Client-Secret': connection.clientSecret, 'Accept': 'application/json'};

  /// Sends one JSON body to a POST route and returns its answer.
  Future<Map<String, dynamic>> post(String route, Map<String, dynamic> body) =>
    _call(() => _client.post(_uri(route), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body)));

  /// Checks this phone's key and returns the device name it was made for. It reads no data.
  Future<String> key() async {
    final json = await _call(() => _client.get(_uri('key'), headers: _headers));
    return json['device'] as String? ?? '';
  }

  Future<Map<String, dynamic>> _call(Future<http.Response> Function() send) async {
    final http.Response response;
    try {
      response = await send().timeout(_timeout);
    } on Exception {
      throw const ApiException(Failure.offline, null);
    }
    final status = response.statusCode;
    // Cloudflare Access answers a refused key with its sign-in page, a redirect or HTML, never JSON.
    final json = response.headers['content-type']?.startsWith('application/json') ?? false;
    if (status == 401 || status == 403 || (status >= 300 && status < 400) || (status == 200 && !json)) {
      throw ApiException(Failure.refused, status);
    }
    if (status == 400 || status == 413) throw ApiException(Failure.rejected, status);
    if (status != 200) throw ApiException(Failure.offline, status);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
