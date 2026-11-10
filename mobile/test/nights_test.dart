import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/sync/nights.dart';

/// 23:00, the evening the made-up nights start.
final evening = DateTime.utc(2026, 11, 3, 23);
DateTime at(num minutes) => evening.add(Duration(seconds: (minutes * 60).round()));
int minute(DateTime time) => time.difference(evening).inMinutes;

SleepReading read(String stage, num from, num to, {String source = 'watch'}) => SleepReading(source, stage, at(from), at(to));

/// The nights of a read that started 10 hours before the evening.
List<Night> nights(List<SleepReading> readings) => nightsOf(readings, from: at(-600));

/// A night's timeline as `core 20-70`.
List<String> steps(Night night) => [for (final step in night.stages) '${step.stage} ${minute(step.start)}-${minute(step.end)}'];

/// A night's minutes: asleep, core, deep, REM, awake.
List<double> minutes(Night night) => [night.asleep, night.core, night.deep, night.rem, night.awake];

void main() {
  test('a watch night with stages gives its times, each stage\'s minutes and its timeline', () {
    final night = nights([
      read('in_bed', 5, 475), read('core', 20, 70), read('deep', 70, 145), read('rem', 145, 255), read('awake', 255, 280),
      read('core', 280, 475),
    ]).single;
    expect([minute(night.start), minute(night.end), minute(night.asleepAt!), minute(night.wokeAt!)], [5, 475, 20, 475]);
    expect(minutes(night), [430, 245, 75, 110, 25]);
    expect(steps(night), ['core 20-70', 'deep 70-145', 'rem 145-255', 'awake 255-280', 'core 280-475']);
    expect(night.toJson(), {'source': 'watch', 'start': at(5).millisecondsSinceEpoch, 'end': at(475).millisecondsSinceEpoch,
      'asleepAt': at(20).millisecondsSinceEpoch, 'wokeAt': at(475).millisecondsSinceEpoch, 'asleep': 430.0, 'core': 245.0,
      'deep': 75.0, 'rem': 110.0, 'awake': 25.0, 'stages': [
        for (final (stage, from, to) in [('core', 20, 70), ('deep', 70, 145), ('rem', 145, 255), ('awake', 255, 280), ('core', 280, 475)])
          {'stage': stage, 'start': at(from).millisecondsSinceEpoch, 'end': at(to).millisecondsSinceEpoch},
      ]});
  });

  test('a gap under 2 hours stays one night; over 2 hours makes two', () {
    expect(nights([read('core', 0, 60), read('core', 170, 200)]).length, 1);
    final [first, nap] = nights([read('core', 0, 60), read('core', 190, 220)]);
    expect([minute(first.end), minute(nap.start), nap.asleep], [60, 190, 30]);
  });

  test('a stage inside in_bed, or two readings that overlap, never count twice', () {
    final night = nights([read('in_bed', 0, 480), read('asleep', 30, 450), read('asleep', 100, 200), read('core', 30, 100),
      read('core', 50, 120)]).single;
    expect([night.asleep, night.core, minute(night.start), minute(night.end)], [420, 90, 0, 480]);
  });

  test('an Android session counts its stages, or with none its span less the awake time', () {
    final staged = nights([read('session', 0, 480), read('core', 10, 200), read('deep', 200, 300), read('awake', 300, 320),
      read('rem', 320, 470)]).single;
    expect([...minutes(staged), minute(staged.asleepAt!), minute(staged.wokeAt!)], [440, 190, 100, 150, 20, 10, 470]);
    final bare = nights([read('session', 0, 480)]).single;
    expect([...minutes(bare), minute(bare.asleepAt!), minute(bare.wokeAt!), bare.stages], [480, 0, 0, 0, 0, 0, 480, isEmpty]);
    final woke = nights([read('session', 0, 480), read('awake', 100, 130)]).single;
    expect([woke.asleep, woke.awake, steps(woke)], [450, 30, ['awake 100-130']]);
  });

  test('a phone\'s bedtime alone is a night with 0 asleep and no timeline', () {
    final night = nights([read('in_bed', 0, 480, source: 'phone')]).single;
    expect([night.asleep, night.asleepAt, night.wokeAt, night.stages], [0, null, null, isEmpty]);
    expect(night.toJson().keys, isNot(contains('asleepAt')));
  });

  test('two sources make two nights, and no minutes add up across them', () {
    final [phone, watch] = nights([read('in_bed', -5, 480, source: 'phone'), read('core', 5, 200), read('deep', 200, 470)]);
    expect([phone.source, phone.asleep, watch.source, watch.asleep, watch.deep], ['phone', 0, 'watch', 465, 270]);
  });

  test('a night that starts within 2 hours of the read\'s start, or at its end mark, is left out', () {
    final readings = [read('core', 60, 120), read('core', 400, 460)];
    expect([for (final night in nightsOf(readings, from: at(0))) minute(night.start)], [400]);
    expect([for (final night in nightsOf(readings, from: at(-61))) minute(night.start)], [60, 400]);
    expect([for (final night in nightsOf(readings, from: at(-600), until: at(400))) minute(night.start)], [60]);
  });

  test('the timeline: a later overlapping reading starts where the earlier ends, and touching steps of one stage join', () {
    final night = nights([read('core', 0, 60), read('deep', 40, 100), read('core', 100, 130), read('core', 130, 160),
      read('rem', 150, 170), read('deep', 165, 168)]).single;
    expect(steps(night), ['core 0-60', 'deep 60-100', 'core 100-160', 'rem 160-170']);
    expect([night.core, night.deep, night.rem], [120, 63, 20]);
  });

  test('a timeline over 400 steps keeps its first 400, and its minutes', () {
    final night = nights([for (var i = 0; i < 450; i++) read(i.isEven ? 'core' : 'deep', i, i + 1)]).single;
    expect([night.stages.length, steps(night).last, ...minutes(night)], [maxSteps, 'deep 399-400', 450, 225, 225, 0, 0]);
  });
}
