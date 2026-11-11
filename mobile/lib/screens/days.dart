import '../editor/markdown.dart' show plainText;
import '../relay.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
  'November', 'December'];

/// Whole days from [at]'s date to [now]'s date: 0 today, 1 yesterday. In UTC, so a clock change does not shift a day.
int daysAgo(DateTime at, DateTime now) =>
  DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(at.year, at.month, at.day)).inDays;

/// The heading a note at [at] goes under, as Apple Notes groups: *Today*, *Yesterday*, *Previous 7 days*, *Previous 30
/// days*, then the month, with the year when it was an earlier year.
String dayGroup(DateTime at, DateTime now) {
  final days = daysAgo(at, now);
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days <= 7) return 'Previous 7 days';
  if (days <= 30) return 'Previous 30 days';
  final month = _months[at.month - 1];
  return at.year == now.year ? month : '$month ${at.year}';
}

/// [entries], newest first, cut into runs that share a [dayGroup].
List<(String, List<Entry>)> groupByDay(List<Entry> entries, DateTime now) {
  final groups = <(String, List<Entry>)>[];
  for (final entry in entries) {
    final name = dayGroup(entry.at, now);
    if (groups.isEmpty || groups.last.$1 != name) groups.add((name, []));
    groups.last.$2.add(entry);
  }
  return groups;
}

/// Search on the phone: true when [entry]'s words, place or a file name hold [query], in any case.
bool entryMatches(Entry entry, String query) {
  final words = query.trim().toLowerCase();
  if (words.isEmpty) return true;
  return [plainText(entry.text), entry.place ?? '', for (final file in entry.files) file.name]
    .any((part) => part.toLowerCase().contains(words));
}

/// *Waiting to send* for a note the server does not have yet while sending is on, else null: a sent note's row says
/// nothing about sending.
String? sendState(Entry entry) => !entry.sent && entry.waiting ? 'Waiting to send' : null;

/// The notes list's filters: three views of the same notes, with no new kind of note. A photo or a file never moves a
/// note: it stays in *All*, and shows under *Photos and files* too.
enum NotesFolder {
  all('All'), voice('Voice'), files('Photos and files');

  const NotesFolder(this.title);

  final String title;
}

/// True when [entry] is in [folder]: every note is in *All*, a voice note in *Voice*, and a note with a photo or a
/// file in *Photos and files*. A link alone is not a file: a typed note with a link is still a typed note.
bool entryIn(NotesFolder folder, Entry entry) => switch (folder) {
  NotesFolder.all => true,
  NotesFolder.voice => entry.voice,
  NotesFolder.files => entry.files.isNotEmpty,
};
