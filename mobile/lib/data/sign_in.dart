import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// The app's own address, where the sign-in page sends its one-time code back.
const callbackScheme = 'relayeverything';

/// Opens the sign-in page inside the app and returns the address it came back to, or null when the person closed it.
typedef WebAuth = Future<Uri?> Function(Uri url);

/// The sign-in inside the app: Safari's sign-in sheet on iPhone, a Custom Tab on Android.
Future<Uri?> phoneWebAuth(Uri url) async {
  try {
    return Uri.parse(await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: callbackScheme));
  } on PlatformException catch (error) {
    if (error.code == 'CANCELED') return null;
    rethrow;
  }
}

String _base64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// A secret only this phone holds, for one sign-in: 32 random bytes.
String newVerifier([Random? random]) {
  final source = random ?? Random.secure();
  return _base64Url(List.generate(32, (_) => source.nextInt(256)));
}

/// What the page keeps of the secret: its SHA-256, so a code another app catches is no use without the secret.
String challengeOf(String verifier) => _base64Url(sha256.convert(utf8.encode(verifier)).bytes);

/// The page that asks *Connect this phone?*, after a sign-in if the person has none.
Uri signInUrl(String server, String challenge, String name) =>
  Uri.parse('$server/apps/relay/sign-in/phone').replace(queryParameters: {'challenge': challenge, 'name': name});
