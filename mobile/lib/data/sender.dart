import 'package:http/http.dart' as http;

import 'api.dart';
import 'connection.dart';
import 'settings.dart';

/// The one way to the Relay server. It gives no API client while sending is off, so no screen or job can call the
/// network on its own.
class Sender {
  Sender([RelayApi Function(Connection)? apiFor, http.Client Function()? clientFor])
    : _apiFor = apiFor ?? RelayApi.new, _clientFor = clientFor ?? http.Client.new;

  final RelayApi Function(Connection) _apiFor;
  final http.Client Function() _clientFor;

  /// The client for [connection], or null while sending is off or no key is kept.
  RelayApi? api(Settings settings, Connection? connection) =>
    settings.sending && connection != null ? _apiFor(connection) : null;

  /// Tries a key the person scanned or pasted. Only the connect screen calls it, and only the sending switch opens
  /// that screen.
  RelayApi check(Connection connection) => _apiFor(connection);

  /// Trades a sign-in's code for this phone's key. Only the connect screen's *Sign in to connect* calls it.
  Future<Connection> trade(String server, String code, String verifier) =>
    RelayApi.trade(_clientFor(), server, code, verifier);
}
