import 'dart:convert';
import 'dart:math';

import '../data/store.dart' show Pin;

// Stays and trips from location points and motion, worked out on the phone with no I/O. The rules follow Dawarich's
// ideas (github.com/Freika/dawarich, AGPL-3.0), never its code: openspec/changes/places-timeline/design.md.

/// A point joins a stay within this many meters of the stay's running center...
const radiusM = 100.0;
/// ...and within this many of its first point, so a slow walk can not drag the circle along.
const driftM = 150.0;
/// A cluster is a stay when it spans this long.
const minStay = Duration(minutes: 5);
/// A silence this long after a point means the phone was still there: *Save battery* sends only on a move.
const still = Duration(minutes: 30);
/// Two stays at one place less than this far apart are one.
const merge = Duration(minutes: 15);
/// A point less sure than this joins no stay; it still counts in a trip.
const poorFixM = 250.0;
/// Apple Maps names a stay only when the stay's median accuracy is within this.
const goodFixM = 50.0;
/// A trip longer than this with no point inside has no mode to tell.
const emptyTrip = Duration(minutes: 60);
/// Speed comes from steps between points this far apart in time or more.
const _speedStep = Duration(seconds: 30);
/// The most accuracies a stay keeps for its median.
const _accuracies = 50;

/// What the phone's motion sensors say the person was doing.
enum MotionKind { stationary, walking, running, cycling, driving }

/// One motion change: from [at], the person was [kind]. [sure] is *high* on iPhone, an *enter* on Android.
class MotionChange {
  const MotionChange(this.at, this.kind, {this.sure = true});

  final DateTime at;
  final MotionKind kind;
  final bool sure;

  bool get moving => kind != MotionKind.stationary;

  Map<String, dynamic> toJson() => {'at': at.millisecondsSinceEpoch, 'kind': kind.name, 'sure': sure};

  /// A change as the store or a phone writes it, or null for one that is not.
  static MotionChange? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'], kind = MotionKind.values.asNameMap()[json['kind']];
    if (at is! int || kind == null) return null;
    return MotionChange(DateTime.fromMillisecondsSinceEpoch(at), kind, sure: json['sure'] != false);
  }
}

/// How a trip went.
enum TripMode { walking, running, cycling, driving, flying, unknown }

/// Where a stay's name came from.
enum NameSource { calendar, map, street, point }

/// A stay's name, with its street when the name came from the calendar or the map.
class StayName {
  const StayName(this.name, this.source, {this.address, this.event});

  final String name;
  final NameSource source;
  final String? address;
  final String? event;

  Map<String, dynamic> toJson() => {'name': name, 'source': source.name, 'address': ?address, 'event': ?event};

  static StayName? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'], source = NameSource.values.asNameMap()[json['source']];
    if (name is! String || source == null) return null;
    return StayName(name, source, address: json['address'] as String?, event: json['event'] as String?);
  }
}

/// A place's coordinates as a name: `43.651, -79.383`.
String coordinatesOf(double lat, double lon) => '${lat.toStringAsFixed(3)}, ${lon.toStringAsFixed(3)}';

/// The great-circle distance between two points, in meters.
double distanceM(double lat1, double lon1, double lat2, double lon2) {
  double radians(double degrees) => degrees * pi / 180;
  final dLat = radians(lat2 - lat1), dLon = radians(lon2 - lon1);
  final h = pow(sin(dLat / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * pow(sin(dLon / 2), 2);
  return 2 * 6371000 * asin(min(1, sqrt(h)));
}

/// A stay or a trip, as the server's `stays` route takes it.
class Segment {
  const Segment.stay({required this.start, required this.end, required double this.lat, required double this.lon,
    required double this.accuracy, this.ongoing = false, this.name}) : isStay = true, mode = null, km = null;

  const Segment.trip({required this.start, required this.end, required TripMode this.mode, required double this.km})
    : isStay = false, ongoing = false, lat = null, lon = null, accuracy = null, name = null;

  final bool isStay;
  final DateTime start;
  final DateTime end;
  /// A stay still going on: it is sent again when it ends.
  final bool ongoing;
  final double? lat;
  final double? lon;
  /// The stay's median accuracy, in meters.
  final double? accuracy;
  /// Null until a lookup names it; it goes as its coordinates until then.
  final StayName? name;
  final TripMode? mode;
  final double? km;

  Segment named(StayName name) =>
    Segment.stay(start: start, end: end, lat: lat!, lon: lon!, accuracy: accuracy!, ongoing: ongoing, name: name);

  Map<String, dynamic> toJson() {
    final times = {'start': start.millisecondsSinceEpoch, 'end': end.millisecondsSinceEpoch};
    if (!isStay) return {'kind': 'trip', ...times, 'mode': mode!.name, 'km': km};
    final label = name ?? StayName(coordinatesOf(lat!, lon!), NameSource.point);
    return {'kind': 'stay', ...times, if (ongoing) 'ongoing': true, 'lat': lat, 'lon': lon, ...label.toJson()};
  }
}

/// The points that make a stay: its first point, a running center, and when it began and last had a point.
class _Cluster {
  _Cluster(Pin first) : firstLat = first.lat, firstLon = first.lon, start = first.at, lastAt = first.at {
    add(first);
  }

  _Cluster._(this.firstLat, this.firstLon, this.sumLat, this.sumLon, this.n, this.start, this.lastAt, this.accuracies);

  final double firstLat, firstLon;
  double sumLat = 0, sumLon = 0;
  int n = 0;
  DateTime start, lastAt;
  List<double> accuracies = [];

  double get lat => sumLat / n;
  double get lon => sumLon / n;

  bool takes(Pin point) => distanceM(lat, lon, point.lat, point.lon) <= radiusM &&
    distanceM(firstLat, firstLon, point.lat, point.lon) <= driftM;

  void add(Pin point) {
    sumLat += point.lat;
    sumLon += point.lon;
    n++;
    if (point.at.isAfter(lastAt)) lastAt = point.at;
    accuracies = [...accuracies, point.accuracy];
    if (accuracies.length > _accuracies) accuracies = accuracies.sublist(accuracies.length - _accuracies);
  }

  /// Takes in another cluster's points, for two stays that merge.
  void absorb(_Cluster other) {
    sumLat += other.sumLat;
    sumLon += other.sumLon;
    n += other.n;
    if (other.lastAt.isAfter(lastAt)) lastAt = other.lastAt;
    accuracies = [...accuracies, ...other.accuracies];
    if (accuracies.length > _accuracies) accuracies = accuracies.sublist(accuracies.length - _accuracies);
  }

  double get accuracy {
    final sorted = [...accuracies]..sort();
    return sorted.isEmpty ? 0 : sorted[sorted.length ~/ 2];
  }

  bool near(_Cluster other) => distanceM(lat, lon, other.lat, other.lon) <= radiusM;

  Map<String, dynamic> toJson() => {'firstLat': firstLat, 'firstLon': firstLon, 'sumLat': sumLat, 'sumLon': sumLon, 'n': n,
    'start': start.millisecondsSinceEpoch, 'lastAt': lastAt.millisecondsSinceEpoch, 'accuracies': accuracies};

  static _Cluster fromJson(Map json) => _Cluster._((json['firstLat'] as num).toDouble(), (json['firstLon'] as num).toDouble(),
    (json['sumLat'] as num).toDouble(), (json['sumLon'] as num).toDouble(), json['n'] as int,
    DateTime.fromMillisecondsSinceEpoch(json['start'] as int), DateTime.fromMillisecondsSinceEpoch(json['lastAt'] as int),
    [for (final value in json['accuracies'] as List) (value as num).toDouble()]);

  _Cluster copy() => fromJson(toJson());
}

/// The last stay that ended: the trip after it starts at [end], and a stay near it soon after merges into it.
class _Closed {
  _Closed(this.cluster, this.end, this.name);

  final _Cluster cluster;
  final DateTime end;
  StayName? name;

  Map<String, dynamic> toJson() => {'cluster': cluster.toJson(), 'end': end.millisecondsSinceEpoch, 'name': name?.toJson()};

  static _Closed fromJson(Map json) => _Closed(_Cluster.fromJson(json['cluster'] as Map),
    DateTime.fromMillisecondsSinceEpoch(json['end'] as int), StayName.fromJson(json['name']));
}

/// The open stay or trip, kept in the store's `timeline` state key between rounds. The points it still needs stay in
/// the store's `track` table, from [keepFrom] on.
class TimelineState {
  TimelineState._({this._last, this._stay, this.stayName, this.staySent = false, this.stayEnd, this.tripFrom,
    this.candidateFrom, this.cursor});

  /// No stay or trip yet, as after an update or after sending turned off.
  factory TimelineState.empty() => TimelineState._();

  _Closed? _last;
  _Cluster? _stay;
  StayName? stayName;
  /// The open stay went out as ongoing.
  bool staySent;
  /// The open stay's end as last sent, or before it went, when it became a stay.
  DateTime? stayEnd;
  /// The open trip's start: the last stay's end.
  DateTime? tripFrom;
  /// The first point of the cluster that may become the next stay.
  DateTime? candidateFrom;
  /// The newest point already stepped.
  DateTime? cursor;

  /// The time from which the open stay or trip needs its points and motion; older rows can go.
  DateTime? get keepFrom {
    final open = _stay;
    if (open != null) return open.lastAt.add(const Duration(milliseconds: 1));
    return tripFrom ?? candidateFrom ?? cursor?.add(const Duration(milliseconds: 1));
  }

  /// The open stay, ended at its last point or the later end already sent, for when the timeline stops while sending
  /// goes on, so the server does not keep it as ongoing; null with no open stay.
  Segment? closeOpen() {
    final open = _stay, sent = stayEnd;
    return open == null ? null : Segment.stay(start: open.start, end: sent != null && sent.isAfter(open.lastAt) ? sent : open.lastAt,
      lat: open.lat, lon: open.lon, accuracy: open.accuracy, name: stayName);
  }

  /// Gives the stay that started at [start], open or last ended, its name.
  void name(DateTime start, StayName name) {
    if (_stay?.start == start) stayName = name;
    if (_last?.cluster.start == start) _last!.name = name;
  }

  String encode() => jsonEncode({'last': _last?.toJson(), 'stay': _stay?.toJson(), 'stayName': stayName?.toJson(),
    'staySent': staySent, 'stayEnd': stayEnd?.millisecondsSinceEpoch, 'tripFrom': tripFrom?.millisecondsSinceEpoch,
    'candidateFrom': candidateFrom?.millisecondsSinceEpoch, 'cursor': cursor?.millisecondsSinceEpoch});

  /// The saved state, or an empty one for none or one that does not read.
  factory TimelineState.decode(String? saved) {
    if (saved == null) return TimelineState.empty();
    try {
      final json = jsonDecode(saved) as Map;
      DateTime? time(String key) => json[key] == null ? null : DateTime.fromMillisecondsSinceEpoch(json[key] as int);
      return TimelineState._(last: json['last'] == null ? null : _Closed.fromJson(json['last'] as Map),
        stay: json['stay'] == null ? null : _Cluster.fromJson(json['stay'] as Map), stayName: StayName.fromJson(json['stayName']),
        staySent: json['staySent'] == true, stayEnd: time('stayEnd'), tripFrom: time('tripFrom'),
        candidateFrom: time('candidateFrom'), cursor: time('cursor'));
    } on Object {
      return TimelineState.empty();
    }
  }
}

/// What one step made: stays and trips that ended, the open stay when it needs sending, and the state after.
class StepResult {
  const StepResult(this.closed, this.open, this.state);

  /// In time order. A stay here can be one sent as ongoing before, now with its end.
  final List<Segment> closed;
  /// The open stay, ongoing, when it is new or changed since it was last sent.
  final Segment? open;
  final TimelineState state;

  /// Everything to send, in time order.
  List<Segment> get segments => [...closed, ?open];
}

/// Steps the open stay or trip on through [track], the points kept from [TimelineState.keepFrom] on, in any order, and
/// [motions], the motion changes kept, at [now]. [late] holds the times of points that came after a round had stepped
/// past them. The [state] given is not changed.
StepResult step(TimelineState state, List<Pin> track, List<MotionChange> motions, DateTime now, {Set<DateTime> late = const {}}) {
  final machine = _Machine(TimelineState.decode(state.encode()), [...motions]..sort((a, b) => a.at.compareTo(b.at)), late);
  final points = [...track]..sort((a, b) => a.at.compareTo(b.at));
  final cursor = state.cursor;
  machine.restore([for (final point in points) if (cursor != null && !point.at.isAfter(cursor)) point]);
  for (final point in points) {
    if (cursor == null || point.at.isAfter(cursor)) machine.add(point);
  }
  machine.finish(now);
  return machine.result(now);
}

/// The mode for a speed in km/h, with no motion to tell.
TripMode modeOfSpeed(double kmh) => kmh < 8 ? TripMode.walking : kmh < 25 ? TripMode.cycling
  : kmh <= 250 ? TripMode.driving : TripMode.flying;

class _Machine {
  _Machine(this.state, this.motions, this.late);

  final TimelineState state;
  final List<MotionChange> motions;
  /// The times of points that came late: only these can change a stay already stepped.
  final Set<DateTime> late;
  final closed = <Segment>[];
  /// Points of the open trip before the candidate, and of the candidate; poor fixes during an open stay.
  var trip = <Pin>[], candidatePoints = <Pin>[], pending = <Pin>[];
  _Cluster? candidate;
  bool reopened = false;
  /// A point joined the open stay this round.
  bool fresh = false;
  /// Late points the last stay took in, which the trip after it leaves out.
  final absorbed = <Pin>{};

  /// Rebuilds the lists from the points already stepped. A late point at the open stay's place joins it.
  void restore(List<Pin> stepped) {
    final open = state._stay;
    if (open != null) {
      for (final point in stepped) {
        if (!point.at.isAfter(open.lastAt)) continue;
        if (late.contains(point.at) && point.accuracy <= poorFixM && open.takes(point)) {
          open.add(point);
          fresh = true;
        } else {
          pending.add(point);
        }
      }
      return;
    }
    _late(stepped);
    final from = state.candidateFrom;
    for (final point in stepped) {
      if (absorbed.contains(point)) continue;
      if (from != null && !point.at.isBefore(from)) {
        candidatePoints.add(point);
      } else if (state.tripFrom != null && !point.at.isBefore(state.tripFrom!)) {
        trip.add(point);
      }
    }
    for (final point in candidatePoints) {
      if (point.accuracy > poorFixM) continue;
      candidate == null ? candidate = _Cluster(point) : candidate!.add(point);
    }
  }

  /// A late point at the last stay's place, after its last point and before the point that ended it, as an iPhone
  /// visit's late departure: while the trip after it is open, the stay goes again, with its real end.
  void _late(List<Pin> stepped) {
    final last = state._last;
    if (last == null || state.tripFrom == null) return;
    final cluster = last.cluster;
    final after = [for (final point in stepped) if (point.at.isAfter(cluster.lastAt) && point.accuracy <= poorFixM) point];
    final closer = after.where((point) => !cluster.takes(point)).firstOrNull;
    final taken = [for (final point in after)
      if (late.contains(point.at) && cluster.takes(point) && (closer == null || point.at.isBefore(closer.at))) point];
    if (taken.isEmpty) return;
    taken.forEach(cluster.add);
    absorbed.addAll(taken);
    final end = closer != null ? _endOf(cluster.lastAt, closer.at) : _later(last.end, cluster.lastAt);
    state._last = _Closed(cluster, end, last.name);
    state.tripFrom = end;
    if (end == last.end) return;
    closed.add(Segment.stay(start: cluster.start, end: end, lat: cluster.lat, lon: cluster.lon, accuracy: cluster.accuracy,
      name: last.name));
  }

  void add(Pin point) {
    state.cursor = point.at;
    final open = state._stay;
    if (open != null) {
      if (point.accuracy > poorFixM) return pending.add(point);
      if (open.takes(point)) {
        open.add(point);
        fresh = true;
        pending = [];
        return;
      }
      closeStay(_endOf(open.lastAt, point.at));
    }
    addLoose(point);
  }

  /// A point with no open stay: it joins the candidate, or starts a new one.
  void addLoose(Pin point) {
    if (point.accuracy > poorFixM) {
      (candidate == null ? trip : candidatePoints).add(point);
      return;
    }
    final cluster = candidate;
    if (cluster != null && cluster.takes(point)) {
      cluster.add(point);
      candidatePoints.add(point);
      if (cluster.lastAt.difference(cluster.start) >= minStay) confirm(cluster.lastAt);
      return;
    }
    final stopped = cluster == null ? null : _stillSpan(cluster.start, point.at);
    if (cluster != null && (stopped != null || point.at.difference(cluster.lastAt) >= still)) {
      // The phone was still at the candidate until this point, or its motion was: a stay, even of one point.
      confirm(cluster.lastAt);
      closeStay(stopped != null ? _later(stopped.end, cluster.lastAt) : _endOf(cluster.lastAt, point.at));
      return addLoose(point);
    }
    trip.addAll(candidatePoints);
    startCandidate(point);
  }

  void startCandidate(Pin point) {
    candidate = _Cluster(point);
    candidatePoints = [point];
    state.candidateFrom = point.at;
  }

  /// The candidate is a stay: it merges into the last stay when it is near and soon after, or the silence between had
  /// no point elsewhere; otherwise the trip before it ends.
  void confirm(DateTime end) {
    final cluster = candidate!;
    final last = state._last;
    bool silent(_Closed last) => !trip.any((point) => point.accuracy <= poorFixM && !last.cluster.takes(point));
    if (last != null && last.cluster.near(cluster) && (cluster.start.difference(last.end) < merge || silent(last))) {
      last.cluster.absorb(cluster);
      state._stay = last.cluster;
      state.stayName = last.name;
      state._last = null;
      closed.removeWhere((segment) => segment.isStay && segment.start == last.cluster.start);
      reopened = true;
    } else {
      if (last != null) closed.add(_trip(last, state.tripFrom!, cluster.start, trip));
      state._stay = cluster;
      state.stayName = null;
      reopened = false;
    }
    state.staySent = false;
    state.stayEnd = end;
    fresh = true;
    state.tripFrom = null;
    state.candidateFrom = null;
    candidate = null;
    candidatePoints = [];
    trip = [];
    pending = [];
  }

  /// The open stay ends at [end]; the trip after it starts there.
  void closeStay(DateTime end) {
    final open = state._stay!;
    closed.add(Segment.stay(start: open.start, end: end, lat: open.lat, lon: open.lon, accuracy: open.accuracy,
      name: state.stayName));
    state._last = _Closed(open, end, state.stayName);
    state._stay = null;
    state.stayName = null;
    state.staySent = false;
    state.stayEnd = null;
    state.tripFrom = end;
    trip = [for (final point in pending) if (!point.at.isBefore(end)) point];
    pending = [];
    candidate = null;
    candidatePoints = [];
    state.candidateFrom = null;
    reopened = false;
    fresh = false;
  }

  /// When a stay whose last point was at [lastIn] ended, given the next point outside it at [nextAt]: the start of the
  /// last sure move between them, else the next point after a silence, else its last point.
  DateTime _endOf(DateTime lastIn, DateTime nextAt) {
    final move = _lastMoveStart(lastIn, nextAt);
    if (move != null) return move;
    return nextAt.difference(lastIn) >= still ? nextAt : lastIn;
  }

  /// The first sure move after [from], before [to], with no sure stillness after it before [to].
  DateTime? _lastMoveStart(DateTime from, DateTime to) {
    DateTime? start;
    for (final change in motions) {
      if (!change.at.isAfter(from) || !change.at.isBefore(to) || !change.sure) continue;
      if (!change.moving) {
        start = null;
      } else {
        start ??= change.at;
      }
    }
    return start;
  }

  /// The last time from [from] to [to] that motion says the phone was still for [minStay] or more.
  ({DateTime start, DateTime end})? _stillSpan(DateTime from, DateTime to) {
    ({DateTime start, DateTime end})? last;
    DateTime? since;
    void stop(DateTime at) {
      final begin = since == null ? null : _later(since!, from), end = at.isAfter(to) ? to : at;
      since = null;
      if (begin != null && end.difference(begin) >= minStay) last = (start: begin, end: end);
    }
    // Stillness starts only when motion is sure of it; any move, sure or not, ends it.
    for (final change in motions) {
      if (!change.at.isBefore(to)) continue;
      if (change.moving) {
        stop(change.at);
      } else if (change.sure) {
        since ??= change.at;
      }
    }
    stop(to);
    return last;
  }

  static DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  /// At the end of the round: a candidate after a long silence, or after [minStay] of sure stillness, is a stay, and a
  /// sure move that is still going on after [minStay] ends the open stay.
  void finish(DateTime now) {
    final cluster = candidate;
    if (state._stay == null && cluster != null) {
      final stopped = _stillSpan(cluster.start, now);
      if (now.difference(cluster.lastAt) >= still) {
        confirm(now);
      } else if (stopped != null) {
        confirm(_later(stopped.end, cluster.lastAt));
      }
    }
    final open = state._stay;
    if (open != null) {
      final move = _lastMoveStart(open.lastAt, now);
      if (move != null && now.difference(move) >= minStay) closeStay(move);
    }
  }

  /// The open stay goes when it is new, merged, or its end moved on since it last went.
  StepResult result(DateTime now) {
    final open = state._stay;
    Segment? ongoing;
    final end = open == null ? null : _openEnd(open, now);
    if (open != null && end != null && (!state.staySent || reopened || state.stayEnd == null || end.isAfter(state.stayEnd!))) {
      ongoing = Segment.stay(start: open.start, end: end, lat: open.lat, lon: open.lon, accuracy: open.accuracy,
        ongoing: true, name: state.stayName);
      state.staySent = true;
      state.stayEnd = end;
    }
    return StepResult(closed, ongoing, state);
  }

  /// The open stay's end: its newest point, or the round's time while the phone was still with no new point.
  DateTime _openEnd(_Cluster open, DateTime now) {
    final newest = state.stayEnd == null ? open.lastAt : _later(state.stayEnd!, open.lastAt);
    return fresh || _lastMoveStart(open.lastAt, now) != null ? newest : _later(now, newest);
  }

  /// The trip from [last] at [start] through [points] to [next]'s first point at [end].
  Segment _trip(_Closed last, DateTime start, DateTime end, List<Pin> points) {
    final next = candidate!;
    final path = [Pin(at: start, lat: last.cluster.lat, lon: last.cluster.lon, accuracy: 0), ...points,
      Pin(at: end, lat: next.lat, lon: next.lon, accuracy: 0)];
    var meters = 0.0;
    final speeds = <double>[];
    for (var i = 1; i < path.length; i++) {
      final step = distanceM(path[i - 1].lat, path[i - 1].lon, path[i].lat, path[i].lon);
      meters += step;
      final time = path[i].at.difference(path[i - 1].at);
      if (time >= _speedStep) speeds.add(step / 1000 / (time.inMilliseconds / 3600000));
    }
    final km = (meters / 100).round() / 10;
    final hours = end.difference(start).inMilliseconds / 3600000;
    speeds.sort();
    final speed = speeds.isNotEmpty ? speeds[speeds.length ~/ 2] : hours > 0 ? meters / 1000 / hours : 0.0;
    return Segment.trip(start: start, end: end, km: km, mode: _modeOf(start, end, speed, points.isEmpty));
  }

  TripMode _modeOf(DateTime start, DateTime end, double speed, bool empty) {
    // No time between the stays, as when the phone was off for a flight: nothing to tell the mode from.
    if (!end.isAfter(start)) return TripMode.unknown;
    if (speed > 250) return TripMode.flying;
    if (empty && end.difference(start) > emptyTrip) return TripMode.unknown;
    return _motionMode(start, end) ?? modeOfSpeed(speed);
  }

  /// The moving kind that covers most of the trip, when moving covers at least half of it.
  TripMode? _motionMode(DateTime start, DateTime end) {
    final covered = <MotionKind, int>{};
    for (var i = 0; i < motions.length; i++) {
      final from = motions[i].at.isBefore(start) ? start : motions[i].at;
      final to = i + 1 < motions.length && motions[i + 1].at.isBefore(end) ? motions[i + 1].at : end;
      if (!to.isAfter(from) || !motions[i].moving) continue;
      covered[motions[i].kind] = (covered[motions[i].kind] ?? 0) + to.difference(from).inMilliseconds;
    }
    if (covered.isEmpty) return null;
    final top = covered.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final total = covered.values.fold(0, (sum, value) => sum + value);
    if (total * 2 < end.difference(start).inMilliseconds) return null;
    return TripMode.values.byName(top.key.name);
  }
}
