import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

}

/// The app's one Flutter view (Main.storyboard): it tells the app of a shake, so a shake after a delete asks *Undo Delete
/// Note* (lib/screens/recently_deleted.dart). The shake still goes on up, so the system's own shake undo of typing works.
class RelayViewController: FlutterViewController {
  override var canBecomeFirstResponder: Bool { true }

  /// With no text field open, the view takes the shake itself.
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !isFirstResponder { becomeFirstResponder() }
  }

  override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    if motion == .motionShake { RelayShake.shaken(event) }
    super.motionEnded(motion, with: event)
  }
}

/// Sends each shake to the app once on `relay/shake`. A shake can come to the view and to the app delegate both, by
/// the responder chain: the second of the same event sends nothing.
enum RelayShake {
  private static var channel: FlutterMethodChannel?
  private static var last: TimeInterval = -1

  static func register(_ messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "relay/shake", binaryMessenger: messenger)
  }

  static func shaken(_ event: UIEvent?) {
    let at = event?.timestamp ?? ProcessInfo.processInfo.systemUptime
    if let event = event, event.timestamp == last { return }
    last = at
    channel?.invokeMethod("shake", arguments: nil)
  }
}
