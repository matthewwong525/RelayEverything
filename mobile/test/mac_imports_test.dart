import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'web_imports_test.dart' show walk;

/// Packages the Mac app must not reach: their plugins have no Mac code, so a call throws on the Mac, or, for
/// sherpa_onnx, they serve voice notes, which only the phone has.
const noMacCode = {'health', 'sherpa_onnx', 'device_calendar_plus', 'open_filex'};

/// The phone's sources of health, places, the background round and the speech model.
const phoneSources = {'lib/sync/health.dart', 'lib/sync/location.dart', 'lib/sync/background.dart',
  'lib/voice/transcriber.dart'};

/// The shared controller: the phone and the Mac both build it, and each entry passes in its own sources. The Mac passes
/// none, so the walk does not read it; its own test keeps it working with none.
const shared = {'lib/controller.dart'};

/// What [entry] reaches that the Mac must not, each with the file that names it.
Map<String, String> macBanned(String entry) {
  final (:packages, :files) = walk(entry, web: false, skip: shared);
  return {
    for (final MapEntry(key: name, value: from) in packages.entries)
      if (noMacCode.contains(name.split('/').first.replaceFirst('package:', ''))) name: from,
    for (final MapEntry(key: file, value: from) in files.entries)
      if (phoneSources.contains(file)) file: from,
  };
}

void main() {
  test('the Mac app reaches no package without Mac code and none of the phone-only sources', () {
    expect(macBanned('lib/main_mac.dart'), isEmpty, reason: 'Each one names the file that reaches it. Pass the source in '
      'from the phone entry, lib/main.dart, in place of an import.');
    final (:packages, :files) = walk('lib/main_mac.dart', web: false, skip: shared);
    expect(packages.keys, containsAll(['package:desktop_drop/desktop_drop.dart', 'package:url_launcher/url_launcher.dart']));
    expect(files.keys, containsAll(['lib/controller.dart', 'lib/mac/mac_app.dart', 'lib/web/shell.dart']));
  });

  test('the check finds a planted import, of a package or of a phone source', () {
    final folder = Directory.systemTemp.createTempSync('mac_imports');
    addTearDown(() => folder.deleteSync(recursive: true));
    final planted = File('${folder.path}/main_mac.dart')..writeAsStringSync('''
import 'package:relay_app/main_mac.dart';
import 'package:open_filex/open_filex.dart';
import 'package:relay_app/sync/health.dart';
''');
    final banned = macBanned(planted.path);
    expect(banned.keys, containsAll(['package:open_filex/open_filex.dart', 'lib/sync/health.dart']));
    expect(banned.keys, contains('package:health/health.dart'), reason: 'the walk reads on through sync/health.dart');
    expect(macBanned('lib/main.dart').keys, containsAll(['lib/sync/background.dart', 'package:open_filex/open_filex.dart']),
      reason: 'the phone entry reaches them itself');
  });
}
