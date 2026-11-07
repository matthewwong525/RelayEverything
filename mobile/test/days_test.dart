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
}
