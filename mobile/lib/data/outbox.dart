import 'dart:convert';
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

// Settings shows when health, places and the calendar last landed, so a person sees when the iPhone stopped them.
const _sentKeys = {'health': sentHealth, nightsRoute: sentHealth, 'locations': sentPoints, staysRoute: sentPoints, 'calendar': sentCalendar};

/// The last time the person's webhook did not take an upload, in the store's `state`, for Settings:
/// `{at, status, file}`. A status of null is no answer; a `file` is one dropped as too large.
const webhookProblemKey = 'webhook.problem';

/// Sends waiting uploads oldest first through [api], and stops at the first that can not land now, so order holds.
/// An upload [api] turns down ([Failure.rejected]) is dropped: it would never land, and would hold back the rest.
/// An `attachment` upload sends a note's file from [folder], the app's support folder, after its note. A file turned
/// down, or one no longer on the phone, is dropped, and its note stays sent.
/// It sends only the uploads for [api]'s own destination, so notes and private data, which may go to two places, each
/// flush apart, in their own order: one place that fails holds back nothing for the other. Each upload is read again
/// just before it goes, so a switch of place in the middle of a round stops it there; so does an upload already gone.
/// [keepGoing] is asked before each upload; when it says no, such as after *Stop sending*, the round stops there.
/// With [private] true it sends only the [privateRoutes] uploads, with false only the notes' own, so a round sends the
/// notes first, and a health upload that fails holds back no note; null sends all.
Future<FlushResult> flush(Store store, Outbound api, {DateTime Function()? clock, bool Function()? keepGoing,
  Future<Directory> Function()? folder, bool? private}) async {
  var sent = 0, dropped = 0;
  final now = clock ?? DateTime.now;
  final webhook = api.destination == ownWebhook;
  for (final listed in await store.outbox(destination: api.destination, private: private)) {
    if (keepGoing != null && !keepGoing()) break;
    // A switch of place can move the outbox while this round runs, and no background round has [keepGoing]: read each
    // upload again, so one moved since the list never goes to the place left.
    final item = await store.outboxItem(listed.id);
    if (item == null || item.destination != api.destination) {
      return FlushResult(sent: sent, dropped: dropped, failure: Failure.offline);
    }
    try {
      if (item.route == 'attachment') {
        final bytes = await _bytesOf(item.body, folder);
        if (bytes == null) throw const ApiException(Failure.rejected, null);
        await api.sendFile(item, bytes);
      } else {
        await api.send(item);
      }
      sent++;
      final kind = _sentKeys[item.route];
      if (kind != null) await store.set(kind, '${now().millisecondsSinceEpoch}');
      if (webhook) await _clearFailure(store);
    } on ApiException catch (error) {
      if (webhook && (error.failure != Failure.rejected || error.status != null)) {
        await store.set(webhookProblemKey, jsonEncode({'at': now().millisecondsSinceEpoch, 'status': error.status,
          if (error.failure == Failure.rejected) 'file': item.body['name']}));
      }
      if (error.failure != Failure.rejected) return FlushResult(sent: sent, dropped: dropped, failure: error.failure);
      dropped++;
    }
    if (item.route == 'notes') await store.noteSent(item.body['clientId'] as String, now());
    if (item.route == 'attachment') await store.attachmentSent(item.body['id'] as String, now());
    await store.finish(item);
  }
  return FlushResult(sent: sent, dropped: dropped);
}

/// A 2xx ends the last failure. A file dropped as too large stays named until the next problem.
Future<void> _clearFailure(Store store) async {
  final kept = await store.get(webhookProblemKey);
  if (kept != null && (jsonDecode(kept) as Map)['file'] == null) await store.remove(webhookProblemKey);
}

/// A file's bytes, or null when the phone no longer has it.
Future<List<int>?> _bytesOf(Map<String, dynamic> body, Future<Directory> Function()? folder) async {
  final path = body['path'] as String?;
  if (folder == null || path == null || path.isEmpty) return null;
  final file = File('${(await folder()).path}/$path');
  if (!await file.exists()) return null;
  return file.readAsBytes();
}
