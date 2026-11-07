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
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      if let registrar = registry.registrar(forPlugin: "RelayChannels") { RelayChannels.register(registrar.messenger()) }
    }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "com.matthewwong525.relay.sync", earliestBeginInSeconds: 3600)
    // Health and places wake a closed app only if their observers start at each launch, before it returns.
    HealthWake.shared.apply()
    PlacesWake.shared.apply()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // relay/files keeps the speech model and recordings out of iCloud backup; relay/background is in RelayBackground.swift.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RelayChannels") {
      RelayChannels.register(registrar.messenger())
      BackgroundWake.shared.mainMessenger = registrar.messenger()
    }
  }
}
