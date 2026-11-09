import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'stays.dart';

/// The phone's motion sensors, for a trip's mode: iPhone's Core Motion and Android's Activity Recognition. The app reads
/// only what kind of moving the person did, never steps: those stay with Health.
abstract class Motion {
  /// Asks for *Motion & Fitness* or *Physical activity*. True when the app may read it; a no leaves the mode to speed.
  Future<bool> allow();

  /// Starts or stops the phone keeping motion changes while the app is closed. Only Android needs it.
  Future<void> watch(bool on);

  /// The changes from [from] to [to], oldest first. An Android read also empties the file it reads.
  Future<List<MotionChange>> read(DateTime from, DateTime to);
}

/// Drops a change that only repeats the kind before it.
List<MotionChange> collapse(Iterable<MotionChange> changes) {
  final kept = <MotionChange>[];
  for (final change in [...changes]..sort((a, b) => a.at.compareTo(b.at))) {
    if (kept.isNotEmpty && kept.last.kind == change.kind && kept.last.sure == change.sure) continue;
    kept.add(change);
  }
  return kept;
}

/// iPhone: `CMMotionActivityManager` on the `relay/background` channel (ios/Runner/RelayBackground.swift). It reads the
/// phone's last 7 days, so a wake reads what happened while the app was closed.
class PhoneMotion implements Motion {
  static const _channel = MethodChannel('relay/background');

  @override
  Future<bool> allow() async => await _channel.invokeMethod<bool>('motionAllow') ?? false;

  @override
  Future<void> watch(bool on) async {}

  @override
  Future<List<MotionChange>> read(DateTime from, DateTime to) async {
    final rows = await _channel.invokeListMethod<Object?>('motion',
      {'from': from.millisecondsSinceEpoch, 'to': to.millisecondsSinceEpoch}) ?? const [];
    return collapse([for (final row in rows) ?MotionChange.fromJson(row)]);
  }
}

/// Android: an `ActivityReceiver` (android/.../ActivityReceiver.kt) gets the Transition API's changes, also with the
/// app closed, and adds each to `relay-motion.jsonl` in the app's support folder. Only an *enter* is a change.
class AndroidMotion implements Motion {
  AndroidMotion({Future<Directory> Function()? folder}) : _folder = folder ?? getApplicationSupportDirectory;

  static const _channel = MethodChannel('relay/motion');
  final Future<Directory> Function() _folder;

  @override
  Future<bool> allow() async => await _channel.invokeMethod<bool>('allow') ?? false;

  @override
  Future<void> watch(bool on) => _channel.invokeMethod('watch', {'on': on});

  @override
  Future<List<MotionChange>> read(DateTime from, DateTime to) async {
    final file = File('${(await _folder()).path}/relay-motion.jsonl');
    if (!await file.exists()) return const [];
    // A rename first, so a change the receiver adds while this reads goes to a new file.
    final taken = await file.rename('${file.path}.reading');
    final lines = await taken.readAsLines();
    await taken.delete();
    return collapse([
      for (final line in lines) ?_changeOf(line),
    ].where((change) => !change.at.isBefore(from) && !change.at.isAfter(to)));
  }

  static MotionChange? _changeOf(String line) {
    try {
      final json = jsonDecode(line);
      if (json is! Map || json['enter'] != true) return null;
      return MotionChange.fromJson(json);
    } on FormatException {
      return null;
    }
  }
}
