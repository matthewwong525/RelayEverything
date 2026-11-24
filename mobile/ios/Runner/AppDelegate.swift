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
    // A voice note from the Apple Watch can wake a closed app too (RelayWatchReceiver.swift).
    RelayWatchReceiver.shared.activate()
    // The note's web view: no arrow bar over the keyboard, and the keyboard comes up for a new note (RelayWebKeyboard.swift).
    RelayWebKeyboard.apply()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Shortcuts' actions (RelayIntents.swift) call this engine while the app runs, so the open timeline shows a
    // shortcut's note at once. Before iOS 16 there are no actions.
    if #available(iOS 16, *), let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RelayShortcuts") {
      ShortcutsEngine.shared.attachApp(registrar.messenger())
    }
    // relay/files keeps the speech model and recordings out of iCloud backup; relay/background is in RelayBackground.swift.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RelayChannels") {
      RelayChannels.register(registrar.messenger())
      BackgroundWake.shared.mainMessenger = registrar.messenger()
    }
    // A shake after a delete asks to undo it (SceneDelegate.swift).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RelayShake") {
      RelayShake.register(registrar.messenger())
    }
  }

  /// A shake with no view to take it comes here, at the end of the responder chain.
  override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    if motion == .motionShake { RelayShake.shaken(event) }
    super.motionEnded(motion, with: event)
  }
}
