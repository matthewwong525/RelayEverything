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
  return [entry.text, entry.place ?? '', for (final file in entry.files) file.name]
    .any((part) => part.toLowerCase().contains(words));
}

/// *Sent* or *Waiting to send*, or null while nothing of it goes anywhere.
String? sendState(Entry entry) => entry.sent ? 'Sent' : entry.waiting ? 'Waiting to send' : null;

/// The notes folders on Home: three views of the same notes, with no new kind of note.
enum NotesFolder {
  all('Notes'), voice('Voice notes'), shares('Shares');

  const NotesFolder(this.title);

  final String title;
}

final _link = RegExp(r'https?://', caseSensitive: false);

/// True when [entry] is in [folder]: every note is in *Notes*, a voice note in *Voice notes*, and a note with a photo,
/// a file or a link in *Shares*. The phone keeps no mark of which notes came from the share button.
bool entryIn(NotesFolder folder, Entry entry) => switch (folder) {
  NotesFolder.all => true,
  NotesFolder.voice => entry.voice,
  NotesFolder.shares => entry.files.isNotEmpty || _link.hasMatch(entry.text),
};
