import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:health/health.dart';

import '../data/store.dart';
import 'nights.dart';

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

/// The sleep types read only to make nights, never sent as samples, by their stage. iPhone's asleep stages also go as
/// `sleep`; Android sends each session as `sleep` and reads its stages here.
final Map<HealthDataType, String> nightStages = {
  for (final type in Platform.isAndroid
      ? [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_LIGHT, HealthDataType.SLEEP_DEEP, HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_AWAKE, HealthDataType.SLEEP_AWAKE_IN_BED, HealthDataType.SLEEP_OUT_OF_BED]
      : [HealthDataType.SLEEP_IN_BED, HealthDataType.SLEEP_AWAKE])
    type: stageOf[type]!,
};

/// On Android, the types the health package reads inside each workout for its distance and calories: asked, never
/// read alone.
final Map<HealthDataType, String> _workoutDetail = Platform.isAndroid
  ? {HealthDataType.DISTANCE_DELTA: 'distance', HealthDataType.TOTAL_CALORIES_BURNED: 'calories'} : {};

/// Sleep, its stages and workouts: a watch writes them late, so each round reads them back [lateRead].
final Set<HealthDataType> lateTypes = {
  for (final entry in kinds.entries) if (entry.value == 'sleep' || entry.value == 'workout') entry.key,
  ...nightStages.keys,
};

/// Every other type, read from the last round on.
final List<HealthDataType> soonTypes = [for (final type in kinds.keys) if (!lateTypes.contains(type)) type];

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
/// percent, 0 to 100: iPhone gives a fraction. Water goes in ml: the health package gives litres. A workout also
/// carries its kind, and its distance and calories when the phone has them.
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
  return {
    'type': kind, 'start': point.dateFrom.millisecondsSinceEpoch, 'end': point.dateTo.millisecondsSinceEpoch,
    'value': amount, 'unit': _units[kind], 'source': _sourceOf(point),
    if (kind == 'workout' && value is WorkoutHealthValue) ...{
      'kind': value.workoutActivityType.name.toLowerCase(),
      'distance': ?_within(value.totalDistance),
      'calories': ?_within(value.totalEnergyBurned),
    },
  };
}

String _sourceOf(HealthDataPoint point) {
  final source = point.sourceId.isNotEmpty ? point.sourceId : point.sourceName;
  return source.isEmpty ? 'unknown' : source.substring(0, source.length.clamp(0, 200));
}

/// A workout's distance in m or calories in kcal, as both packages give them, or null when unknown or out of range.
double? _within(num? amount) => amount == null || amount < 0 || amount > 1e6 ? null : amount.toDouble();

double _scaled(String kind, double value) => switch (kind) {
  'blood_oxygen' when value <= 1 => value * 100,
  'water' => value * 1000,
  _ => value,
};

/// The types this app asks for, by the server's names and the night stages: the store keeps the list it last asked for
/// under [healthTypes], so a phone that allowed health before new types came is asked once more.
String get askedTypes => ({...kinds.values, ...nightStages.values, ..._workoutDetail.values}.toList()..sort()).join(',');

/// Where readings come from: the phone's health store, or a test's list.
abstract class HealthSource {
  Future<bool> allow();
  /// The readings of [types] from [from] to [to].
  Future<List<HealthDataPoint>> read(DateTime from, DateTime to, Iterable<HealthDataType> types);
}

class PhoneHealth implements HealthSource {
  final _health = Health();

  @override
  Future<bool> allow() async {
    await _health.configure();
    final types = [...kinds.keys, ...nightStages.keys, ..._workoutDetail.keys];
    final allowed = await _health.requestAuthorization(types, permissions: [for (final _ in types) HealthDataAccess.READ]);
    // The hourly sync reads with no screen open, which Health Connect allows only with this second permission.
    if (allowed && Platform.isAndroid && await _health.isHealthDataInBackgroundAvailable()) {
      await _health.requestHealthDataInBackgroundAuthorization();
    }
    return allowed;
  }

  @override
  Future<List<HealthDataPoint>> read(DateTime from, DateTime to, Iterable<HealthDataType> types) async {
    await _health.configure();
    return _health.getHealthDataFromTypes(types: types.toList(), startTime: from, endTime: to);
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
/// How far back each round reads sleep and workouts: a watch writes the whole night when the person wakes.
const lateRead = Duration(hours: 36);
// The sent list keeps a row by its start for longer than [lateRead], so a row read again is known.
const _keep = Duration(hours: 48);
// A redo week also reads past its newer end, so a night across two weeks is read whole by the older week.
const _tail = Duration(days: 1);
/// How far back the history read goes, a week each round, newest first.
const healthHistory = Duration(days: 90);
const _week = Duration(days: 7);

/// Starts health from [now]: the next rounds read new readings, and the last 90 days a week at a time.
Future<void> startHealth(Store store, DateTime now) async {
  await store.set(healthSince, '${now.millisecondsSinceEpoch}');
  await store.set(healthBackfill, '${now.millisecondsSinceEpoch}');
  await store.set(healthDetail, '${now.millisecondsSinceEpoch}');
  await store.remove(healthSent);
  await store.set(healthTypes, askedTypes);
}

/// Forgets the sent list and the redo, for when health turns off.
Future<void> stopHealth(Store store) async {
  await store.remove(healthSent);
  await store.remove(healthDetail);
}

/// Reads every reading since the last round, sleep and workouts from 36 hours back, then one more week of the 90-day
/// history and one week of the sleep and workout redo, and queues them, 500 to a batch. New readings go first, so they
/// never wait behind history. A phone from before the history read, or the redo, starts it at its last read, or now.
/// It waits until the app asked for the new types, at open: a week read before that has none of them, and the mark
/// would move past it. Returns how many it queued.
Future<int> syncHealth(Store store, HealthSource source, {DateTime? now}) async {
  final to = now ?? DateTime.now();
  final saved = await store.get(healthSince);
  final last = saved == null ? to : _time(saved);
  final asked = await store.get(healthTypes) == askedTypes;
  final sent = _sentList(await store.get(healthSent), to);
  var queued = 0;
  if (saved != null) {
    queued += await _queue(store, await source.read(last.subtract(_overlap), to, soonTypes));
    final from = last.subtract(lateRead);
    queued += await _queueLate(store, await source.read(from, to, lateTypes), sent, from: from);
  }
  await store.set(healthSince, '${to.millisecondsSinceEpoch}');
  final backfill = await store.get(healthBackfill), detail = await store.get(healthDetail);
  final history = backfill == null ? (asked ? last : null) : _time(backfill);
  if (history != null) queued += await _history(store, source, history, to);
  final redo = detail == null ? (asked ? to : null) : _time(detail);
  if (redo != null) queued += await _redo(store, source, redo, to, sent);
  return queued;
}

DateTime _time(String saved) => DateTime.fromMillisecondsSinceEpoch(int.parse(saved));

/// The start of the week before [mark], or null once [mark] reached 90 days before [to].
DateTime? _weekBefore(DateTime mark, DateTime to) {
  final oldest = to.subtract(healthHistory);
  if (!mark.isAfter(oldest)) return null;
  final from = mark.subtract(_week);
  return from.isBefore(oldest) ? oldest : from;
}

/// One week of the history before [mark], of every type but sleep and workouts, which the redo reads.
Future<int> _history(Store store, HealthSource source, DateTime mark, DateTime to) async {
  final from = _weekBefore(mark, to);
  if (from == null) return 0;
  final queued = await _queue(store, await source.read(from, mark, soonTypes));
  await store.set(healthBackfill, '${from.millisecondsSinceEpoch}');
  return queued;
}

/// One week of sleep and workouts before [mark], with [edge] more before it, for its nights and full workouts. Each
/// week keeps the nights and samples that start in it.
Future<int> _redo(Store store, HealthSource source, DateTime mark, DateTime to, Map<String, String> sent) async {
  final from = _weekBefore(mark, to);
  if (from == null) return 0;
  final read = from.subtract(edge);
  final queued = await _queueLate(store, await source.read(read, mark.add(_tail), lateTypes), sent,
    from: read, keep: from, until: mark);
  await store.set(healthDetail, '${from.millisecondsSinceEpoch}');
  return queued;
}

Future<int> _queue(Store store, List<HealthDataPoint> points) async {
  final seen = <String>{};
  final samples = [
    for (final point in points)
      if (sampleOf(point) case final sample? when seen.add('${sample['type']} ${sample['start']} ${sample['end']} ${sample['source']}')) sample,
  ];
  await store.queueSamples(samples);
  return samples.length;
}

/// Queues the sleep and workout samples in [points] that start from [keep], or [from], and before [until], and the
/// nights a read from [from] makes, each only when it is not in [sent] unchanged; saves [sent] in the same step.
Future<int> _queueLate(Store store, List<HealthDataPoint> points, Map<String, String> sent,
    {required DateTime from, DateTime? keep, DateTime? until}) async {
  final first = (keep ?? from).millisecondsSinceEpoch, last = until?.millisecondsSinceEpoch;
  final samples = [
    for (final point in points)
      if (sampleOf(point) case final sample? when sample['start'] >= first && (last == null || sample['start'] < last)
        && _changed(sent, '${sample['start']} ${sample['type']} ${sample['end']} ${sample['source']}', sample)) sample,
  ];
  final nights = [
    for (final night in nightsOf([for (final point in points) ?_readingOf(point)], from: from, until: until))
      if (night.toJson() case final body when _changed(sent, '${body['start']} night ${night.source}', body)) body,
  ];
  await store.transaction(() async {
    await store.queueSamples(samples);
    await store.queueNights(nights);
    await store.set(healthSent, jsonEncode(sent));
  });
  return samples.length + nights.length;
}

SleepReading? _readingOf(HealthDataPoint point) {
  final stage = stageOf[point.type];
  return stage == null ? null : SleepReading(_sourceOf(point), stage, point.dateFrom, point.dateTo);
}

/// The sent list, key to hash, less the rows that start more than 48 hours before [now]. Each key starts with its
/// row's start.
Map<String, String> _sentList(String? saved, DateTime now) {
  final oldest = now.subtract(_keep).millisecondsSinceEpoch;
  final kept = saved == null ? const <String, Object?>{} : jsonDecode(saved) as Map<String, Object?>;
  return {
    for (final MapEntry(:key, :value) in kept.entries)
      if ((int.tryParse(key.split(' ').first) ?? 0) >= oldest && value is String) key: value,
  };
}

/// False when [sent] has [row] under [key] unchanged; else marks it and gives true.
bool _changed(Map<String, String> sent, String key, Map<String, dynamic> row) {
  final hash = sha256.convert(utf8.encode(jsonEncode(row))).toString().substring(0, 16);
  if (sent[key] == hash) return false;
  sent[key] = hash;
  return true;
}
