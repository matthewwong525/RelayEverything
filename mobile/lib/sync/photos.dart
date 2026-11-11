import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/api.dart';
import '../data/settings.dart';
import '../data/store.dart';

/// When *Photos* turned on: only photos taken from then on go, never the library from before.
const photosSince = 'photos.since';
/// The newest photo queued so far; each round looks from here. It starts at [photosSince].
const photosAfter = 'photos.after';
/// The library ids handled already that the next look can find again, such as a photo taken in the same second as
/// [photosAfter]. Each goes once.
const photosSeen = 'photos.seen';
/// The library id whose copy failed last, with how many rounds it failed in. The next round tries it again.
const photosFailed = 'photos.failed';
/// The most rounds a photo's copy may fail before the photo is skipped.
const copyTries = 3;
/// The most photos one round queues.
const photoRound = 50;
/// The longest side of the copy the phone sends, in pixels: the most an AI uses. The server refuses a larger one.
const longSide = 1600;

/// One image in the phone's library.
class LibraryPhoto {
  const LibraryPhoto({required this.id, required this.takenAt, this.lat, this.lon});

  final String id;
  final DateTime takenAt;
  /// Where it was taken, or null for a photo with no place.
  final double? lat;
  final double? lon;
}

/// Where photos come from: the phone's library, or a test's list.
abstract class PhotoSource {
  /// Asks for photo access. True when the app may read photos: all of them, or on iPhone only the ones the person
  /// picked (*Limited*).
  Future<bool> allow();
  /// Images, never videos, taken at or after [from], oldest first, at most [limit].
  Future<List<LibraryPhoto>> find(DateTime from, {required int limit});
  /// False for a photo kept only in iCloud: making its copy downloads it.
  Future<bool> onPhone(LibraryPhoto photo);
  /// The photo as a JPEG at most [longSide] px on its long side, with no EXIF block; null when the phone can not
  /// make one.
  Future<Uint8List?> jpeg(LibraryPhoto photo);
}

/// The phone's photo library, through photo_manager: Apple Photos on iPhone, MediaStore on Android.
class PhonePhotos implements PhotoSource {
  // Images only; on Android the place needs its own permission, ACCESS_MEDIA_LOCATION.
  static const _access = PermissionRequestOption(
    androidPermission: AndroidPermission(type: RequestType.image, mediaLocation: true));

  @override
  Future<bool> allow() async => (await PhotoManager.requestPermissionExtend(requestOption: _access)).hasAccess;

  @override
  Future<List<LibraryPhoto>> find(DateTime from, {required int limit}) async {
    // A photo dated later than now has a wrong clock: it would move the next look past every photo still to come.
    final filter = FilterOptionGroup(
      createTimeCond: DateTimeCond(min: from, max: DateTime.now()),
      orders: const [OrderOption(type: OrderOptionType.createDate, asc: true)]);
    final assets = await PhotoManager.getAssetListRange(start: 0, end: limit, type: RequestType.image, filterOption: filter);
    return [
      for (final asset in assets)
        if (asset.type == AssetType.image) await _photoOf(asset),
    ];
  }

  Future<LibraryPhoto> _photoOf(AssetEntity asset) async {
    LatLng? point;
    try {
      // On Android 10 and later, only this call reads the real place.
      point = await asset.latlngAsync();
    } on Exception {
      point = asset.latLng;
    }
    final place = photoPlace(point?.latitude, point?.longitude);
    return LibraryPhoto(id: asset.id, takenAt: asset.createDateTime, lat: place?.$1, lon: place?.$2);
  }

  @override
  Future<bool> onPhone(LibraryPhoto photo) async {
    final asset = await AssetEntity.fromId(photo.id);
    return asset != null && await asset.isLocallyAvailable();
  }

  @override
  Future<Uint8List?> jpeg(LibraryPhoto photo) async {
    final asset = await AssetEntity.fromId(photo.id);
    if (asset == null) return null;
    final width = asset.orientatedWidth, height = asset.orientatedHeight;
    var box = width > 0 && height > 0 ? fitBox(width, height) : (longSide, longSide);
    // Each platform can round up or fill the box, so the copy's own size is checked, and once made smaller again.
    for (var tries = 0; tries < 2; tries++) {
      final bytes = await asset.thumbnailDataWithOption(_option(box));
      final size = bytes == null ? null : jpegSize(bytes);
      if (size == null) return null;
      final long = max(size.$1, size.$2);
      if (long <= longSide) return bytes;
      box = (max(1, box.$1 * longSide ~/ long), max(1, box.$2 * longSide ~/ long));
    }
    return null;
  }

  static ThumbnailOption _option((int, int) box) {
    final size = ThumbnailSize(box.$1, box.$2);
    // iPhone: one full-quality image, fitted inside the box, not filling it.
    return Platform.isIOS || Platform.isMacOS
      ? ThumbnailOption.ios(size: size, format: ThumbnailFormat.jpeg, quality: 80, deliveryMode: DeliveryMode.highQualityFormat,
          resizeMode: ResizeMode.exact, resizeContentMode: ResizeContentMode.fit)
      : ThumbnailOption(size: size, format: ThumbnailFormat.jpeg, quality: 80);
  }
}

/// The box a photo of [width] by [height] fits in with its long side at most [longSide], keeping its shape. A smaller
/// photo keeps its size.
(int, int) fitBox(int width, int height) {
  final long = max(width, height);
  if (long <= longSide) return (width, height);
  return (max(1, (width * longSide / long).round()), max(1, (height * longSide / long).round()));
}

/// A photo's place, or null when it has none: a phone gives 0, 0 or nothing for a photo with no place.
(double, double)? photoPlace(double? lat, double? lon) {
  if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) return null;
  if ((lat == 0 && lon == 0) || lat.abs() > 90 || lon.abs() > 180) return null;
  return (lat, lon);
}

/// A JPEG's own width and height, read from its frame header; null for bytes that are not a JPEG.
(int, int)? jpegSize(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var at = 2;
  while (at + 4 <= bytes.length) {
    if (bytes[at] != 0xFF) return null;
    final marker = bytes[at + 1];
    // Fill bytes, and markers with no length.
    if (marker == 0xFF) {
      at++;
      continue;
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      at += 2;
      continue;
    }
    // The image data or its end, with no frame header before them.
    if (marker == 0xD9 || marker == 0xDA) return null;
    final length = (bytes[at + 2] << 8) | bytes[at + 3];
    if (length < 2) return null;
    // A frame header: any SOF marker, but not DHT (C4), JPG (C8) or DAC (CC).
    if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      if (at + 9 > bytes.length) return null;
      final height = (bytes[at + 5] << 8) | bytes[at + 6];
      final width = (bytes[at + 7] << 8) | bytes[at + 8];
      return width == 0 || height == 0 ? null : (width, height);
    }
    at += 2 + length;
  }
  return null;
}

/// A random UUID (version 4) for a photo, so a resend is stored once.
String newPhotoId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// The phone's network now: Wi-Fi (or a cable), mobile data, or none.
enum Link { none, wifi, mobile }

/// Tells Wi-Fi from mobile data, and when it changes: the phone's own, or a test's.
abstract class Network {
  Future<Link> link();

  /// Each change of the phone's network while the app is open.
  Stream<Link> changes();
}

class PhoneNetwork implements Network {
  @override
  Future<Link> link() async {
    try {
      return linkOf(await Connectivity().checkConnectivity());
    } on Exception {
      return Link.none;
    }
  }

  @override
  Stream<Link> changes() => Connectivity().onConnectivityChanged.map(linkOf);
}

/// The [Link] that [results] name. A VPN on Wi-Fi reports both, so Wi-Fi wins over the rest.
Link linkOf(List<ConnectivityResult> results) {
  if (results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.ethernet)) return Link.wifi;
  if (results.isEmpty || results.every((result) => result == ConnectivityResult.none)) return Link.none;
  return Link.mobile;
}

/// True when photos may go on [link]: on Wi-Fi, or on any network while the person allows mobile data.
bool photosMayGo(Settings settings, Link link) => link == Link.wifi || (settings.photosOnMobileData && link != Link.none);

/// The photo step of a round, after the outbox: queues the new photos, then, with [send] and a network photos may
/// use, sends the queue oldest first through [api], the client for private data. Returns why the photo send stopped
/// early, or null. With photos or sending off it reads no library and sends nothing. With no [api], such as a webhook
/// the phone lost, the photos queue and wait. [keepGoing] is asked before each photo; when it says no, such as after
/// *Photos* turns off, the step stops there.
Future<Failure?> syncPhotos(Store store, Outbound? api, PhotoSource source, Network network,
  {required Settings settings, bool send = true, Future<bool> Function()? keepGoing, DateTime? now}) async {
  if (!settings.sending || !settings.photos) return null;
  final Link link;
  try {
    link = await network.link();
  } on Exception {
    return null;
  }
  final mayGo = photosMayGo(settings, link);
  try {
    await queuePhotos(store, source, network: mayGo, keepGoing: keepGoing, now: now);
  } on Exception {
    // The library can be closed, such as after photo access was turned off in the phone's Settings; the next round
    // looks again.
  }
  if (!send || !mayGo || api == null) return null;
  return sendPhotos(store, api, keepGoing: keepGoing);
}

/// Copies up to [photoRound] new photos into the queue, oldest first, and moves [photosAfter] to the newest one.
/// A photo taken before *Photos* turned on is skipped. A photo kept only in iCloud waits, with each photo after it,
/// until [network] allows the download. A photo the phone can not copy is skipped once. A photo the phone fails to
/// copy stops the round there, and is skipped once it failed in [copyTries] rounds. Each photo is
/// queued in one step with where the library was read to, so a round cut short, such as by an error or by the phone
/// ending a background task, never queues a photo twice. Returns how many it queued.
Future<int> queuePhotos(Store store, PhotoSource source, {required bool network, Future<bool> Function()? keepGoing,
  DateTime? now}) async {
  final since = int.tryParse(await store.get(photosSince) ?? '');
  if (since == null) return 0;
  final after = int.tryParse(await store.get(photosAfter) ?? '') ?? since;
  final seen = {for (final id in jsonDecode(await store.get(photosSeen) ?? '[]') as List) id as String};
  final limit = photoRound + seen.length;
  final found = await source.find(DateTime.fromMillisecondsSinceEpoch(after), limit: limit);
  // Library times are whole seconds, so a photo in the second the switch turned on counts as new.
  final from = since - since % 1000;
  final latest = (now ?? DateTime.now()).millisecondsSinceEpoch;
  // A look that came back whole shows every id it can find again; a cut-off look may have left some out.
  final handled = found.length < limit ? {for (final photo in found) if (seen.contains(photo.id)) photo.id} : {...seen};
  final failed = {
    for (final MapEntry(:key, :value) in (jsonDecode(await store.get(photosFailed) ?? '{}') as Map).entries)
      key as String: value as int,
  };
  var newest = after, queued = 0;
  Map<String, String> readTo() =>
    {photosAfter: '$newest', photosSeen: jsonEncode([...handled]), photosFailed: jsonEncode(failed)};
  for (final photo in found) {
    if (seen.contains(photo.id)) continue;
    if (queued == photoRound) break;
    final taken = photo.takenAt.millisecondsSinceEpoch;
    if (taken < from) {
      handled.add(photo.id);
      continue;
    }
    if (!network && !await source.onPhone(photo)) break;
    if (keepGoing != null && !await keepGoing()) break;
    final Uint8List? bytes;
    try {
      bytes = await source.jpeg(photo);
    } on Exception {
      // Such as an iCloud download that failed: the photo and each one after it wait for the next round. After
      // [copyTries] failed rounds the photo is skipped, so one broken photo can not hold back the rest.
      final tries = (failed[photo.id] ?? 0) + 1;
      // The round stops at the failed photo, so only its count can still matter.
      failed.clear();
      if (tries >= copyTries) {
        handled.add(photo.id);
        continue;
      }
      failed[photo.id] = tries;
      break;
    }
    failed.remove(photo.id);
    final size = bytes == null ? null : jpegSize(bytes);
    handled.add(photo.id);
    if (bytes == null || size == null || max(size.$1, size.$2) > longSide) continue;
    final clientId = newPhotoId();
    final path = photoPathOf(clientId);
    final file = await store.photoFile(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    newest = max(newest, min(taken, latest));
    await store.addPhoto(QueuedPhoto(clientId: clientId, assetId: photo.id, takenAt: photo.takenAt, lat: photo.lat, lon: photo.lon,
      width: size.$1, height: size.$2, path: path), state: readTo());
    // *Photos* can turn off while the copy is made, such as in the app during a background round. The app's drop of
    // the queue can be done already, so this photo and its copy go now.
    if (keepGoing != null && !await keepGoing()) {
      await store.photoDone(clientId);
      return queued;
    }
    queued++;
  }
  for (final MapEntry(:key, :value) in readTo().entries) {
    await store.set(key, value);
  }
  return queued;
}

/// Sends the waiting photos oldest first: to the server's `photos` route, or as `photo.created` messages to the
/// person's own webhook. A photo turned down (400 or 413 from the server, 413 from a webhook) is dropped with its copy:
/// it would never land. Any other failure stops the photo send there and keeps the rest. A photo the server refuses
/// asks it about the key (`GET key`): a refused key is [Failure.refused], as for the notes; a key that answers is an
/// older server whose phone keys may not send photos, so only the photo send stops, with no failure.
Future<Failure?> sendPhotos(Store store, Outbound api, {Future<bool> Function()? keepGoing}) async {
  for (final photo in await store.waitingPhotos()) {
    if (keepGoing != null && !await keepGoing()) break;
    final file = await store.photoFile(photo.path);
    if (await file.exists()) {
      try {
        await api.sendPhoto(photo, await file.readAsBytes());
      } on ApiException catch (error) {
        if (error.failure == Failure.refused) return api is RelayApi ? _keyFailure(api) : error.failure;
        if (error.failure != Failure.rejected) return error.failure;
      }
    }
    await store.photoDone(photo.clientId);
  }
  return null;
}

/// Why the key does not work, after a refused photo: null when it answers, such as on an older server with no photos.
Future<Failure?> _keyFailure(RelayApi api) async {
  try {
    await api.key();
    return null;
  } on ApiException catch (error) {
    return error.failure;
  }
}

/// Drops the waiting photos and their copies, and forgets where the library was read to, for when *Photos* or
/// sending turns off: a later turn-on starts again from that moment.
Future<void> dropPhotoQueue(Store store) async {
  await store.dropPhotos();
  for (final key in [photosSince, photosAfter, photosSeen, photosFailed]) {
    await store.remove(key);
  }
}
