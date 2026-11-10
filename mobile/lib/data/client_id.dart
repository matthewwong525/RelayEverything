import 'dart:math';

/// A random id for a note or a file, so a resend is stored once. The phone and the browser both make them.
String newClientId([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(16, (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
