import 'package:http/http.dart' as http;

import 'api.dart';
import 'connection.dart';
import 'settings.dart';
import 'webhook.dart';

/// The one way out of the phone: to the Relay Everything server, or to the person's own webhook, and for private data
/// maybe the webhook while notes go to the server. It gives no client while sending is off, so no screen or job can
/// call the network on its own.
class Sender {
  Sender([RelayApi Function(Connection)? apiFor, http.Client Function()? clientFor,
    WebhookClient Function(Webhook webhook, String installId)? webhookFor])
    : _apiFor = apiFor ?? RelayApi.new, _clientFor = clientFor ?? http.Client.new,
      _webhookFor = webhookFor ?? ((webhook, installId) => WebhookClient(webhook, installId: installId));

  final RelayApi Function(Connection) _apiFor;
  final http.Client Function() _clientFor;
  final WebhookClient Function(Webhook, String) _webhookFor;

  /// The client for the place [settings] names, or null while sending is off or that place is not set up: no key for
  /// the server, or no webhook. Webhook mode needs no key.
  Outbound? api(Settings settings, {Connection? connection, Webhook? webhook, String? installId}) {
    if (!settings.sending) return null;
    return switch (settings.place) {
      SendPlace.server => connection == null ? null : _apiFor(connection),
      SendPlace.webhook => webhook == null || installId == null ? null : _webhookFor(webhook, installId),
    };
  }

  /// The client for health, location points, calendar events and photos: the same as [api] while they go where notes
  /// go; the person's own webhook while [Settings.privateTo] says so; else null, and they wait on the phone. It never
  /// gives the server's client while [Settings.privatePlace] is the webhook: a missing webhook is no reason to send
  /// them to the server.
  Outbound? privateApi(Settings settings, {Connection? connection, Webhook? webhook, String? installId}) {
    if (!settings.sending) return null;
    if (settings.privatePlace == settings.place) {
      return api(settings, connection: connection, webhook: webhook, installId: installId);
    }
    // Notes go to the server and private data to the webhook: the one other case.
    return webhook == null || installId == null ? null : _webhookFor(webhook, installId);
  }

  /// The server's client for the one read a phone key has, the names of its person's AI apps and webhooks: only while
  /// sending to the Relay Everything server with its key, else null.
  RelayApi? reader(Settings settings, {Connection? connection}) =>
    settings.sending && settings.place == SendPlace.server && connection != null ? _apiFor(connection) : null;

  /// Tries a key the person scanned or pasted. Only the connect screen calls it, and only the choice of place opens
  /// that screen.
  RelayApi check(Connection connection) => _apiFor(connection);

  /// *Send a test* to a webhook. Only the person's tap calls it.
  WebhookClient tryWebhook(Webhook webhook, String installId) => _webhookFor(webhook, installId);

  /// Trades a sign-in's code for this phone's key. Only the connect screen's *Sign in to connect* calls it.
  Future<Connection> trade(String server, String code, String verifier) =>
    RelayApi.trade(_clientFor(), server, code, verifier);
}
