import 'api.dart';
import 'store.dart';

/// What one send round did. [failure] is why it stopped early, or null when the outbox emptied.
class FlushResult {
  const FlushResult({this.sent = 0, this.dropped = 0, this.failure});

  final int sent;
  final int dropped;
  final Failure? failure;
}

// Settings shows when health and places last landed, so a person sees when the iPhone stopped them.
const _sentKeys = {'health': sentHealth, 'locations': sentPoints};

/// Sends waiting uploads oldest first, and stops at the first that can not land now, so order holds.
/// A body the server turns down is dropped: it would never land, and would hold back the rest.
/// [keepGoing] is asked before each upload; when it says no, such as after *Stop sending*, the round stops there.
Future<FlushResult> flush(Store store, RelayApi api, {DateTime Function()? clock, bool Function()? keepGoing}) async {
  var sent = 0, dropped = 0;
  for (final item in await store.outbox()) {
    if (keepGoing != null && !keepGoing()) break;
    try {
      await api.post(item.route, item.body);
      sent++;
      final kind = _sentKeys[item.route];
      if (kind != null) await store.set(kind, '${(clock ?? DateTime.now)().millisecondsSinceEpoch}');
    } on ApiException catch (error) {
      if (error.failure != Failure.rejected) return FlushResult(sent: sent, dropped: dropped, failure: error.failure);
      dropped++;
    }
    if (item.route == 'notes') await store.noteSent(item.body['clientId'] as String, (clock ?? DateTime.now)());
    await store.done(item.id);
  }
  return FlushResult(sent: sent, dropped: dropped);
}
