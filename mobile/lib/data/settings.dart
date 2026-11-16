import 'dart:convert';

/// The store key the settings live under.
const settingsKey = 'settings';

/// How the iPhone keeps places while the app is closed, after OwnTracks: [battery] at each move of about 500 m and each
/// arrival and departure; [move] each 100 m, or each 5 minutes while still. Android keeps a point each 100 m.
enum LocationMode { battery, move }

/// Where sending goes: the person's Relay Everything [server], or their own [webhook]. Never both.
enum SendPlace { server, webhook }

/// What location history sends: [all] stays, trips and points; [stays] only stays and trips, with no point leaving the
/// phone; [points] only points, as before stays and trips, with no motion asked for.
enum LocationSend { all, stays, points }

/// Light or dark: [system] follows the phone's own setting; [light] and [dark] keep that look whatever the phone says.
enum Appearance { system, light, dark }

/// What the person turned on. Each asks for its permission when turned on, and never before.
///
/// Sending is off by default: notes stay on this phone. Health, location history, the calendar and photos exist only to
/// send, so they are off whenever sending is off. [calendarsOff] holds the ids of the phone's calendars the person turned
/// off. Photos go where notes go: see [place]. Photos on mobile data is off whenever photos is off.
class Settings {
  const Settings({this.sending = false, bool history = false, bool health = false,
    bool calendar = false, this.calendarsOff = const {}, this.mode = LocationMode.battery, this.place = SendPlace.server,
    bool photos = false, bool photosOnMobileData = false,
    this.appearance = Appearance.system, this.locationSend = LocationSend.all, this.highlightColour = 'purple',
    this.testBuilds = false})
    : history = sending && history, health = sending && health, calendar = sending && calendar,
      photos = sending && photos, photosOnMobileData = sending && photos && photosOnMobileData;

  final bool sending;
  final bool history;
  final bool health;
  final bool calendar;
  final Set<String> calendarsOff;
  final LocationMode mode;
  /// Where sending goes: notes, health, location points, calendar events and photos, all to this one place. Settings
  /// from before there was a choice read as [SendPlace.server].
  final SendPlace place;
  /// Sends new photos, taken since it turned on.
  final bool photos;
  /// Off: photos wait for Wi-Fi.
  final bool photosOnMobileData;
  /// Light or dark. Settings from before there was a choice read as [Appearance.system].
  final Appearance appearance;
  /// What location history sends. Settings from before there was a choice read as [LocationSend.all].
  final LocationSend locationSend;
  /// The colour the note's highlight pen draws, one of `highlightColours`: kept, so it stays the same after the app
  /// closes, as in Apple Notes. Settings from before there was a choice read as purple.
  final String highlightColour;
  /// *Get test builds* on the Mac: updates offer test builds too, not only full releases.
  final bool testBuilds;

  /// Location history makes stays and trips.
  bool get stays => history && locationSend != LocationSend.points;

  Settings copyWith({bool? sending, bool? history, bool? health, bool? calendar, Set<String>? calendarsOff,
    LocationMode? mode, SendPlace? place, bool? photos, bool? photosOnMobileData,
    Appearance? appearance, LocationSend? locationSend, String? highlightColour, bool? testBuilds}) => Settings(
    sending: sending ?? this.sending,
    history: history ?? this.history, health: health ?? this.health, calendar: calendar ?? this.calendar,
    calendarsOff: calendarsOff ?? this.calendarsOff, mode: mode ?? this.mode, place: place ?? this.place,
    photos: photos ?? this.photos,
    photosOnMobileData: photosOnMobileData ?? this.photosOnMobileData,
    appearance: appearance ?? this.appearance, locationSend: locationSend ?? this.locationSend,
    highlightColour: highlightColour ?? this.highlightColour, testBuilds: testBuilds ?? this.testBuilds);

  String encode() => jsonEncode({'sending': sending, 'history': history, 'health': health,
    'calendar': calendar, 'calendarsOff': (calendarsOff.toList()..sort()), 'mode': mode.name, 'place': place.name,
    'photos': photos, 'photosOnMobileData': photosOnMobileData, 'appearance': appearance.name,
    'locationSend': locationSend.name, 'highlightColour': highlightColour,
    'testBuilds': testBuilds});

  /// True when [saved] comes from a build that sent health, places, the calendar and photos only to the person's own
  /// webhook while notes went to Relay Everything. That choice is gone: such a phone now sends everything to Relay
  /// Everything, and says so once. The next save drops the old field, so this is true only once.
  static bool hadPrivateWebhook(String? saved) {
    if (saved == null) return false;
    final json = jsonDecode(saved);
    return json is Map && json['privateTo'] == SendPlace.webhook.name && json['place'] != SendPlace.webhook.name;
  }

  /// Reads saved settings. Settings from before sending was a switch, or none on a phone with a key, come from the
  /// first version, which sent everything: that install keeps sending on, so nothing it set up stops. Settings from
  /// before photos have photos off.
  factory Settings.decode(String? saved, {required bool hasKey}) {
    final json = saved == null ? null : jsonDecode(saved) as Map<String, dynamic>;
    final firstVersion = json == null ? hasKey : !json.containsKey('sending');
    if (json == null) return firstVersion ? const Settings(sending: true) : const Settings();
    return Settings(
      sending: firstVersion ? hasKey : json['sending'] as bool? ?? false,
      history: json['history'] as bool? ?? false,
      health: json['health'] as bool? ?? false,
      calendar: json['calendar'] as bool? ?? false,
      calendarsOff: {for (final id in json['calendarsOff'] as List? ?? const []) if (id is String) id},
      mode: LocationMode.values.asNameMap()[json['mode']] ?? LocationMode.battery,
      place: SendPlace.values.asNameMap()[json['place']] ?? SendPlace.server,
      photos: json['photos'] as bool? ?? false,
      photosOnMobileData: json['photosOnMobileData'] as bool? ?? false,
      appearance: Appearance.values.asNameMap()[json['appearance']] ?? Appearance.system,
      locationSend: LocationSend.values.asNameMap()[json['locationSend']] ?? LocationSend.all,
      highlightColour: json['highlightColour'] as String? ?? 'purple',
      testBuilds: json['testBuilds'] as bool? ?? false,
    );
  }
}
