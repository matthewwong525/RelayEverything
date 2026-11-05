import 'api.dart';
import 'connection.dart';
import 'settings.dart';

/// The one way to the Relay server. It gives no API client while sending is off, so no screen or job can call the
/// network on its own.
class Sender {
  Sender([RelayApi Function(Connection)? apiFor]) : _apiFor = apiFor ?? RelayApi.new;

  final RelayApi Function(Connection) _apiFor;

  /// The client for [connection], or null while sending is off or no key is kept.
  RelayApi? api(Settings settings, Connection? connection) =>
    settings.sending && connection != null ? _apiFor(connection) : null;

  /// Tries a key the person scanned or pasted. Only the connect screen calls it, and only the sending switch opens
  /// that screen.
  RelayApi check(Connection connection) => _apiFor(connection);
}
