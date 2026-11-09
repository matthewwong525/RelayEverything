import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/settings.dart';
import '../data/store.dart';

/// The iPhone's own background work, in Swift (ios/Runner/RelayBackground.swift): Apple Health wakes the app for new
/// readings, and a location manager keeps points in a file while the app is closed. Android has none of it.
abstract class NativeBackground {
  /// What Swift may do. Each is false while sending is off, so it reads and keeps nothing then.
  Future<void> set({required bool health, required bool history, required LocationMode mode});

  /// The points Swift kept since the last drain, one JSON object each, and empties its file.
  Future<List<String>> drain();

  /// The nearest place of interest within 50 m, such as a café, from Apple Maps; null when there is none. A network
  /// call, made once per stay and only while sending is on.
  Future<String?> venue(double lat, double lon);
}

class PhoneBackground implements NativeBackground {
  static const _channel = MethodChannel('relay/background');

  @override
  Future<void> set({required bool health, required bool history, required LocationMode mode}) =>
    _channel.invokeMethod('set', {'health': health, 'history': history, 'mode': mode.name});

  @override
  Future<List<String>> drain() async => await _channel.invokeListMethod<String>('drain') ?? const [];

  @override
  Future<String?> venue(double lat, double lon) => _channel.invokeMethod<String>('venue', {'lat': lat, 'lon': lon});

  /// With the app open, a wake runs [round] here, in place of a second engine.
  static void onWake(Future<void> Function() round) => _channel.setMethodCallHandler((call) async {
    if (call.method == 'wake') await round();
  });
}

/// A point as Swift writes it, or null for a line that is not one.
Pin? pointOf(String line) {
  try {
    final json = jsonDecode(line);
    if (json is! Map) return null;
    final at = json['at'], lat = json['lat'], lon = json['lon'], accuracy = json['accuracy'];
    if (at is! int || lat is! num || lon is! num || accuracy is! num) return null;
    return Pin(at: DateTime.fromMillisecondsSinceEpoch(at), lat: lat.toDouble(), lon: lon.toDouble(),
      accuracy: accuracy >= 0 ? accuracy.toDouble() : 0);
  } on FormatException {
    return null;
  }
}

// Apple limits how often an app may look up place names, so a round names only the newest few.
const _namedPerRound = 10;

/// Moves the points Swift kept into the store. Swift empties its file as it answers, so every point is stored before
/// any name lookup: a wake that iOS cuts short loses at most names, never points. Each goes where [send] says: waiting
/// to go as a point, into the open stay or trip, or both. Then, with [name], set only while sending is on, the newest
/// 10 points that go get a place name; the rest, and any whose lookup fails, stay unnamed. Returns how many it moved.
Future<int> drainPoints(Store store, NativeBackground native, {Future<String?> Function(double lat, double lon)? name,
  LocationSend send = LocationSend.all}) async {
  final points = [for (final line in await native.drain()) ?pointOf(line)]..sort((a, b) => b.at.compareTo(a.at));
  await store.transaction(() async {
    for (final point in points) {
      await store.addPoint(point, send: send);
    }
  });
  // With *Only stays and trips* no point goes, so none needs a name: the stay gets its own.
  if (name != null && send != LocationSend.stays) {
    for (final point in points.take(_namedPerRound)) {
      try {
        final place = await name(point.lat, point.lon);
        if (place != null) await store.namePoint(point.at, place);
      } on Exception {
        // A lookup that fails leaves this point unnamed; the others still get theirs.
      }
    }
  }
  return points.length;
}
