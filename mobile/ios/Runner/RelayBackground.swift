import CoreLocation
import Flutter
import HealthKit
import UIKit

// The iPhone's background work while the app is closed. lib/sync/native.dart sets the flags on `relay/background`
// and drains the points; lib/sync/wake.dart runs one round when Health or a place wakes the app.

/// What Dart allows, kept so a relaunch in the background follows it with no Dart running.
enum RelayFlags {
  private static let defaults = UserDefaults.standard
  static var health: Bool { defaults.bool(forKey: "relay.health") }
  static var history: Bool { defaults.bool(forKey: "relay.history") }
  static var move: Bool { defaults.string(forKey: "relay.mode") == "move" }

  static func set(health: Bool, history: Bool, mode: String) {
    defaults.set(health, forKey: "relay.health")
    defaults.set(history, forKey: "relay.history")
    defaults.set(mode, forKey: "relay.mode")
  }
}

/// The points kept since the last drain, one JSON object a line, in Application Support and never in iCloud backup.
enum PointsFile {
  private static let queue = DispatchQueue(label: "relay.points")

  private static var url: URL? {
    guard let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("relay-points.jsonl")
  }

  static func add(_ location: CLLocation) {
    let point: [String: Any] = [
      "at": Int(location.timestamp.timeIntervalSince1970 * 1000), "lat": location.coordinate.latitude,
      "lon": location.coordinate.longitude, "accuracy": location.horizontalAccuracy,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: point), let line = String(data: data, encoding: .utf8) else { return }
    queue.sync {
      guard var url = url else { return }
      if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
      }
      guard let handle = try? FileHandle(forWritingTo: url) else { return }
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: Data((line + "\n").utf8))
    }
  }

  /// Every line, and an empty file after.
  static func drain() -> [String] {
    queue.sync {
      guard let url = url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
      try? FileManager.default.removeItem(at: url)
      return text.split(separator: "\n").map(String.init)
    }
  }

  static func clear() { queue.sync { if let url = url { try? FileManager.default.removeItem(at: url) } } }
}

/// Runs one Dart round for a wake. With the app open, the main engine runs it; closed, a headless engine does. One wake
/// at a time: a second waits for the first, and each stops waiting after 25 s. An iOS background task holds the app
/// awake for the round, and ends with it, at the cap, or when iOS ends the background time first.
final class BackgroundWake {
  static let shared = BackgroundWake()
  private var running: FlutterEngine?
  private var waiting: [() -> Void] = []
  private var timer: Timer?
  private var task = UIBackgroundTaskIdentifier.invalid
  /// Counts the rounds, so a late answer from a round that already ended can't end the next one.
  private var round = 0
  /// The app engine's messenger, once it runs: a wake runs there in place of a second engine.
  weak var mainMessenger: FlutterBinaryMessenger?

  func wake(done: @escaping () -> Void) {
    DispatchQueue.main.async { self.start(done) }
  }

  private func start(_ done: @escaping () -> Void) {
    waiting.append(done)
    if running != nil || timer != nil { return }
    round += 1
    let current = round
    task = UIApplication.shared.beginBackgroundTask(withName: "relay.wake") { [weak self] in self?.finish(current) }
    timer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in self?.finish(current) }
    guard let messenger = mainMessenger else { return headless(current) }
    // Before main.dart sets its handler the answer is not implemented, so a headless engine runs the round.
    FlutterMethodChannel(name: "relay/background", binaryMessenger: messenger).invokeMethod("wake", arguments: nil) { [weak self] answer in
      if (answer as? NSObject) === FlutterMethodNotImplemented { self?.headless(current) } else { self?.finish(current) }
    }
  }

  private func headless(_ current: Int) {
    guard current == round, timer != nil else { return }
    let engine = FlutterEngine(name: "relay.wake", project: nil, allowHeadlessExecution: true)
    running = engine
    engine.run(withEntrypoint: "wakeRound", libraryURI: "package:relay_app/sync/wake.dart")
    GeneratedPluginRegistrant.register(with: engine)
    RelayChannels.register(engine.binaryMessenger)
    FlutterMethodChannel(name: "relay/wake", binaryMessenger: engine.binaryMessenger).setMethodCallHandler { [weak self] call, result in
      result(nil)
      if call.method == "done" { self?.finish(current) }
    }
  }

  private func finish(_ current: Int) {
    guard current == round, timer != nil else { return }
    timer?.invalidate()
    timer = nil
    running?.destroyContext()
    running = nil
    let calls = waiting
    waiting = []
    calls.forEach { $0() }
    if task != .invalid {
      UIApplication.shared.endBackgroundTask(task)
      task = .invalid
    }
  }
}

/// Apple Health wakes the app for new readings, at most hourly. Each wake runs a round, which reads since the last.
final class HealthWake {
  static let shared = HealthWake()
  private let store = HKHealthStore()
  private var queries: [HKObserverQuery] = []

  private var types: [HKSampleType] {
    let quantities: [HKQuantityTypeIdentifier] = [.stepCount, .heartRate, .bodyMass, .restingHeartRate, .heartRateVariabilitySDNN,
      .oxygenSaturation, .bloodPressureSystolic, .bloodPressureDiastolic, .dietaryWater]
    let categories: [HKCategoryTypeIdentifier] = [.sleepAnalysis, .menstrualFlow, .mindfulSession]
    return quantities.compactMap { HKQuantityType.quantityType(forIdentifier: $0) }
      + categories.compactMap { HKCategoryType.categoryType(forIdentifier: $0) } + [HKObjectType.workoutType()]
  }

  func apply() {
    guard HKHealthStore.isHealthDataAvailable() else { return }
    queries.forEach { store.stop($0) }
    queries = []
    guard RelayFlags.health else {
      store.disableAllBackgroundDelivery { _, _ in }
      return
    }
    for type in types {
      let query = HKObserverQuery(sampleType: type, predicate: nil) { _, finished, error in
        guard error == nil, RelayFlags.health else { return finished() }
        BackgroundWake.shared.wake { finished() }
      }
      store.execute(query)
      queries.append(query)
      store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
    }
  }
}

/// Keeps points while the app is closed, after OwnTracks. Save battery: significant changes (about 500 m) and visits.
/// Every 100 m: best accuracy kept at 100 m or 5 minutes, plus significant changes, so iOS relaunches the app.
final class PlacesWake: NSObject, CLLocationManagerDelegate {
  static let shared = PlacesWake()
  private let manager = CLLocationManager()
  private var last: CLLocation?
  private var lastWake = Date.distantPast

  override init() {
    super.init()
    manager.delegate = self
  }

  func apply() {
    manager.stopUpdatingLocation()
    manager.stopMonitoringSignificantLocationChanges()
    manager.stopMonitoringVisits()
    guard RelayFlags.history, manager.authorizationStatus == .authorizedAlways else {
      if !RelayFlags.history { PointsFile.clear() }
      return
    }
    manager.allowsBackgroundLocationUpdates = true
    manager.pausesLocationUpdatesAutomatically = !RelayFlags.move
    manager.showsBackgroundLocationIndicator = false
    manager.startMonitoringSignificantLocationChanges()
    if RelayFlags.move {
      manager.desiredAccuracy = kCLLocationAccuracyBest
      manager.distanceFilter = kCLDistanceFilterNone
      manager.startUpdatingLocation()
    } else {
      manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
      manager.startMonitoringVisits()
      manager.requestLocation()
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { apply() }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard RelayFlags.history else { return }
    var kept = false
    for location in locations where location.horizontalAccuracy >= 0 && keeps(location) {
      PointsFile.add(location)
      last = location
      kept = true
    }
    if kept { wakeToSend() }
  }

  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    guard RelayFlags.history else { return }
    let at = visit.departureDate == .distantFuture ? visit.arrivalDate : visit.departureDate
    PointsFile.add(CLLocation(coordinate: visit.coordinate, altitude: 0, horizontalAccuracy: visit.horizontalAccuracy,
      verticalAccuracy: -1, timestamp: at))
    wakeToSend()
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

  /// Save battery runs a round for each significant change and each visit, as iOS gives few. Every 100 m runs one at
  /// most each 5 minutes, as its points come often. The open app also drains each minute.
  private func wakeToSend() {
    if RelayFlags.move {
      guard Date().timeIntervalSince(lastWake) >= 5 * 60 else { return }
      lastWake = Date()
    }
    BackgroundWake.shared.wake {}
  }

  /// Battery keeps each point iOS gives; Every 100 m keeps one at 100 m from the last, or 5 minutes after it.
  private func keeps(_ location: CLLocation) -> Bool {
    guard RelayFlags.move, let last = last else { return true }
    return location.distance(from: last) >= 100 || location.timestamp.timeIntervalSince(last.timestamp) >= 5 * 60
  }
}

/// The channels each engine gets: `relay/files` for backup, and `relay/background` for the flags and the points.
enum RelayChannels {
  static func register(_ messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "relay/files", binaryMessenger: messenger).setMethodCallHandler { call, result in
      // The App Group the share card (ios/ShareExtension/) shares: its folder, and whether the card may send.
      let group = "group.com.matthewwong525.relayApp"
      switch call.method {
      case "appGroupPath":
        return result(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.path)
      case "setShareSettings":
        let sending = (call.arguments as? [String: Any])?["sending"] as? Bool ?? false
        UserDefaults(suiteName: group)?.set(sending, forKey: "sending")
        return result(nil)
      default:
        break
      }
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
    FlutterMethodChannel(name: "relay/background", binaryMessenger: messenger).setMethodCallHandler { call, result in
      switch call.method {
      case "set":
        let flags = call.arguments as? [String: Any] ?? [:]
        RelayFlags.set(health: flags["health"] as? Bool ?? false, history: flags["history"] as? Bool ?? false,
          mode: flags["mode"] as? String ?? "battery")
        DispatchQueue.main.async {
          HealthWake.shared.apply()
          PlacesWake.shared.apply()
        }
        result(nil)
      case "drain":
        result(PointsFile.drain())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
