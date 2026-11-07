import 'dart:convert';

/// The store key the settings live under.
const settingsKey = 'settings';

/// What the person turned on. Each asks for its permission when turned on, and never before.
///
/// Sending is off by default: notes stay on this phone. Health, location history and photos exist only to send, so
/// they are off whenever sending is off. Photos on mobile data is off whenever photos is off.
class Settings {
  const Settings({this.sending = false, this.pinNotes = false, bool history = false, bool health = false,
    bool photos = false, bool photosOnMobileData = false})
    : history = sending && history, health = sending && health, photos = sending && photos,
      photosOnMobileData = sending && photos && photosOnMobileData;

  final bool sending;
  final bool pinNotes;
  final bool history;
  final bool health;
  /// Sends new photos, taken since it turned on.
  final bool photos;
  /// Off: photos wait for Wi-Fi.
  final bool photosOnMobileData;

  Settings copyWith({bool? sending, bool? pinNotes, bool? history, bool? health, bool? photos, bool? photosOnMobileData}) =>
    Settings(
      sending: sending ?? this.sending, pinNotes: pinNotes ?? this.pinNotes,
      history: history ?? this.history, health: health ?? this.health,
      photos: photos ?? this.photos, photosOnMobileData: photosOnMobileData ?? this.photosOnMobileData);

  String encode() => jsonEncode({'sending': sending, 'pinNotes': pinNotes, 'history': history, 'health': health,
    'photos': photos, 'photosOnMobileData': photosOnMobileData});

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
      photos: json['photos'] as bool? ?? false,
      photosOnMobileData: json['photosOnMobileData'] as bool? ?? false,
    );
  }
}
