import 'dart:io';

import 'package:health/health.dart';

import '../data/store.dart';

/// The health types Relay keeps, by the server's names. iPhone splits sleep by stage; Android has whole sessions. Each
/// phone keeps its own heart rate variability measure: iPhone SDNN, Android RMSSD, which can not be compared. Android's
/// health store gives no mindful minutes to the app.
final Map<HealthDataType, String> kinds = {
  HealthDataType.STEPS: 'steps',
  HealthDataType.HEART_RATE: 'heart_rate',
  HealthDataType.WORKOUT: 'workout',
  HealthDataType.WEIGHT: 'weight',
  HealthDataType.RESTING_HEART_RATE: 'resting_heart_rate',
  HealthDataType.BLOOD_OXYGEN: 'blood_oxygen',
  HealthDataType.BLOOD_PRESSURE_SYSTOLIC: 'blood_pressure_systolic',
  HealthDataType.BLOOD_PRESSURE_DIASTOLIC: 'blood_pressure_diastolic',
  HealthDataType.MENSTRUATION_FLOW: 'cycle_flow',
  HealthDataType.WATER: 'water',
  if (Platform.isAndroid) ...{HealthDataType.SLEEP_SESSION: 'sleep', HealthDataType.HEART_RATE_VARIABILITY_RMSSD: 'hrv_rmssd'}
  else ...{HealthDataType.SLEEP_ASLEEP: 'sleep', HealthDataType.SLEEP_LIGHT: 'sleep', HealthDataType.SLEEP_DEEP: 'sleep',
    HealthDataType.SLEEP_REM: 'sleep', HealthDataType.HEART_RATE_VARIABILITY_SDNN: 'hrv_sdnn',
    HealthDataType.MINDFULNESS: 'mindful'},
};

const _units = {
  'steps': 'count', 'heart_rate': 'bpm', 'sleep': 'min', 'workout': 'min', 'weight': 'kg', 'resting_heart_rate': 'bpm',
  'hrv_sdnn': 'ms', 'hrv_rmssd': 'ms', 'blood_oxygen': '%', 'blood_pressure_systolic': 'mmHg',
  'blood_pressure_diastolic': 'mmHg', 'cycle_flow': 'flow', 'mindful': 'min', 'water': 'ml',
};

// These types are a span of time: their value is its length in minutes.
const _spans = {'sleep', 'workout', 'mindful'};

/// Cycle flow as a number: 0 none, 1 light, 2 medium, 3 heavy. Unspecified and spotting count as light.
int flowOf(MenstrualFlow? flow) => switch (flow) {
  MenstrualFlow.none => 0,
  MenstrualFlow.medium => 2,
  MenstrualFlow.heavy => 3,
  _ => 1,
};

/// One reading as the server's `health` route takes it, or null for a type Relay does not keep. Blood oxygen goes as a
/// percent, 0 to 100: iPhone gives a fraction. Water goes in ml: the health package gives litres.
Map<String, dynamic>? sampleOf(HealthDataPoint point) {
  final kind = kinds[point.type];
  if (kind == null) return null;
  final minutes = point.dateTo.difference(point.dateFrom).inSeconds / 60;
  final value = point.value;
  final amount = switch (kind) {
    _ when _spans.contains(kind) => minutes,
    'cycle_flow' => value is MenstruationFlowHealthValue ? flowOf(value.flow).toDouble() : null,
    _ => value is NumericHealthValue ? _scaled(kind, value.numericValue.toDouble()) : null,
  };
  if (amount == null || amount < 0) return null;
  final source = point.sourceId.isNotEmpty ? point.sourceId : point.sourceName;
  return {
    'type': kind, 'start': point.dateFrom.millisecondsSinceEpoch, 'end': point.dateTo.millisecondsSinceEpoch,
    'value': amount, 'unit': _units[kind], 'source': source.isEmpty ? 'unknown' : source.substring(0, source.length.clamp(0, 200)),
  };
}

double _scaled(String kind, double value) => switch (kind) {
  'blood_oxygen' when value <= 1 => value * 100,
  'water' => value * 1000,
  _ => value,
};

/// The types this app asks for, by the server's names: the store keeps the list it last asked for under [healthTypes],
/// so a phone that allowed health before new types came is asked once more.
String get askedTypes => (kinds.values.toSet().toList()..sort()).join(',');

/// Where readings come from: the phone's health store, or a test's list.
abstract class HealthSource {
  Future<bool> allow();
  Future<List<HealthDataPoint>> read(DateTime from, DateTime to);
}

class PhoneHealth implements HealthSource {
  final _health = Health();

  @override
  Future<bool> allow() async {
    await _health.configure();
    final types = kinds.keys.toList();
    final allowed = await _health.requestAuthorization(types, permissions: [for (final _ in types) HealthDataAccess.READ]);
    // The hourly sync reads with no screen open, which Health Connect allows only with this second permission.
    if (allowed && Platform.isAndroid && await _health.isHealthDataInBackgroundAvailable()) {
      await _health.requestHealthDataInBackgroundAuthorization();
    }
    return allowed;
  }

  @override
  Future<List<HealthDataPoint>> read(DateTime from, DateTime to) async {
    await _health.configure();
    return _health.getHealthDataFromTypes(types: kinds.keys.toList(), startTime: from, endTime: to);
  }
}

const healthSince = 'health.since';
/// The oldest moment the 90-day history read reached, while it still goes back.
const healthBackfill = 'health.backfill';
/// The types last asked for, as [askedTypes] gave them.
const healthTypes = 'health.types';
// Each round reads again a little before the last, so a reading the store saved late is not missed; the server keeps
// each once.
const _overlap = Duration(hours: 2);
/// How far back the history read goes, a week each round, newest first.
const healthHistory = Duration(days: 90);
const _week = Duration(days: 7);

/// Starts health from [now]: the next rounds read new readings, and the last 90 days a week at a time.
Future<void> startHealth(Store store, DateTime now) async {
  await store.set(healthSince, '${now.millisecondsSinceEpoch}');
  await store.set(healthBackfill, '${now.millisecondsSinceEpoch}');
  await store.set(healthTypes, askedTypes);
}

/// Reads every reading since the last round, then one more week of the 90-day history, and queues them, 500 to a
/// batch. New readings go first, so they never wait behind history. A phone from before the history read starts it at
/// its last read, so every type, new ones too, gets its 90 days once. It waits until the app asked for the new types, at
/// open: a history week read before that has none of them, and the mark would move past it. Returns how many it queued.
Future<int> syncHealth(Store store, HealthSource source, {DateTime? now}) async {
  final to = now ?? DateTime.now();
  final saved = await store.get(healthSince);
  final last = saved == null ? to : DateTime.fromMillisecondsSinceEpoch(int.parse(saved));
  final backfill = await store.get(healthBackfill);
  final waiting = backfill == null && await store.get(healthTypes) != askedTypes;
  if (backfill == null && !waiting) await store.set(healthBackfill, '${last.millisecondsSinceEpoch}');
  var queued = 0;
  if (saved != null) queued += await _queue(store, await source.read(last.subtract(_overlap), to));
  await store.set(healthSince, '${to.millisecondsSinceEpoch}');
  if (waiting) return queued;
  final mark = backfill == null ? last : DateTime.fromMillisecondsSinceEpoch(int.parse(backfill));
  final oldest = to.subtract(healthHistory);
  if (mark.isAfter(oldest)) {
    final from = mark.subtract(_week).isBefore(oldest) ? oldest : mark.subtract(_week);
    queued += await _queue(store, await source.read(from, mark));
    await store.set(healthBackfill, '${from.millisecondsSinceEpoch}');
  }
  return queued;
}

Future<int> _queue(Store store, List<HealthDataPoint> points) async {
  final seen = <String>{};
  final samples = [
    for (final point in points)
      if (sampleOf(point) case final sample? when seen.add('${sample['type']} ${sample['start']} ${sample['end']} ${sample['source']}')) sample,
  ];
  for (var at = 0; at < samples.length; at += 500) {
    await store.enqueue('health', {'samples': samples.sublist(at, (at + 500).clamp(0, samples.length))});
  }
  return samples.length;
}
