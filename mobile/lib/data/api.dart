import 'dart:convert';

import 'package:http/http.dart' as http;

import 'connection.dart';
import 'store.dart';

/// Why a call did not land: the key was refused, the server turned the body down, or the network or server failed.
enum Failure { refused, rejected, offline }

class ApiException implements Exception {
  const ApiException(this.failure, this.status);

  final Failure failure;
  final int? status;

  @override
  String toString() => 'ApiException($failure, $status)';
}

/// Where the outbox sends: the Relay Everything server, or the person's own webhook. Each call throws [ApiException]:
/// [Failure.rejected] drops the upload, and any other failure stops the round with it kept.
abstract class Outbound {
  /// The outbox destination this client sends to.
  String get destination;

  /// Sends one waiting upload's JSON body.
  Future<void> send(OutboxItem item);

  /// Sends one file of a note: [item] is its `attachment` upload.
  Future<void> sendFile(OutboxItem item, List<int> bytes);
}

/// Relay's device routes, each call carrying this phone's key: `Authorization: Bearer` for a page-made key, or
/// Cloudflare Access's two headers for an older one. A device key only adds data: the server refuses it on every
/// route that reads, but its own key check and the names of what its person connected.
class RelayApi implements Outbound {
  RelayApi(this.connection, [http.Client? client]) : _client = client ?? http.Client();

  @override
  String get destination => relayServer;

  /// A server older than files turns down a note that lists them, so that note goes once more without the list; its
  /// files' uploads then get 404 and are dropped.
  @override
  Future<void> send(OutboxItem item) async {
    final body = _forServer(item.route, item.body);
    try {
      await post(item.route, body);
    } on ApiException catch (error) {
      if (error.failure != Failure.rejected || item.route != 'notes' || body['attachments'] == null) rethrow;
      await post(item.route, {...body}..remove('attachments'));
    }
  }

  @override
  Future<void> sendFile(OutboxItem item, List<int> bytes) => upload(noteClientId: item.body['noteClientId'] as String,
    id: item.body['id'] as String, type: item.body['type'] as String? ?? '', bytes: bytes);

  /// The server numbers its own rows, and its routes take no `id` on a reading or point: the ids are for webhooks.
  static Map<String, dynamic> _forServer(String route, Map<String, dynamic> body) {
    final list = switch (route) { 'health' => 'samples', 'locations' => 'points', _ => null };
    if (list == null) return body;
    return {...body, list: [for (final item in body[list] as List) Map<String, dynamic>.of(item as Map<String, dynamic>)..remove('id')]};
  }

  final Connection connection;
  final http.Client _client;
  static const _timeout = Duration(seconds: 30);
  /// A file can be 25 MB, so its upload may take longer on a slow signal.
  static const _uploadTimeout = Duration(minutes: 5);

  Uri _uri(String route) => Uri.parse('${connection.server}/apps/relay/api/$route');

  Map<String, String> get _headers => {...connection.headers, 'Accept': 'application/json'};

  /// Sends one JSON body to a POST route and returns its answer.
  Future<Map<String, dynamic>> post(String route, Map<String, dynamic> body) =>
    _call(() => _client.post(_uri(route), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body)));

  /// Sends one file's bytes to `POST attachments`, after its note. The server answers 404 for a file its note does not
  /// list, such as against a server from before files: that file can never land, so it counts as turned down.
  Future<Map<String, dynamic>> upload({required String noteClientId, required String id, required String type,
    required List<int> bytes}) =>
    _call(() => _client.post(_uri('attachments'), headers: {..._headers, 'Content-Type': type.isEmpty ? 'application/octet-stream' : type,
      'X-Note-Client-Id': noteClientId, 'X-Attachment-Id': id}, body: bytes), rejected: const {400, 404, 413},
      timeout: _uploadTimeout);

  /// Checks this phone's key and returns the device name it was made for. It reads no data.
  Future<String> key() async {
    final json = await _call(() => _client.get(_uri('key'), headers: _headers));
    return json['device'] as String? ?? '';
  }

  /// The names of the person's AI apps and webhooks: the one read a phone key has, with no data in it.
  Future<Map<String, dynamic>> connections() => _call(() => _client.get(_uri('connections'), headers: _headers));

  /// Trades the sign-in's one-time code, with the secret only this phone holds, for this phone's own key. The call
  /// carries no key: the code and the secret are its proof.
  static Future<Connection> trade(http.Client client, String server, String code, String verifier) async {
    final json = await _answer(() => client.post(Uri.parse('$server/apps/relay/sign-in/phone/key'),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'}, body: jsonEncode({'code': code, 'verifier': verifier})));
    final key = json['key'];
    if (key is! String || !Connection.keyForm.hasMatch(key)) throw const ApiException(Failure.rejected, 200);
    return Connection.bearer(server: server, key: key);
  }

  Future<Map<String, dynamic>> _call(Future<http.Response> Function() send, {Set<int> rejected = const {400, 413},
    Duration timeout = _timeout}) => _answer(send, rejected: rejected, timeout: timeout);

  static Future<Map<String, dynamic>> _answer(Future<http.Response> Function() send, {Set<int> rejected = const {400, 413},
    Duration timeout = _timeout}) async {
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
    if (rejected.contains(status)) throw ApiException(Failure.rejected, status);
    if (status != 200) throw ApiException(Failure.offline, status);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
