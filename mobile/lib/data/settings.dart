import 'dart:convert';

/// The store key the settings live under.
const settingsKey = 'settings';

/// How the iPhone keeps places while the app is closed, after OwnTracks: [battery] at each move of about 500 m and each
/// arrival and departure; [move] each 100 m, or each 5 minutes while still. Android keeps a point each 100 m.
enum LocationMode { battery, move }

/// Where sending goes: the person's Relay Everything [server], or their own [webhook]. Never both.
enum SendPlace { server, webhook }

/// Light or dark: [system] follows the phone's own setting; [light] and [dark] keep that look whatever the phone says.
enum Appearance { system, light, dark }

/// What the person turned on. Each asks for its permission when turned on, and never before.
///
/// Sending is off by default: notes stay on this phone. Health, location history, the calendar and photos exist only to
/// send, so they are off whenever sending is off. [calendarsOff] holds the ids of the phone's calendars the person turned
/// off. Photos go where health and places go: see [privatePlace]. Photos on mobile data is off whenever photos is off.
class Settings {
  const Settings({this.sending = false, this.pinNotes = false, bool history = false, bool health = false,
    bool calendar = false, this.calendarsOff = const {}, this.mode = LocationMode.battery, this.place = SendPlace.server,
    this.privateTo = SendPlace.server, bool photos = false, bool photosOnMobileData = false,
    this.appearance = Appearance.system})
    : history = sending && history, health = sending && health, calendar = sending && calendar,
      photos = sending && photos, photosOnMobileData = sending && photos && photosOnMobileData;

  final bool sending;
  final bool pinNotes;
  final bool history;
  final bool health;
  final bool calendar;
  final Set<String> calendarsOff;
  final LocationMode mode;
  /// Where sending goes. Settings from before there was a choice read as [SendPlace.server].
  final SendPlace place;
  /// Where health, location points, calendar events and photos go while [place] is the server: there too, or only to
  /// the person's own webhook. Settings from before there was a choice read as [SendPlace.server]. It stays through
  /// *Sign out*, so a sign-in again keeps the choice.
  final SendPlace privateTo;
  /// Sends new photos, taken since it turned on.
  final bool photos;
  /// Off: photos wait for Wi-Fi.
  final bool photosOnMobileData;
  /// Light or dark. Settings from before there was a choice read as [Appearance.system].
  final Appearance appearance;

  /// Where health, location points, calendar events and photos go now: the webhook while [place] is the webhook, else
  /// [privateTo]. Only this is read to route them, so whole-webhook sending needs no case of its own.
  SendPlace get privatePlace => place == SendPlace.webhook ? SendPlace.webhook : privateTo;

  Settings copyWith({bool? sending, bool? pinNotes, bool? history, bool? health, bool? calendar, Set<String>? calendarsOff,
    LocationMode? mode, SendPlace? place, SendPlace? privateTo, bool? photos, bool? photosOnMobileData,
    Appearance? appearance}) => Settings(
    sending: sending ?? this.sending, pinNotes: pinNotes ?? this.pinNotes,
    history: history ?? this.history, health: health ?? this.health, calendar: calendar ?? this.calendar,
    calendarsOff: calendarsOff ?? this.calendarsOff, mode: mode ?? this.mode, place: place ?? this.place,
    privateTo: privateTo ?? this.privateTo, photos: photos ?? this.photos,
    photosOnMobileData: photosOnMobileData ?? this.photosOnMobileData,
    appearance: appearance ?? this.appearance);

  String encode() => jsonEncode({'sending': sending, 'pinNotes': pinNotes, 'history': history, 'health': health,
    'calendar': calendar, 'calendarsOff': (calendarsOff.toList()..sort()), 'mode': mode.name, 'place': place.name,
    'privateTo': privateTo.name, 'photos': photos, 'photosOnMobileData': photosOnMobileData, 'appearance': appearance.name});

  /// Reads saved settings. Settings from before sending was a switch, or none on a phone with a key, come from the
  /// first version, which sent everything: that install keeps sending on, so nothing it set up stops. Settings from
  /// before photos have photos off.
  factory Settings.decode(String? saved, {required bool hasKey}) {
    final json = saved == null ? null : jsonDecode(saved) as Map<String, dynamic>;
    final firstVersion = json == null ? hasKey : !json.containsKey('sending');
    if (json == null) return firstVersion ? const Settings(sending: true, pinNotes: true) : const Settings();
    return Settings(
      sending: firstVersion ? hasKey : json['sending'] as bool? ?? false,
      pinNotes: json['pinNotes'] as bool? ?? firstVersion,
      history: json['history'] as bool? ?? false,
      health: json['health'] as bool? ?? false,
      calendar: json['calendar'] as bool? ?? false,
      calendarsOff: {for (final id in json['calendarsOff'] as List? ?? const []) if (id is String) id},
      mode: LocationMode.values.asNameMap()[json['mode']] ?? LocationMode.battery,
      place: SendPlace.values.asNameMap()[json['place']] ?? SendPlace.server,
      privateTo: SendPlace.values.asNameMap()[json['privateTo']] ?? SendPlace.server,
      photos: json['photos'] as bool? ?? false,
      photosOnMobileData: json['photosOnMobileData'] as bool? ?? false,
      appearance: Appearance.values.asNameMap()[json['appearance']] ?? Appearance.system,
    );
  }
}
