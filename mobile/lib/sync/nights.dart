import 'dart:math';

import 'package:health/health.dart';

// Sleep readings grouped into nights, per source, on the phone with no I/O:
// openspec/changes/health-nights-workouts/design.md.

/// Per source, a reading that starts more than this after the open night's end starts a new night.
const gap = Duration(hours: 2);
/// A night that starts within this of the read's start may be cut there: the read that covered its start made it.
const edge = Duration(hours: 2);
/// A night keeps at most this many timeline steps, its first ones.
const maxSteps = 400;

/// Each sleep type's stage. `in_bed` gives the night's span only; `session` is an Android sleep session, which counts
/// as asleep when no stage of the night says how the person slept.
const stageOf = {
  HealthDataType.SLEEP_IN_BED: 'in_bed',
  HealthDataType.SLEEP_SESSION: 'session',
  HealthDataType.SLEEP_ASLEEP: 'asleep',
  HealthDataType.SLEEP_LIGHT: 'core',
  HealthDataType.SLEEP_DEEP: 'deep',
  HealthDataType.SLEEP_REM: 'rem',
  HealthDataType.SLEEP_AWAKE: 'awake',
  HealthDataType.SLEEP_AWAKE_IN_BED: 'awake',
  HealthDataType.SLEEP_OUT_OF_BED: 'awake',
};

const _asleepKinds = {'asleep', 'core', 'deep', 'rem'};

/// One sleep reading: a [stage] of [stageOf] from [start] to [end], written by [source].
class SleepReading {
  const SleepReading(this.source, this.stage, this.start, this.end);

  final String source;
  final String stage;
  final DateTime start;
  final DateTime end;
}

/// One step of a night's timeline.
typedef NightStep = ({String stage, DateTime start, DateTime end});

/// One night or nap of one source: its times, its minutes in each stage, and its timeline.
class Night {
  const Night({required this.source, required this.start, required this.end, this.asleepAt, this.wokeAt,
    required this.asleep, required this.core, required this.deep, required this.rem, required this.awake,
    required this.stages});

  final String source;
  final DateTime start, end;
  final DateTime? asleepAt, wokeAt;
  final double asleep, core, deep, rem, awake;
  final List<NightStep> stages;

  /// The body of `POST nights`, one night.
  Map<String, dynamic> toJson() => {
    'source': source, 'start': start.millisecondsSinceEpoch, 'end': end.millisecondsSinceEpoch,
    'asleepAt': ?asleepAt?.millisecondsSinceEpoch, 'wokeAt': ?wokeAt?.millisecondsSinceEpoch,
    'asleep': asleep, 'core': core, 'deep': deep, 'rem': rem, 'awake': awake,
    'stages': [for (final step in stages)
      {'stage': step.stage, 'start': step.start.millisecondsSinceEpoch, 'end': step.end.millisecondsSinceEpoch}],
  };
}

/// The nights in [readings], by start. A read from [from] leaves out each night that starts within [edge] of it, and
/// each that starts at or after [until], which a newer read made.
List<Night> nightsOf(List<SleepReading> readings, {required DateTime from, DateTime? until}) {
  final sorted = [for (final reading in readings) if (!reading.end.isBefore(reading.start)) reading]
    ..sort((a, b) => a.start.compareTo(b.start));
  final groups = <List<SleepReading>>[];
  final open = <String, (List<SleepReading>, DateTime)>{};
  for (final reading in sorted) {
    final current = open[reading.source];
    if (current != null && !reading.start.isAfter(current.$2.add(gap))) {
      current.$1.add(reading);
      open[reading.source] = (current.$1, reading.end.isAfter(current.$2) ? reading.end : current.$2);
    } else {
      final group = [reading];
      groups.add(group);
      open[reading.source] = (group, reading.end);
    }
  }
  final first = from.add(edge);
  return [
    for (final group in groups)
      if (!group.first.start.isBefore(first) && (until == null || group.first.start.isBefore(until))) _night(group),
  ];
}

Night _night(List<SleepReading> group) {
  List<_Span> spans(bool Function(String stage) take) =>
    _union([for (final reading in group) if (take(reading.stage)) (reading.start.millisecondsSinceEpoch, reading.end.millisecondsSinceEpoch)]);
  final asleep = spans(_asleepKinds.contains), awake = spans((stage) => stage == 'awake');
  final sessions = spans((stage) => stage == 'session');
  // An Android session with no stage that says how the person slept counts as asleep, less the awake time in it.
  final slept = asleep.isNotEmpty ? asleep : sessions;
  return Night(
    source: group.first.source,
    start: group.first.start,
    end: group.map((reading) => reading.end).reduce((a, b) => a.isAfter(b) ? a : b),
    asleepAt: slept.isEmpty ? null : DateTime.fromMillisecondsSinceEpoch(slept.first.$1),
    wokeAt: slept.isEmpty ? null : DateTime.fromMillisecondsSinceEpoch(slept.last.$2),
    asleep: asleep.isNotEmpty ? _minutes(asleep) : _minutes(sessions) - _overlap(sessions, awake),
    core: _minutes(spans((stage) => stage == 'core')),
    deep: _minutes(spans((stage) => stage == 'deep')),
    rem: _minutes(spans((stage) => stage == 'rem')),
    awake: _minutes(awake),
    stages: _timeline(group),
  );
}

/// The stages in time order: a reading that overlaps the step before starts where it ends, and touching steps of
/// one stage join.
List<NightStep> _timeline(List<SleepReading> group) {
  final steps = <NightStep>[];
  for (final reading in group) {
    if (!_asleepKinds.contains(reading.stage) && reading.stage != 'awake') continue;
    final last = steps.isEmpty ? null : steps.last;
    final start = last != null && last.end.isAfter(reading.start) ? last.end : reading.start;
    if (!reading.end.isAfter(start)) continue;
    if (last != null && last.stage == reading.stage && last.end == start) {
      steps.last = (stage: last.stage, start: last.start, end: reading.end);
    } else {
      steps.add((stage: reading.stage, start: start, end: reading.end));
    }
  }
  return steps.take(maxSteps).toList();
}

typedef _Span = (int, int);

/// [spans] as sorted spans that never overlap.
List<_Span> _union(List<_Span> spans) {
  spans.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <_Span>[];
  for (final span in spans) {
    if (merged.isNotEmpty && span.$1 <= merged.last.$2) {
      merged.last = (merged.last.$1, max(merged.last.$2, span.$2));
    } else {
      merged.add(span);
    }
  }
  return merged;
}

double _minutes(List<_Span> spans) => spans.fold(0, (sum, span) => sum + span.$2 - span.$1) / 60000;

/// The minutes two lists of [_union] spans share.
double _overlap(List<_Span> a, List<_Span> b) {
  var shared = 0;
  for (final x in a) {
    for (final y in b) {
      shared += max(0, min(x.$2, y.$2) - max(x.$1, y.$1));
    }
  }
  return shared / 60000;
}
