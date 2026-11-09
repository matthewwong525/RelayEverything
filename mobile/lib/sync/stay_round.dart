import '../data/settings.dart';
import '../data/store.dart';
import 'calendar.dart';
import 'location.dart';
import 'motion.dart';
import 'native.dart';
import 'stays.dart';

/// The most stays a round names: Apple throttles lookups, and an iPhone wake has about 25 seconds. The rest go as their
/// coordinates and get a name when they end.
const namesPerRound = 3;
/// A calendar event names a stay only when its place is this near.
const eventNearM = 150.0;
/// How far back an iPhone reads motion: Core Motion keeps 7 days.
const _motionDays = Duration(days: 7);

/// The lookups that name a stay, in order: the calendar, Apple Maps, the street, the coordinates. Each is a network
/// call, so the round makes one only while sending is on. A lookup that fails goes to the next.
class StayNamer {
  StayNamer({this.events, this.placeOf, this.venue, this.street});

  /// The events that overlap a time, while *Calendar* is on.
  final Future<List<PhoneEvent>> Function(DateTime from, DateTime to)? events;
  /// Where an event's place is, from its words.
  final Future<({double lat, double lon})?> Function(String address)? placeOf;
  /// The nearest place of interest within 50 m: Apple Maps, on iPhone only.
  final Future<String?> Function(double lat, double lon)? venue;
  /// The street, as a point's place name.
  final Future<String?> Function(double lat, double lon)? street;
  /// Each event place looked up this round, by its words.
  final _places = <String, ({double lat, double lon})?>{};

  /// The best name for [stay].
  Future<StayName> name(Segment stay) async {
    final lat = stay.lat!, lon = stay.lon!;
    final fromCalendar = await _calendar(stay);
    if (fromCalendar != null) return StayName(fromCalendar.$1, NameSource.calendar, event: fromCalendar.$2, address: await _try(street, lat, lon));
    if (stay.accuracy! <= goodFixM) {
      final place = await _try(venue, lat, lon);
      if (place != null) return StayName(place, NameSource.map, address: await _try(street, lat, lon));
    }
    final road = await _try(street, lat, lon);
    if (road != null) return StayName(road, NameSource.street);
    return StayName(coordinatesOf(lat, lon), NameSource.point);
  }

  static Future<String?> _try(Future<String?> Function(double, double)? lookup, double lat, double lon) async {
    if (lookup == null) return null;
    try {
      final found = (await lookup(lat, lon))?.trim();
      return found == null || found.isEmpty ? null : _cut(found, 200);
    } on Exception {
      return null;
    }
  }

  /// The name and title of an event that overlaps [stay] at a place within 150 m, or null. A link, such as an online
  /// meeting's, is no place, so an online meeting at home never renames home.
  Future<(String, String)?> _calendar(Segment stay) async {
    final read = events, find = placeOf;
    if (read == null || find == null) return null;
    final end = stay.end.isAfter(stay.start) ? stay.end : stay.start.add(const Duration(milliseconds: 1));
    List<PhoneEvent> found;
    try {
      found = await read(stay.start, end);
    } on Exception {
      return null;
    }
    for (final event in found) {
      final location = event.location?.trim() ?? '';
      if (event.allDay || event.cancelled || location.isEmpty || _isLink(location)) continue;
      if (!event.start.isBefore(end) || !event.end.isAfter(stay.start)) continue;
      final place = await _placeOf(find, location);
      if (place == null || distanceM(place.lat, place.lon, stay.lat!, stay.lon!) > eventNearM) continue;
      final first = location.split(',').first.trim();
      final title = _cut(event.title.trim(), 500);
      final name = first.isEmpty || RegExp(r'^\d').hasMatch(first) ? title : first;
      if (name.isEmpty) continue;
      return (_cut(name, 200), title);
    }
    return null;
  }

  Future<({double lat, double lon})?> _placeOf(Future<({double lat, double lon})?> Function(String) find, String location) async {
    if (_places.containsKey(location)) return _places[location];
    try {
      return _places[location] = await find(location);
    } on Exception {
      return _places[location] = null;
    }
  }

  static bool _isLink(String location) => RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(location) ||
    RegExp(r'\b(zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com)\b', caseSensitive: false).hasMatch(location);

  static String _cut(String text, int most) => text.length <= most ? text : text.substring(0, most);
}

/// The lookups that name a stay: the calendar while it is on, Apple Maps on iPhone, and the street. Used only while
/// sending is on.
StayNamer stayNamer(Settings settings, {Places? places, NativeBackground? native, CalendarSource? calendar}) => StayNamer(
  events: eventsAt(calendar, settings), placeOf: places?.locate, venue: native?.venue, street: places?.nameOf);

/// The round's timeline step, after the points are in the store: reads motion, names at most [namesPerRound] stays, and
/// queues each stay and trip that ended or opened with the state, in one step. Returns how many it queued.
Future<int> syncStays(Store store, Settings settings, {Motion? motion, StayNamer? namer, DateTime? now}) async {
  if (!settings.sending || !settings.stays) return 0;
  final at = now ?? DateTime.now();
  final state = await store.timeline();
  if (motion != null) {
    final oldest = at.subtract(_motionDays);
    final from = state.keepFrom ?? at.subtract(const Duration(days: 1));
    try {
      await store.addMotions(await motion.read(from.isBefore(oldest) ? oldest : from, at));
    } on Exception {
      // No motion, or refused: the mode comes from speed.
    }
  }
  final result = step(state, await store.track(), await store.motions(), at, late: await store.lateTrack());
  final segments = <Segment>[];
  var asked = 0;
  for (final segment in result.segments) {
    if (!segment.isStay || segment.name != null || namer == null || asked == namesPerRound) {
      segments.add(segment);
      continue;
    }
    asked++;
    final name = await namer.name(segment);
    result.state.name(segment.start, name);
    segments.add(segment.named(name));
  }
  await store.queueStays(segments, result.state);
  return segments.length;
}
