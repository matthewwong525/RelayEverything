import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/sync/calendar.dart';
import 'package:relay_app/sync/stay_round.dart';
import 'package:relay_app/sync/stays.dart';

import 'fakes.dart';

final start = DateTime.fromMillisecondsSinceEpoch(1793797200000);
DateTime at(num minutes) => start.add(Duration(seconds: (minutes * 60).round()));

// Places a double holds exactly, so a center of many points is the place itself.
const homeLat = 43.625, homeLon = -79.375;
/// About 14 km north of home.
const officeLat = 43.75, officeLon = -79.375;
/// Meters north as degrees of latitude.
double north(double meters) => meters / 111195;

Pin pin(num minutes, double lat, double lon, {double accuracy = 10}) => Pin(at: at(minutes), lat: lat, lon: lon, accuracy: accuracy);

/// A point every [every] minutes from [from] to [to], at one place.
List<Pin> still(num from, num to, double lat, double lon, {num every = 1, double accuracy = 10}) => [
  for (var minute = from; minute <= to; minute += every) pin(minute, lat, lon, accuracy: accuracy),
];

/// A point each minute from [from] to [to], on a straight line between two places.
List<Pin> line(int from, int to, (double, double) a, (double, double) b) => [
  for (var minute = from; minute <= to; minute++)
    pin(minute, a.$1 + (b.$1 - a.$1) * (minute - from + 1) / (to - from + 2), a.$2 + (b.$2 - a.$2) * (minute - from + 1) / (to - from + 2)),
];

StepResult once(List<Pin> points, num now, {List<MotionChange> motions = const []}) =>
  step(TimelineState.empty(), points, motions, at(now));

/// Each segment as `stay 0-10`, `stay 22+` for an ongoing one, or `trip driving 10-22`.
List<String> shape(Iterable<Segment> segments) => [
  for (final segment in segments)
    segment.isStay
      ? 'stay ${_minute(segment.start)}${segment.ongoing ? '+' : '-${_minute(segment.end)}'}'
      : 'trip ${segment.mode!.name} ${_minute(segment.start)}-${_minute(segment.end)}',
];
String _minute(DateTime time) {
  final minutes = time.difference(start).inSeconds / 60;
  return minutes == minutes.roundToDouble() ? '${minutes.round()}' : minutes.toStringAsFixed(1);
}

/// Steps [points] over several rounds, each with the points up to its time, as the store keeps them: only rows from
/// `keepFrom` on stay. Returns each segment, the newest for each start.
List<Segment> rounds(List<Pin> points, List<num> times, {List<MotionChange> motions = const []}) {
  var state = TimelineState.empty();
  var track = <Pin>[];
  final sent = <String, Segment>{};
  for (final time in times) {
    track = [...track, for (final point in points) if (!point.at.isAfter(at(time)) && !track.any((kept) => kept.at == point.at)
      && (state.cursor == null || point.at.isAfter(state.cursor!))) point];
    final result = step(state, track, motions, at(time));
    for (final segment in result.segments) {
      sent['${segment.isStay}:${segment.start.millisecondsSinceEpoch}'] = segment;
    }
    state = TimelineState.decode(result.state.encode());
    final keep = state.keepFrom;
    if (keep != null) track = [for (final point in track) if (!point.at.isBefore(keep)) point];
  }
  return sent.values.toList()..sort((a, b) => a.start.compareTo(b.start));
}

void main() {
  group('the timeline rules', () {
    final drive = [
      ...still(0, 10, homeLat, homeLon),
      ...line(12, 20, (homeLat, homeLon), (officeLat, officeLon)),
      ...still(22, 40, officeLat, officeLon, every: 2),
    ];

    test('a drive between two stays is one trip, driving, with its distance', () {
      final result = once(drive, 41);
      expect(shape(result.segments), ['stay 0-10', 'trip driving 10-22', 'stay 22+']);
      final trip = result.closed[1];
      expect(trip.km, closeTo(13.9, 0.1));
      expect(result.open!.toJson(), {'kind': 'stay', 'start': at(22).millisecondsSinceEpoch,
        'end': at(40).millisecondsSinceEpoch, 'ongoing': true, 'lat': officeLat, 'lon': officeLon,
        'name': coordinatesOf(officeLat, officeLon), 'source': 'point'});
      expect(trip.toJson(), {'kind': 'trip', 'start': at(10).millisecondsSinceEpoch, 'end': at(22).millisecondsSinceEpoch,
        'mode': 'driving', 'km': trip.km});
    });

    test('a stop at a light on the way makes no stay', () {
      final withLight = [
        ...still(0, 10, homeLat, homeLon),
        ...line(12, 14, (homeLat, homeLon), (43.70, homeLon)),
        ...still(15, 17, 43.70, homeLon),
        ...line(18, 20, (43.70, homeLon), (officeLat, officeLon)),
        ...still(22, 40, officeLat, officeLon, every: 2),
      ];
      expect(shape(once(withLight, 41).segments), ['stay 0-10', 'trip driving 10-22', 'stay 22+']);
    });

    test('the same points over several rounds give the same stays and trips as one round', () {
      expect(shape(rounds(drive, [5, 11, 17, 26, 41])), shape(once(drive, 41).segments));
    });

    test('a night with no points is one stay, from the evening to the morning\'s last point', () {
      final night = [...still(0, 10, homeLat, homeLon), ...still(480, 490, homeLat, homeLon),
        ...line(492, 500, (homeLat, homeLon), (officeLat, officeLon))];
      expect(shape(once(night, 501).segments), ['stay 0-490']);
      expect(shape(rounds(night, [11, 120, 486, 501])), ['stay 0-490']);
    });

    test('one point and 30 minutes of silence is a stay, ongoing until now', () {
      expect(once([pin(0, homeLat, homeLon)], 29).segments, isEmpty);
      expect(shape(once([pin(0, homeLat, homeLon)], 31).segments), ['stay 0+']);
      expect(once([pin(0, homeLat, homeLon)], 31).open!.end, at(31));
    });

    test('a stay opens as ongoing at 5 minutes, and goes again each round its end moves on', () {
      expect(once(still(0, 4, homeLat, homeLon), 4.5).segments, isEmpty);
      final opened = once(still(0, 5, homeLat, homeLon), 5.5);
      expect([shape(opened.segments), opened.open!.end], [['stay 0+'], at(5)]);
      // New points: the end is the newest.
      final moved = step(opened.state, still(0, 8, homeLat, homeLon), const [], at(8.5));
      expect(moved.open!.end, at(8));
      // No new point and no move: the phone was still, so the end is the round's time.
      final quiet = step(moved.state, const [], const [], at(20));
      expect(quiet.open!.end, at(20));
      // Nothing moved since, or a sure move not yet 5 minutes long: nothing goes.
      expect(step(quiet.state, const [], const [], at(20)).segments, isEmpty);
      expect(step(quiet.state, const [], [MotionChange(at(21), MotionKind.walking)], at(23)).segments, isEmpty);
    });

    test('an iPhone visit\'s late departure ends the stay where the person left, and the trip starts there', () {
      final first = once([pin(0, homeLat, homeLon), pin(40, officeLat, officeLon)], 41);
      expect(shape(first.segments), ['stay 0-40']);
      final office = still(42, 46, officeLat, officeLon);
      final late = step(first.state, [pin(30, homeLat, homeLon), pin(40, officeLat, officeLon), ...office], const [], at(47),
        late: {at(30)});
      expect(shape(late.segments), ['stay 0-30', 'trip driving 30-40', 'stay 40+']);
      // Once the trip after it went, a late point changes nothing.
      expect(step(late.state, [pin(35, homeLat, homeLon), ...office], const [], at(46), late: {at(35)}).segments, isEmpty);
    });

    test('a late point after a stay that motion ended moves its end only when it is later', () {
      final walk = [MotionChange(at(20), MotionKind.walking)];
      final poor = pin(22, officeLat, officeLon, accuracy: 300);
      final first = once([...still(0, 10, homeLat, homeLon), poor], 26, motions: walk);
      expect(shape(first.segments), ['stay 0-20']);
      expect(step(first.state, [pin(15, homeLat, homeLon), poor], walk, at(27), late: {at(15)}).segments, isEmpty);
      expect(shape(step(first.state, [pin(21, homeLat, homeLon), poor], walk, at(27), late: {at(21)}).segments), ['stay 0-21']);
      // A point an earlier round stepped is not late, so more rounds give the same as fewer.
      expect(step(first.state, [pin(21, homeLat, homeLon), poor], walk, at(27)).segments, isEmpty);
    });

    test('a late point at the open stay\'s place joins it, and the stay goes again with it as its end', () {
      final poor = pin(12, officeLat, officeLon, accuracy: 300);
      final open = once([...still(0, 10, homeLat, homeLon), poor], 13);
      expect(open.open!.end, at(10));
      final joined = step(open.state, [pin(10, homeLat, homeLon), pin(11, homeLat, homeLon), poor], const [], at(14),
        late: {at(11)});
      expect(joined.open!.end, at(11));
    });

    test('a stay a sure move ended gives the same over more rounds, with a point near it after the move', () {
      final points = [...still(0, 9, homeLat, homeLon), pin(15.5, homeLat, homeLon)];
      final walk = [MotionChange(at(10), MotionKind.walking)];
      expect(shape(rounds(points, [15, 16, 17], motions: walk)), shape(rounds(points, [15, 17], motions: walk)));
      expect(shape(rounds(points, [15, 16, 17], motions: walk)), ['stay 0-10']);
    });

    test('any move, sure or not, ends sure stillness: a sparse walk after it makes no stay', () {
      final walk = [for (final (i, minute) in [18, 24, 30].indexed) pin(minute, homeLat + north(400.0 * (i + 1)), homeLon)];
      final end = homeLat + north(1600);
      final points = [...still(0, 10, homeLat, homeLon), ...walk, ...still(36, 46, end, homeLon)];
      final motions = [MotionChange(at(0), MotionKind.stationary), MotionChange(at(12), MotionKind.walking, sure: false)];
      expect(shape(once(points, 47, motions: motions).segments), ['stay 0-10', 'trip walking 10-36', 'stay 36+']);
    });

    test('5 minutes of sure stillness on a trip, inside 100 m, is a stay that splits the trip', () {
      final shop = 43.70;
      final points = [
        ...still(0, 10, homeLat, homeLon),
        ...line(12, 14, (homeLat, homeLon), (shop, homeLon)),
        pin(15, shop, homeLon),
        ...line(24, 26, (shop, homeLon), (officeLat, officeLon)),
        ...still(28, 40, officeLat, officeLon, every: 2),
      ];
      List<MotionChange> stopped(num minutes) => [MotionChange(at(11), MotionKind.driving),
        MotionChange(at(15), MotionKind.stationary), MotionChange(at(15 + minutes), MotionKind.driving)];
      expect(shape(once(points, 41, motions: stopped(8)).segments),
        ['stay 0-11', 'trip driving 11-15', 'stay 15-23', 'trip driving 23-28', 'stay 28+']);
      // Stillness under 5 minutes, or an unsure one, is a stop at a light.
      expect(shape(once(points, 41, motions: stopped(3)).segments), ['stay 0-11', 'trip driving 11-28', 'stay 28+']);
      expect(shape(once(points, 41, motions: [MotionChange(at(15), MotionKind.stationary, sure: false)]).segments),
        ['stay 0-10', 'trip driving 10-28', 'stay 28+']);
      // Still for 5 minutes by the round's end: the stay is open.
      expect(shape(once(points.where((point) => point.at.isBefore(at(16))).toList(), 22, motions: stopped(20)).segments),
        ['stay 0-11', 'trip driving 11-15', 'stay 15+']);
    });

    test('two stays at one place 10 minutes apart are one', () {
      final away = 43.65 + north(330);
      final points = [...still(0, 10, homeLat, homeLon), pin(13, away, homeLon), pin(15, away, homeLon),
        ...still(20, 30, homeLat, homeLon)];
      expect(shape(once(points, 31).segments), ['stay 0+']);
      expect(shape(rounds(points, [11, 16, 31])), ['stay 0+']);
    });

    test('a fix less sure than 250 m joins no stay, and alone makes none', () {
      final points = [...still(0, 10, homeLat, homeLon), pin(12, officeLat, officeLon, accuracy: 300), ...still(14, 20, homeLat, homeLon)];
      expect(shape(once(points, 21).segments), ['stay 0+']);
      expect(once([pin(0, homeLat, homeLon, accuracy: 300)], 60).segments, isEmpty);
    });

    test('a slow walk never drags a stay along', () {
      final walk = [for (var minute = 0; minute <= 30; minute++) pin(minute, homeLat + north(40.0 * minute), homeLon)];
      expect(once(walk, 31).segments, isEmpty);
    });

    test('motion beats speed: a bus at 18 km/h with the phone saying driving is a drive', () {
      final bus = [
        ...still(0, 10, homeLat, homeLon),
        for (var minute = 12; minute <= 40; minute++) pin(minute, homeLat + north(300.0 * (minute - 11)), homeLon),
        ...still(42, 50, homeLat + north(300.0 * 31), homeLon),
      ];
      final motions = [MotionChange(at(11), MotionKind.driving), MotionChange(at(41), MotionKind.stationary)];
      expect(shape(once(bus, 51, motions: motions).segments), ['stay 0-11', 'trip driving 11-42', 'stay 42+']);
      expect(shape(once(bus, 51).segments), ['stay 0-10', 'trip cycling 10-42', 'stay 42+']);
      // Motion that covers less than half the trip leaves it to speed.
      final short = [MotionChange(at(11), MotionKind.driving), MotionChange(at(14), MotionKind.stationary, sure: false)];
      expect(once(bus, 51, motions: short).closed[1].mode, TripMode.cycling);
    });

    test('speed bands: under 8 km/h walking, under 25 cycling, up to 250 driving, above flying', () {
      expect([for (final kmh in [0.0, 7.9, 8.0, 24.9, 25.0, 250.0, 250.1]) modeOfSpeed(kmh)], [TripMode.walking,
        TripMode.walking, TripMode.cycling, TripMode.cycling, TripMode.driving, TripMode.driving, TripMode.flying]);
    });

    test('a trip of 3 hours with no point inside has no mode to tell', () {
      final points = [...still(0, 10, homeLat, homeLon), ...still(190, 200, officeLat, officeLon)];
      final motions = [MotionChange(at(11), MotionKind.driving)];
      expect(shape(once(points, 201, motions: motions).segments), ['stay 0-11', 'trip unknown 11-190', 'stay 190+']);
      // With no move to end the first stay, the silence keeps the phone there until its next point.
      expect(shape(once(points, 201).segments), ['stay 0-190', 'trip unknown 190-190', 'stay 190+']);
    });

    test('a sure move ends a stay at its start; an unsure one, or a stop after it, does not', () {
      final home = still(0, 10, homeLat, homeLon);
      expect(shape(once(home, 26, motions: [MotionChange(at(20), MotionKind.walking)]).segments), ['stay 0-20']);
      expect(shape(once(home, 26, motions: [MotionChange(at(20), MotionKind.walking, sure: false)]).segments), ['stay 0+']);
      expect(shape(once(home, 26, motions: [MotionChange(at(20), MotionKind.walking), MotionChange(at(22), MotionKind.stationary)])
        .segments), ['stay 0+']);
      // A move still under 5 minutes waits.
      expect(shape(once(home, 23, motions: [MotionChange(at(20), MotionKind.walking)]).segments), ['stay 0+']);
    });

    test('the state reads back as it was saved, and one that does not read starts empty', () {
      final result = once(drive, 41);
      final again = TimelineState.decode(result.state.encode());
      expect(again.encode(), result.state.encode());
      expect([again.keepFrom, again.cursor], [at(40).add(const Duration(milliseconds: 1)), at(40)]);
      expect(TimelineState.decode('{not json').encode(), TimelineState.empty().encode());
      expect(TimelineState.decode(null).keepFrom, isNull);
    });
  });

  group('a stay\'s name', () {
    final stay = Segment.stay(start: at(0), end: at(60), lat: homeLat, lon: homeLon, accuracy: 10);
    final calendar = FakeCalendar();
    final places = FakePlaces();
    final swift = FakeBackground();
    StayNamer namer({bool withCalendar = true}) => stayNamer(Settings(sending: true, history: true, calendar: withCalendar),
      places: places, native: swift, calendar: calendar);
    PhoneEvent event(String location, {String title = 'Coffee with Sam', bool allDay = false}) => PhoneEvent(calendarId: 'work',
      eventId: location, title: title, start: at(10), end: at(40), location: location, allDay: allDay);

    setUp(() {
      calendar.items = [];
      places.places.clear();
      calendar.reads.clear();
      places.lookups.clear();
      places.placeLookups.clear();
      places.streetFails = false;
      swift.venueName = null;
      swift.venues.clear();
    });

    test('a calendar event at the place names it first, with the event and the street', () async {
      calendar.items = [event('Cafe Nero, 123 King St W, Toronto')];
      places.places['Cafe Nero, 123 King St W, Toronto'] = (lat: homeLat + north(80), lon: homeLon);
      swift.venueName = 'Some Cafe';
      final name = await namer().name(stay);
      expect(name.toJson(), {'name': 'Cafe Nero', 'source': 'calendar', 'address': 'Place 1', 'event': 'Coffee with Sam'});
      expect(swift.venues, isEmpty);
    });

    test('an event place that starts with a number goes by the event\'s title', () async {
      calendar.items = [event('123 King St W, Toronto')];
      places.places['123 King St W, Toronto'] = (lat: homeLat, lon: homeLon);
      expect((await namer().name(stay)).name, 'Coffee with Sam');
    });

    test('a link, an all-day event or a far place is no place: an online meeting at home never renames home', () async {
      calendar.items = [event('https://zoom.us/j/123'), event('meet.google.com/abc-defg-hij'), event('Home office', allDay: true),
        event('Head office')];
      places.places['Home office'] = (lat: homeLat, lon: homeLon);
      places.places['Head office'] = (lat: homeLat + north(200), lon: homeLon);
      final name = await namer().name(stay);
      expect([name.name, name.source], ['Place 1', NameSource.street]);
      expect(places.placeLookups, ['Head office']);
    });

    test('with Calendar off, no event is read', () async {
      calendar.items = [event('Cafe Nero')];
      places.places['Cafe Nero'] = (lat: homeLat, lon: homeLon);
      expect((await namer(withCalendar: false).name(stay)).source, NameSource.street);
      expect(calendar.reads, isEmpty);
    });

    test('Apple Maps names it only with a fix within 50 m', () async {
      swift.venueName = 'Union Station';
      expect((await namer().name(stay)).toJson(), {'name': 'Union Station', 'source': 'map', 'address': 'Place 1'});
      final rough = Segment.stay(start: at(0), end: at(60), lat: homeLat, lon: homeLon, accuracy: 80);
      expect((await namer().name(rough)).source, NameSource.street);
      expect(swift.venues.length, 1);
    });

    test('a lookup that fails goes to the next, down to the coordinates', () async {
      places.streetFails = true;
      expect((await namer().name(stay)).toJson(), {'name': '43.625, -79.375', 'source': 'point'});
    });
  });

  group('the stays round', () {
    late Store store;
    setUp(() => store = memoryStore());
    tearDown(() => store.close());
    const settings = Settings(sending: true, history: true);

    Future<void> add(List<Pin> points) async {
      for (final point in points) {
        await store.addPoint(point);
      }
    }

    List<Map<String, dynamic>> queued(List<OutboxItem> items) => [
      for (final item in items) for (final stay in item.body['stays'] as List) stay as Map<String, dynamic>,
    ];

    test('a stay opens in one round and closes in the next, and the points it no longer needs go', () async {
      final places = FakePlaces();
      await add(still(0, 10, homeLat, homeLon));
      expect(await syncStays(store, settings, namer: stayNamer(settings, places: places), now: at(11)), 1);
      final first = queued(await store.outbox());
      expect([first.single['ongoing'], first.single['name'], first.single['source']], [true, 'Place 1', 'street']);
      expect((await store.track()).length, 0);
      await add([...line(12, 20, (homeLat, homeLon), (officeLat, officeLon)), ...still(22, 30, officeLat, officeLon)]);
      expect(await syncStays(store, settings, namer: stayNamer(settings, places: places), now: at(31)), 3);
      final all = queued(await store.outbox());
      expect([for (final stay in all) (stay['kind'], stay['ongoing'], stay['name'])], [('stay', true, 'Place 1'),
        ('stay', null, 'Place 1'), ('trip', null, null), ('stay', true, 'Place 2')]);
      expect(await store.waitingStays(), 4);
      // The closed stay kept its name, so only the new one was looked up.
      expect(places.lookups.length, 2);
      expect(await store.track(), isEmpty);
    });

    test('a round cut before its save keeps every point, and the next does the step again', () async {
      await add(still(0, 10, homeLat, homeLon));
      final state = await store.timeline();
      final result = step(state, await store.track(), await store.motions(), at(11));
      expect(result.segments.length, 1);
      // Cut here: nothing was saved.
      expect([(await store.track()).length, await store.waitingStays()], [11, 0]);
      expect(await syncStays(store, settings, now: at(11)), 1);
      expect(await store.waitingStays(), 1);
    });

    test('names at most 3 stays a round; the rest go as their coordinates', () async {
      final points = <Pin>[];
      for (var i = 0; i < 5; i++) {
        points.addAll(still(i * 20, i * 20 + 10, homeLat + north(1000.0 * i), homeLon));
      }
      await add(points);
      final places = FakePlaces();
      await syncStays(store, settings, namer: stayNamer(settings, places: places), now: at(120));
      final stays = [for (final stay in queued(await store.outbox())) if (stay['kind'] == 'stay') stay];
      expect([for (final stay in stays) stay['source']], ['street', 'street', 'street', 'point', 'point']);
      expect(places.lookups.length, 3);
    });

    test('reads motion from the open stay or trip on, and a stay ends where the move began', () async {
      final motion = FakeMotion()..changes = [MotionChange(at(20), MotionKind.walking)];
      await add(still(0, 10, homeLat, homeLon));
      await syncStays(store, settings, motion: motion, now: at(11));
      await syncStays(store, settings, motion: motion, now: at(30));
      expect(motion.reads.last, (at(10).add(const Duration(milliseconds: 1)), at(30)));
      final last = queued(await store.outbox()).last;
      expect([last['ongoing'], last['end']], [null, at(20).millisecondsSinceEpoch]);
    });

    test('with sending off, or Only points, makes no stays and asks nothing', () async {
      await add(still(0, 10, homeLat, homeLon));
      final places = FakePlaces();
      final motion = FakeMotion();
      expect(await syncStays(store, const Settings(history: true), motion: motion, namer: stayNamer(settings, places: places),
        now: at(60)), 0);
      expect(await syncStays(store, const Settings(sending: true, history: true, locationSend: LocationSend.points), motion: motion,
        now: at(60)), 0);
      expect([places.lookups, motion.reads, await store.outbox()], [isEmpty, isEmpty, isEmpty]);
    });
  });

  group('the store', () {
    late Store store;
    setUp(() => store = memoryStore());
    tearDown(() => store.close());

    test('a point goes as a point, into the timeline, or both, by What to send', () async {
      await store.addPoint(pin(0, 1, 1));
      await store.addPoint(pin(1, 1, 1), send: LocationSend.stays);
      await store.addPoint(pin(2, 1, 1), send: LocationSend.points);
      expect([await store.waitingPoints(), [for (final point in await store.track()) _minute(point.at)]], [2, ['0', '1']]);
    });

    test('dropping readings, or the timeline, clears the track, motion, state and waiting stays', () async {
      await store.addPoint(pin(0, homeLat, homeLon));
      await store.addMotions([MotionChange(at(0), MotionKind.walking)]);
      await syncStays(store, const Settings(sending: true, history: true), now: at(60));
      expect([await store.waitingStays(), await store.get(timelineKey)], [1, isNotNull]);
      await store.addPoint(pin(61, homeLat, homeLon));
      await store.dropTimeline();
      expect([await store.track(), await store.motions(), await store.get(timelineKey), await store.waitingStays()],
        [isEmpty, isEmpty, isNull, 1]);
      await store.addPoint(pin(62, homeLat, homeLon));
      await store.addMotions([MotionChange(at(62), MotionKind.walking)]);
      await store.dropReadings();
      expect([await store.track(), await store.motions(), await store.get(timelineKey), await store.waitingStays()],
        [isEmpty, isEmpty, isNull, 0]);
    });

    test('closing the timeline queues the open stay ended at its last point, then drops it', () async {
      for (final point in still(0, 10, homeLat, homeLon)) {
        await store.addPoint(point);
      }
      await syncStays(store, const Settings(sending: true, history: true), now: at(30));
      await store.closeTimeline();
      final stay = ((await store.outbox()).last.body['stays'] as List).single as Map;
      expect([stay['ongoing'], stay['end']], [null, at(10).millisecondsSinceEpoch]);
      expect([await store.track(), await store.get(timelineKey), await store.waitingStays()], [isEmpty, isNull, 2]);
      await store.closeTimeline();
      expect(await store.waitingStays(), 2);
    });

    test('closing the timeline ends a still stay at the later end already sent, not its one point', () async {
      await store.addPoint(pin(0, homeLat, homeLon));
      const settings = Settings(sending: true, history: true);
      await syncStays(store, settings, now: at(31));
      await syncStays(store, settings, now: at(240));
      expect((((await store.outbox()).last.body['stays'] as List).single as Map)['end'], at(240).millisecondsSinceEpoch);
      await store.closeTimeline();
      final stay = ((await store.outbox()).last.body['stays'] as List).single as Map;
      expect([stay['ongoing'], stay['start'], stay['end']], [null, at(0).millisecondsSinceEpoch, at(240).millisecondsSinceEpoch]);
    });

    test('a point that comes after a round stepped past its time is marked late, and moves the stay it belongs to', () async {
      const settings = Settings(sending: true, history: true);
      await store.addPoint(pin(0, homeLat, homeLon));
      await store.addPoint(pin(40, officeLat, officeLon));
      await syncStays(store, settings, now: at(41));
      await store.addPoint(pin(30, homeLat, homeLon));
      await store.addPoint(pin(42, officeLat, officeLon));
      expect(await store.lateTrack(), {at(30)});
      await syncStays(store, settings, now: at(43));
      final stay = ((await store.outbox()).last.body['stays'] as List).first as Map;
      expect([stay['start'], stay['end']], [at(0).millisecondsSinceEpoch, at(30).millisecondsSinceEpoch]);
    });

    test('Only stays and trips drops the points still waiting, and says how many', () async {
      await store.addPoint(pin(0, 1, 1));
      await store.addPoint(pin(1, 1, 1));
      expect(await store.dropPoints(), 2);
      expect([await store.waitingPoints(), (await store.track()).length], [0, 2]);
    });

    test('keeps the motion change in effect when the open stay or trip began, and drops older ones', () async {
      await store.addMotions([for (final minute in [0, 5, 9, 30]) MotionChange(at(minute), MotionKind.walking)]);
      await store.queueStays(const [], TimelineState.decode(jsonEncode({'tripFrom': at(10).millisecondsSinceEpoch})));
      expect([for (final change in await store.motions()) _minute(change.at)], ['9', '30']);
    });

    test('upgrades a phone from version 10 with the track and motion tables', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
      final folder = tempFolder();
      final old = Store(NativeDatabase.memory(setup: (db) {
        for (final statement in [
          "CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, destination TEXT NOT NULL DEFAULT 'relay-server', "
            'route TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL)',
          'CREATE TABLE notes (client_id TEXT PRIMARY KEY, body TEXT NOT NULL, words_pending INTEGER NOT NULL DEFAULT 0, '
            'pinning INTEGER NOT NULL DEFAULT 0, sent_at INTEGER, queued INTEGER NOT NULL DEFAULT 0)',
          'CREATE TABLE points (at INTEGER PRIMARY KEY, body TEXT NOT NULL)',
          'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        ]) {
          db.execute(statement);
        }
        db.execute('PRAGMA user_version = 10');
      }), folder: () async => folder);
      addTearDown(old.close);
      await old.addPoint(pin(0, homeLat, homeLon));
      await old.addMotions([MotionChange(at(0), MotionKind.walking)]);
      expect([(await old.track()).length, (await old.motions()).length, await old.waitingPoints()], [1, 1, 1]);
    });
  });
}
