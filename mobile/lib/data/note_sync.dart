import 'connection.dart';
import 'sender.dart';
import 'settings.dart';
import 'store.dart';

/// Reads the notes changed in the person's space since the last pull, page by page, and gives how many came. It calls
/// nothing unless [Sender.reader] gives a client; [editing], the note open in the editor, keeps the saved place before it.
/// [onPage] runs after each page that brought notes is kept, so a first pull of many pages shows each as it lands.
Future<int> syncNotes(Store store, Sender sender, {required Settings settings, required Connection? connection,
  String? editing, Future<void> Function()? onPage}) async {
  final api = sender.reader(settings, connection: connection);
  if (api == null) return 0;
  var since = int.tryParse(await store.get(noteSyncSeq) ?? '') ?? 0;
  var count = 0, held = false;
  while (true) {
    final page = await api.getNotes(since);
    final notes = [for (final note in (page['notes'] as List?) ?? const []) note as Map<String, dynamic>];
    final next = page['next'] as int? ?? since;
    if (!await store.applyPulled(notes, editing: editing)) held = true;
    if (!held) await store.set(noteSyncSeq, '$next');
    count += notes.length;
    if (notes.isNotEmpty) await onPage?.call();
    if (page['more'] != true || next <= since) return count;
    since = next;
  }
}
