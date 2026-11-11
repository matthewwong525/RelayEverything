import Foundation
import UIKit
import WatchConnectivity

// Takes each voice note the Relay Everything Apple Watch app hands over, into the inbox Dart keeps notes from, and
// answers `kept` so the watch deletes its copy. Nothing here uses a network: the watch talks only to this phone.

final class RelayWatchReceiver: NSObject, WCSessionDelegate {
  static let shared = RelayWatchReceiver()

  /// AppDelegate calls this at each launch, before Flutter starts, so a background wake for a file gets it.
  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

  func sessionDidBecomeInactive(_ session: WCSession) {}

  /// The person paired another watch: the session starts again for it.
  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  /// The watch's wake: it only starts this app, so the session takes the waiting files at once. It needs no answer.
  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {}

  func session(_ session: WCSession, didReceive file: WCSessionFile) {
    // The system deletes the file when this returns, so it moves now, on this thread. The watch sends a note again
    // until it gets kept, so an id taken before writes nothing and gets kept again.
    guard let id = try? ShortcutsInbox.takeWatchRecording(file.fileURL, metadata: file.metadata) else { return }
    session.transferUserInfo(["kept": id])
    DispatchQueue.main.async {
      guard #available(iOS 16, *) else { return }
      // The phone may be locked, with the app out of sight: ask iOS for time to write the words and send the note.
      let end = Self.backgroundTime(named: "relay.watch-note")
      ShortcutsEngine.shared.inboxChanged(done: end)
    }
  }

  /// Asks iOS for time to finish work while the app is not on the screen, about 30 seconds. It gives the call that
  /// ends the time: the first call ends it, and later calls, or a call after iOS took the time back, do nothing. Runs
  /// on the main thread, as the end call and iOS's expiry handler do.
  static func backgroundTime(named name: String) -> () -> Void {
    var task = UIBackgroundTaskIdentifier.invalid
    let end = {
      guard task != .invalid else { return }
      let ending = task
      task = .invalid
      UIApplication.shared.endBackgroundTask(ending)
    }
    task = UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: end)
    return end
  }
}
