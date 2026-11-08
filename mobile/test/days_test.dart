import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/screens/days.dart';

void main() {
  final now = DateTime(2026, 11, 7, 9, 41);

  test('groups by day at each edge, midnight included', () {
    expect({
      for (final at in [
        DateTime(2026, 11, 7, 0, 0), DateTime(2026, 11, 6, 23, 59), DateTime(2026, 11, 6, 0, 0), DateTime(2026, 11, 5, 23, 59),
        DateTime(2026, 10, 31, 0, 0), DateTime(2026, 10, 30, 23, 59), DateTime(2026, 10, 8), DateTime(2026, 10, 7, 23, 59),
        DateTime(2026, 1, 2), DateTime(2025, 12, 31, 23, 59),
      ]) at.toString(): dayGroup(at, now),
    }.values, [
      'Today', 'Yesterday', 'Yesterday', 'Previous 7 days',
      'Previous 7 days', 'Previous 30 days', 'Previous 30 days', 'October',
      'January', 'December 2025',
    ]);
    // A note dated after now, such as from a phone whose clock moved back, stays under Today.
    expect(dayGroup(DateTime(2026, 11, 8), now), 'Today');
  });

  test('cuts newest-first notes into runs by day', () {
    final entries = [for (final day in [7, 7, 6, 2]) Entry(text: '$day', at: DateTime(2026, 11, day, 8))];
    expect([for (final (name, notes) in groupByDay(entries, now)) '$name ${notes.length}'],
      ['Today 2', 'Yesterday 1', 'Previous 7 days 1']);
  });

  test('search finds words, the place and file names, in any case', () {
    final note = Entry(text: 'Paint colours for the hall', at: now, place: 'Home',
      files: const [EntryFile(name: 'Swatches.pdf', type: 'application/pdf', size: 1, path: '/nowhere/Swatches.pdf')]);
    for (final words in ['PAINT', 'hall', 'home', 'swatches', '  colours  ', '']) {
      expect(entryMatches(note, words), isTrue, reason: words);
    }
    expect(entryMatches(note, 'dentist'), isFalse);
    expect(entryMatches(Entry(text: 'No place', at: now), 'home'), isFalse);
  });

  test('says Sent, Waiting to send, or nothing', () {
    expect([sendState(Entry(text: '', at: now, sent: true)), sendState(Entry(text: '', at: now, waiting: true)),
      sendState(Entry(text: '', at: now))], ['Sent', 'Waiting to send', null]);
  });

  test('a share is a note with a photo, a file or a link; a voice note is only in Voice notes and Notes', () {
    const photo = EntryFile(name: 'receipt.jpg', type: 'image/jpeg', size: 1, path: '/nowhere/receipt.jpg');
    final notes = {
      'typed': Entry(text: 'Buy milk', at: now),
      'voice': Entry(text: 'Call the fab', at: now, voice: true),
      'photo': Entry(text: '', at: now, files: const [photo]),
      'link': Entry(text: 'Read HTTPS://example.com/post later', at: now),
      'no link': Entry(text: 'The http header is long', at: now),
    };
    List<String> inFolder(NotesFolder folder) => [for (final MapEntry(:key, :value) in notes.entries) if (entryIn(folder, value)) key];
    expect(inFolder(NotesFolder.all), notes.keys);
    expect(inFolder(NotesFolder.voice), ['voice']);
    expect(inFolder(NotesFolder.shares), ['photo', 'link']);
    expect([for (final folder in NotesFolder.values) folder.title], ['Notes', 'Voice notes', 'Shares']);
  });
}
