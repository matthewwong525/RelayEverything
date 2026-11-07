import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

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

/// Relay's device routes, each call carrying this phone's key: `Authorization: Bearer` for a page-made key, or
/// Cloudflare Access's two headers for an older one. A device key only adds data: the server refuses it on every
/// route that reads.
class RelayApi {
  RelayApi(this.connection, [http.Client? client]) : _client = client ?? http.Client();

  final Connection connection;
  final http.Client _client;
  static const _timeout = Duration(seconds: 30);
  // A photo is a few hundred kilobytes, which can take longer than a JSON body on a slow network.
  static const _uploadTimeout = Duration(seconds: 120);

  Uri _uri(String route) => Uri.parse('${connection.server}/apps/relay/api/$route');

  Map<String, String> get _headers => {...connection.headers, 'Accept': 'application/json'};

  /// Sends one JSON body to a POST route and returns its answer.
  Future<Map<String, dynamic>> post(String route, Map<String, dynamic> body) =>
    _call(() => _client.post(_uri(route), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body)));

  /// Sends one multipart body to a POST route: the text [fields], and one file part named [file], with its [bytes],
  /// [filename] and [contentType]. A refusal is named the same way as for [post].
  Future<Map<String, dynamic>> upload(String route, Map<String, String> fields,
    {required String file, required List<int> bytes, required String filename, required String contentType}) =>
    _call(() async {
      final request = http.MultipartRequest('POST', _uri(route))
        ..headers.addAll(_headers)
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes(file, bytes, filename: filename, contentType: MediaType.parse(contentType)));
      return http.Response.fromStream(await _client.send(request));
    }, timeout: _uploadTimeout);

  /// Checks this phone's key and returns the device name it was made for. It reads no data.
  Future<String> key() async {
    final json = await _call(() => _client.get(_uri('key'), headers: _headers));
    return json['device'] as String? ?? '';
  }

  /// Trades the sign-in's one-time code, with the secret only this phone holds, for this phone's own key. The call
  /// carries no key: the code and the secret are its proof.
  static Future<Connection> trade(http.Client client, String server, String code, String verifier) async {
    final json = await _answer(() => client.post(Uri.parse('$server/apps/relay/sign-in/phone/key'),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'}, body: jsonEncode({'code': code, 'verifier': verifier})));
    final key = json['key'];
    if (key is! String || !Connection.keyForm.hasMatch(key)) throw const ApiException(Failure.rejected, 200);
    return Connection.bearer(server: server, key: key);
  }

  Future<Map<String, dynamic>> _call(Future<http.Response> Function() send, {Duration timeout = _timeout}) =>
    _answer(send, timeout: timeout);

  static Future<Map<String, dynamic>> _answer(Future<http.Response> Function() send, {Duration timeout = _timeout}) async {
    final http.Response response;
    try {
      response = await send().timeout(timeout);
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
