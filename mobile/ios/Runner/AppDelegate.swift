import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The hourly sync runs in its own engine, which needs the plugins too. Its name matches lib/sync/background.dart.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in GeneratedPluginRegistrant.register(with: registry) }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "com.matthewwong525.relay.sync", earliestBeginInSeconds: 3600)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Shortcuts' actions (RelayIntents.swift) call this engine while the app runs, so the open timeline shows a
    // shortcut's note at once. Before iOS 16 there are no actions.
    if #available(iOS 16, *), let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RelayShortcuts") {
      ShortcutsEngine.shared.attachApp(registrar.messenger())
    }
    // iCloud does not back up the speech model (57 MB, and it can be got again) or a recording (it never leaves the
    // phone). lib/voice/model.dart and lib/voice/recorder.dart call this.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RelayFiles") {
      let files = FlutterMethodChannel(name: "relay/files", binaryMessenger: registrar.messenger())
      files.setMethodCallHandler { call, result in
        guard call.method == "excludeFromBackup", let path = call.arguments as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
          result(nil)
        } catch {
          result(FlutterError(code: "backup", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
