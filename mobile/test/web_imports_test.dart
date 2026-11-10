import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Packages that run only on a phone: a web build with one fails, or breaks when it runs. The key store builds for the
/// web, where the phone's Account page reaches it, and the browser never opens it.
const phoneOnly = {
  'whisper_cpp_flutter_plus', 'health', 'workmanager', 'photo_manager', 'device_calendar_plus', 'open_filex', 'geocoding',
  'geolocator', 'drift', 'drift_flutter', 'path_provider',
};

final _directive = RegExp(r'''^\s*(?:import|export)\s+'([^']+)'((?:\s+if\s*\([^)]*\)\s*'[^']+')*)''', multiLine: true);
final _branch = RegExp(r"if\s*\(\s*([\w.]+)\s*\)\s*'([^']+)'");

/// The library a browser build takes for one import: a conditional import's web branch when it has one.
String chosen(String plain, String conditions) {
  for (final match in _branch.allMatches(conditions)) {
    if (const {'dart.library.js_interop', 'dart.library.html', 'dart.library.js_util'}.contains(match[1])) return match[2]!;
  }
  return plain;
}

/// Every import and export [entry] reaches inside this app, with the file that names it.
Map<String, String> reached(String entry) {
  final seen = <String, String>{entry: '(entry)'};
  final names = <String, String>{};
  final queue = [entry];
  while (queue.isNotEmpty) {
    final file = queue.removeLast();
    for (final match in _directive.allMatches(File(file).readAsStringSync())) {
      final target = chosen(match[1]!, match[2] ?? '');
      final String? path;
      if (target.startsWith('package:relay_app/')) {
        path = 'lib/${target.substring('package:relay_app/'.length)}';
      } else if (target.startsWith('package:') || target.startsWith('dart:')) {
        names.putIfAbsent(target, () => file);
        path = null;
      } else {
        path = File(file).parent.uri.resolve(target).toFilePath();
      }
      if (path != null && !seen.containsKey(path)) {
        seen[path] = file;
        queue.add(path);
      }
    }
  }
  return names;
}

void main() {
  test('the web app reaches no dart:ffi and no phone-only package', () {
    final names = reached('lib/main_web.dart');
    final banned = {
      for (final MapEntry(key: name, value: from) in names.entries)
        if (name == 'dart:ffi' || phoneOnly.contains(name.split('/').first.replaceFirst('package:', ''))) name: from,
    };
    expect(banned, isEmpty, reason: 'Each import names the file that reaches it. Move the phone-only part behind the '
      'phone app, or give the web its own.');
    expect(names.keys, contains('package:flutter/material.dart'));
  });

  test('the check finds a phone-only package and takes the web branch of a conditional import', () {
    expect(phoneOnly.contains('package:health/health.dart'.split('/').first.replaceFirst('package:', '')), isTrue);
    expect(chosen('drops_none.dart', " if (dart.library.js_interop) 'drops_browser.dart'"), 'drops_browser.dart');
    expect(reached('lib/main.dart').keys, contains('package:health/health.dart'));
  });
}
