import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart' as plugin;

import '../data/settings.dart';
import '../data/store.dart';

/// One calendar on the phone: Google, iCloud, Outlook, work or subscribed. [account] is where it comes from, such as
/// an email address, to tell two calendars of the same name apart.
class PhoneCalendar {
  const PhoneCalendar({required this.id, required this.name, this.account});

  final String id;
  final String name;
  final String? account;
}

/// One person on an event.
class EventPerson {
  const EventPerson({this.name, this.email, this.organizer = false});

  final String? name;
  final String? email;
  final bool organizer;
}

/// One occurrence of an event: each occurrence of a repeating event is its own, with its own start.
class PhoneEvent {
  const PhoneEvent({required this.calendarId, required this.eventId, required this.title, required this.start,
    required this.end, this.allDay = false, this.location, this.notes, this.url, this.people = const [],
    this.cancelled = false});

  final String calendarId;
  final String eventId;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? notes;
  final String? url;
  final List<EventPerson> people;
  final bool cancelled;

  /// The event's key on the server: `<calendarId>:<eventId>:<startMs>`, so each occurrence is its own row.
  String get key => '$calendarId:$eventId:${start.millisecondsSinceEpoch}';
}

/// Where events come from: the phone's calendars, or a test's list. It only reads.
abstract class CalendarSource {
  /// Asks for the phone's calendar permission; true when the app may read every event.
  Future<bool> allow();

  /// Every calendar on the phone. Throws when the app may not read them, so a revoked permission removes nothing.
  Future<List<PhoneCalendar>> calendars();

  /// The events of [calendarIds] that overlap `[from, to)`.
  Future<List<PhoneEvent>> events(DateTime from, DateTime to, Set<String> calendarIds);
}

/// The calendar may not be read, such as after the person took the permission back in the phone's settings.
class CalendarRefused implements Exception {
  const CalendarRefused();
}

/// The phone's own calendars, through EventKit on iPhone and CalendarContract on Android.
class PhoneCalendarSource implements CalendarSource {
  plugin.DeviceCalendar get _calendar => plugin.DeviceCalendar.instance;

  @override
  Future<bool> allow() async => await _calendar.requestPermissions() == plugin.CalendarPermissionStatus.granted;

  Future<void> _check() async {
    if (await _calendar.hasPermissions() != plugin.CalendarPermissionStatus.granted) throw const CalendarRefused();
  }

  @override
  Future<List<PhoneCalendar>> calendars() async {
    await _check();
    return [
      for (final calendar in await _calendar.listCalendars())
        if (!calendar.hidden) PhoneCalendar(id: calendar.id, name: calendar.name, account: calendar.accountName),
    ];
  }

  @override
  Future<List<PhoneEvent>> events(DateTime from, DateTime to, Set<String> calendarIds) async {
    if (calendarIds.isEmpty) return const [];
    await _check();
    return [
      for (final event in await _calendar.listEvents(from, to, calendarIds: calendarIds.toList()))
        PhoneEvent(calendarId: event.calendarId, eventId: event.eventId, title: event.title, start: event.startDate,
          end: event.endDate, allDay: event.isAllDay, location: event.location, notes: event.description, url: event.url,
          cancelled: event.status == plugin.EventStatus.canceled, people: _peopleOf(event)),
    ];
  }

  static List<EventPerson> _peopleOf(plugin.Event event) {
    final organizer = event.organizer;
    final email = organizer?.emailAddress?.toLowerCase();
    final people = [
      for (final person in event.attendees ?? const <plugin.Attendee>[])
        EventPerson(name: person.name, email: person.emailAddress,
          organizer: email != null && person.emailAddress?.toLowerCase() == email),
    ];
    if (organizer != null && !people.any((person) => person.organizer)) {
      people.insert(0, EventPerson(name: organizer.name, email: organizer.emailAddress, organizer: true));
    }
    return people;
  }
}

/// How far back and ahead the phone reads its calendars.
const calendarWindow = Duration(days: 90);
const _perUpload = 200;
// The server takes a body up to 256 KB; each upload stays well under it.
const _uploadBytes = 200000;

String? _cut(String? text, int most) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.length <= most ? trimmed : trimmed.substring(0, most);
}

/// An event as the server's `calendar` route takes it, with times in ms since 1970, as health and places send them.
/// The calendar's name goes, cut to 200 characters; its id does not. Title and place are cut to 500, notes to 4,000, people to 100.
Map<String, dynamic> eventBody(PhoneEvent event, String calendar) {
  final start = event.start.millisecondsSinceEpoch;
  final end = event.end.millisecondsSinceEpoch;
  return {
    'key': event.key, 'calendar': _cut(calendar, 200) ?? '', 'title': _cut(event.title, 500) ?? '', 'start': start,
    'end': end < start ? start : end, 'allDay': event.allDay,
    'location': ?_cut(event.location, 500),
    'notes': ?_cut(event.notes, 4000),
    'url': ?_cut(event.url, 2000),
    'people': [
      for (final person in event.people.take(100))
        {
          'name': ?_cut(person.name, 200),
          'email': ?_cut(person.email, 320),
          if (person.organizer) 'organizer': true,
        },
    ],
  };
}

/// The start a key holds, or null for one that is not an event key.
int? _startOf(String key) => int.tryParse(key.substring(key.lastIndexOf(':') + 1));

/// Reads the window from 90 days ago to 90 days ahead from each calendar not turned off, and queues what changed since
/// the last round: new and changed events, and the keys gone from the window, such as a cancelled meeting or a calendar
/// turned off. An event that left the window's past edge is forgotten with no removal: it happened. The first round
/// sends the whole window the same way. Each `calendar` upload holds up to 200 events and 200 removed keys. Returns how
/// many events and removals it queued.
Future<int> syncCalendar(Store store, CalendarSource source, Settings settings, {DateTime? now}) async {
  if (!settings.calendar) return 0;
  final at = now ?? DateTime.now();
  final from = at.subtract(calendarWindow), to = at.add(calendarWindow);
  final names = {
    for (final calendar in await source.calendars())
      if (!settings.calendarsOff.contains(calendar.id)) calendar.id: calendar.name,
  };
  final bodies = <String, Map<String, dynamic>>{};
  for (final event in names.isEmpty ? const <PhoneEvent>[] : await source.events(from, to, names.keys.toSet())) {
    final name = names[event.calendarId];
    if (name == null || event.cancelled) continue;
    bodies[event.key] = eventBody(event, name);
  }
  final sent = await store.calendarSent();
  final hashes = {for (final entry in bodies.entries) entry.key: sha256.convert(utf8.encode(jsonEncode(entry.value))).toString()};
  final changed = [for (final entry in bodies.entries) if (sent[entry.key] != hashes[entry.key]) entry.value];
  final removed = <String>[], forget = <String>[];
  for (final key in sent.keys) {
    if (bodies.containsKey(key)) continue;
    final start = _startOf(key);
    (start != null && start >= from.millisecondsSinceEpoch ? removed : forget).add(key);
  }
  if (changed.isEmpty && removed.isEmpty && forget.isEmpty) return 0;
  await store.queueCalendar(_uploads(changed, removed),
    {for (final body in changed) body['key'] as String: hashes[body['key']]!}, [...removed, ...forget]);
  return changed.length + removed.length;
}

/// Splits events and removed keys into uploads of up to 200 of each, and about 200 KB.
List<Map<String, dynamic>> _uploads(List<Map<String, dynamic>> events, List<String> removed) {
  final uploads = <Map<String, dynamic>>[];
  var batch = <Map<String, dynamic>>[], gone = <String>[];
  var bytes = 0;
  void close() {
    if (batch.isEmpty && gone.isEmpty) return;
    uploads.add({'events': batch, 'removed': gone});
    batch = [];
    gone = [];
    bytes = 0;
  }
  for (final event in events) {
    final size = utf8.encode(jsonEncode(event)).length + 1;
    if (batch.length == _perUpload || bytes + size > _uploadBytes) close();
    batch.add(event);
    bytes += size;
  }
  for (final key in removed) {
    final size = utf8.encode(key).length + 3;
    if (gone.length == _perUpload || bytes + size > _uploadBytes) close();
    gone.add(key);
    bytes += size;
  }
  close();
  return uploads;
}
