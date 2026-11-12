import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

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

/// Where the outbox and the photos send: the Relay Everything server, or the person's own webhook. Each call throws
/// [ApiException]: [Failure.rejected] drops the upload, and any other failure stops the round with it kept.
abstract class Outbound {
  /// The outbox destination this client sends to.
  String get destination;

  /// Sends one waiting upload's JSON body.
  Future<void> send(OutboxItem item);

  /// Sends one file of a note: [item] is its `attachment` upload.
  Future<void> sendFile(OutboxItem item, List<int> bytes);

  /// Sends one photo from *Photos*: its JPEG copy's [bytes], with its time and place.
  Future<void> sendPhoto(QueuedPhoto photo, List<int> bytes);
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
    if (item.route == noteUpdate) return _change(item.body);
    if (item.route == noteDelete) return _delete(item.body);
    if (item.route == notePin) {
      await pin(item.body);
      return;
    }
    final body = _forServer(item.route, item.body);
    try {
      await post(item.route, body);
    } on ApiException catch (error) {
      if (error.failure != Failure.rejected || item.route != 'notes' || body['attachments'] == null) rethrow;
      await post(item.route, {...body}..remove('attachments'));
    }
  }

  /// A sent note's newest words, edit time and the file list the store gave it, by its server `id` once a pull saved one,
  /// else by its `clientId`. A 404 (no such note, or an old server) or a 409 (a newer change is kept) is dropped; the
  /// pull then takes it. A 400 with files, as when a new key made this phone another device, goes once more without
  /// them, so the words still land.
  Future<void> _change(Map<String, dynamic> body) async {
    try {
      await _patchNote(body, withFiles: true);
    } on ApiException catch (error) {
      if (error.status != 400 || body['attachments'] == null) rethrow;
      await _patchNote(body, withFiles: false);
    }
  }

  Future<void> _patchNote(Map<String, dynamic> body, {required bool withFiles}) => _call(() => _client.patch(_uri('notes'),
    headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode({
      if (body['id'] != null) 'id': body['id'] else 'clientId': body['clientId'],
      'text': body['text'], if (body['editedAt'] != null) 'editedAt': body['editedAt'],
      if (withFiles && body['attachments'] != null) 'attachments': body['attachments']})),
    rejected: const {400, 404, 409, 413});

  /// A note deleted on the phone, by its server `id` once a pull saved one, else by its `clientId`. A 404 (deleted
  /// already, never landed, or an old server) is dropped: the note is gone either way.
  Future<void> _delete(Map<String, dynamic> body) => _call(() => _client.delete(_uri('notes').replace(queryParameters: {
      if (body['id'] != null) 'id': body['id'] as String else 'clientId': body['clientId'] as String}), headers: _headers),
    rejected: const {400, 404});

  /// A note's pin, by its server `id` once a pull saved one, else by its `clientId`, and gives when the server says the
  /// pin changed, by its own clock. A 404 (no such note) or a 409 (a newer pin change is kept) is dropped; the pull then
  /// takes the server's pin. A server older than pins refuses a phone key's PUT as it refuses a turned-off key, so a
  /// refusal asks `GET key`: a key that answers means an older server, and the pin is dropped, so the rest still sends.
  Future<int?> pin(Map<String, dynamic> body) async {
    try {
      final answer = await _call(() => _client.put(_uri('notes/pin'), headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({if (body['id'] != null) 'id': body['id'] else 'clientId': body['clientId'], 'pinned': body['pinned'],
          'at': body['at']})), rejected: const {400, 404, 409});
      return answer['pinChangedAt'] as int?;
    } on ApiException catch (error) {
      if (error.failure != Failure.refused) rethrow;
      await key();
      throw ApiException(Failure.rejected, error.status);
    }
  }

  @override
  Future<void> sendFile(OutboxItem item, List<int> bytes) => upload(noteClientId: item.body['noteClientId'] as String,
    id: item.body['id'] as String, type: item.body['type'] as String? ?? '', bytes: bytes);

  /// To `POST photos`, once per photo however often it goes: the server keeps a photo by its client id.
  @override
  Future<void> sendPhoto(QueuedPhoto photo, List<int> bytes) => multipart('photos', photo.fields, file: 'photo', bytes: bytes,
    filename: '${photo.clientId}.jpg', contentType: 'image/jpeg');

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
  // A photo is a few hundred kilobytes, which can take longer than a JSON body on a slow network.
  static const _photoTimeout = Duration(seconds: 120);

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

  /// Sends one multipart body to a POST route: the text [fields], and one file part named [file], with its [bytes],
  /// [filename] and [contentType]. A refusal is named the same way as for [post].
  Future<Map<String, dynamic>> multipart(String route, Map<String, String> fields,
    {required String file, required List<int> bytes, required String filename, required String contentType}) =>
    _call(() async {
      final request = http.MultipartRequest('POST', _uri(route))
        ..headers.addAll(_headers)
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes(file, bytes, filename: filename, contentType: MediaType.parse(contentType)));
      return http.Response.fromStream(await _client.send(request));
    }, timeout: _photoTimeout);

  /// Checks this phone's key and returns the device name it was made for. It reads no data.
  Future<String> key() async {
    final json = await _call(() => _client.get(_uri('key'), headers: _headers));
    return json['device'] as String? ?? '';
  }

  /// The names of the person's AI apps and webhooks: the one read a phone key has, with no data in it.
  Future<Map<String, dynamic>> connections() => _call(() => _client.get(_uri('connections'), headers: _headers));

  /// One page of the person's notes that changed after change number [since], oldest change first:
  /// `{notes, next, more}`. A deleted note comes as `{id, clientId, deleted: true}`.
  Future<Map<String, dynamic>> getNotes(int since, {int limit = 100}) => _call(() => _client.get(
    _uri('notes').replace(queryParameters: {'since': '$since', 'limit': '$limit', 'deleted': '1'}), headers: _headers));

  /// The bytes of a note's file [id], or with [audio] the recording of the ring note [id]. A file the server does not
  /// have, such as one still on its way, is [Failure.rejected].
  Future<List<int>> download(String id, {bool audio = false}) async {
    final http.Response response;
    try {
      response = await _client.get(_uri(audio ? 'audio' : 'attachment').replace(queryParameters: {'id': id}),
        headers: connection.headers).timeout(_uploadTimeout);
    } on Exception {
      throw const ApiException(Failure.offline, null);
    }
    final status = response.statusCode;
    // Cloudflare Access answers a refused key with its sign-in page, never a file.
    final page = response.headers['content-type']?.startsWith('text/html') ?? false;
    if (status == 401 || status == 403 || (status >= 300 && status < 400) || (status == 200 && page)) {
      throw ApiException(Failure.refused, status);
    }
    if (status == 404) throw const ApiException(Failure.rejected, 404);
    if (status != 200) throw ApiException(Failure.offline, status);
    return response.bodyBytes;
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
