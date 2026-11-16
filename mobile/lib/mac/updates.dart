import 'package:flutter/services.dart';

/// The Mac app's updates, through Sparkle in `macos/Runner/Updater.swift`: each call opens Sparkle's own window when
/// there is something to show.
class MacUpdates {
  const MacUpdates([this._channel = const MethodChannel('relay/updates')]);

  final MethodChannel _channel;

  /// *Check for Updates…*: Sparkle's window shows the new version, or says this one is the newest.
  Future<void> check() => _channel.invokeMethod<void>('check');

  /// When the app opens: a window only when a new version is ready; no network is no window.
  Future<void> checkInBackground() => _channel.invokeMethod<void>('checkInBackground');

  /// *Get test builds*: Sparkle also offers test builds while it is on. It never offers a version older than this one.
  Future<void> setTestBuilds(bool on) => _channel.invokeMethod<void>('setTestBuilds', on);
}
