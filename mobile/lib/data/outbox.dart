import 'dart:io';

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
/// An `attachment` upload sends a note's file from [folder], the app's support folder, after its note. A file the
/// server turns down, or one no longer on the phone, is dropped, and its note stays sent.
/// A server older than files turns down a note that lists them, so that note goes once more without the list; its
/// files' uploads then get 404 and are dropped.
/// [keepGoing] is asked before each upload; when it says no, such as after *Stop sending*, the round stops there.
Future<FlushResult> flush(Store store, RelayApi api, {DateTime Function()? clock, bool Function()? keepGoing,
  Future<Directory> Function()? folder}) async {
  var sent = 0, dropped = 0;
  final now = clock ?? DateTime.now;
  for (final item in await store.outbox()) {
    if (keepGoing != null && !keepGoing()) break;
    try {
      if (item.route == 'attachment') {
        final bytes = await _bytesOf(item.body, folder);
        if (bytes == null) throw const ApiException(Failure.rejected, null);
        await api.upload(noteClientId: item.body['noteClientId'] as String, id: item.body['id'] as String,
          type: item.body['type'] as String? ?? '', bytes: bytes);
      } else {
        await _post(api, item.route, item.body);
      }
      sent++;
      final kind = _sentKeys[item.route];
      if (kind != null) await store.set(kind, '${(clock ?? DateTime.now)().millisecondsSinceEpoch}');
    } on ApiException catch (error) {
      if (error.failure != Failure.rejected) return FlushResult(sent: sent, dropped: dropped, failure: error.failure);
      dropped++;
    }
    if (item.route == 'notes') await store.noteSent(item.body['clientId'] as String, now());
    if (item.route == 'attachment') await store.attachmentSent(item.body['id'] as String, now());
    await store.done(item.id);
  }
  return FlushResult(sent: sent, dropped: dropped);
}

Future<void> _post(RelayApi api, String route, Map<String, dynamic> body) async {
  try {
    await api.post(route, body);
  } on ApiException catch (error) {
    if (error.failure != Failure.rejected || route != 'notes' || body['attachments'] == null) rethrow;
    await api.post(route, {...body}..remove('attachments'));
  }
}

/// A file's bytes, or null when the phone no longer has it.
Future<List<int>?> _bytesOf(Map<String, dynamic> body, Future<Directory> Function()? folder) async {
  final path = body['path'] as String?;
  if (folder == null || path == null || path.isEmpty) return null;
  final file = File('${(await folder()).path}/$path');
  if (!await file.exists()) return null;
  return file.readAsBytes();
}
