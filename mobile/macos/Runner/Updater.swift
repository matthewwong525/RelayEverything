import Cocoa
import FlutterMacOS
import Sparkle

/// Sparkle's updater, and the `relay/updates` channel that Dart calls: `check` (the person asked, with Sparkle's own
/// window), `checkInBackground` (a window only when a new version is ready), and `setTestBuilds`.
final class Updater: NSObject, SPUUpdaterDelegate {
  /// *Get test builds*, kept here so Sparkle reads it at launch, before Dart runs.
  static let testBuildsKey = "RelayTestBuilds"

  private var controller: SPUStandardUpdaterController!
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "relay/updates", binaryMessenger: messenger)
    super.init()
    controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  /// A release has no channel; a test build is `beta`, offered only while *Get test builds* is on.
  func allowedChannels(for updater: SPUUpdater) -> Set<String> {
    UserDefaults.standard.bool(forKey: Updater.testBuildsKey) ? ["beta"] : []
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "check":
      controller.checkForUpdates(nil)
    case "checkInBackground":
      controller.updater.checkForUpdatesInBackground()
    case "setTestBuilds":
      UserDefaults.standard.set(call.arguments as? Bool ?? false, forKey: Updater.testBuildsKey)
      // The next check reads the new channels, and the daily schedule starts again from now.
      controller.updater.resetUpdateCycle()
    default:
      return result(FlutterMethodNotImplemented)
    }
    result(nil)
  }
}
