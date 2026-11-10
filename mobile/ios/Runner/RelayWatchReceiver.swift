import Foundation
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

  func session(_ session: WCSession, didReceive file: WCSessionFile) {
    // The system deletes the file when this returns, so it moves now, on this thread. The watch sends a note again
    // until it gets kept, so an id taken before writes nothing and gets kept again.
    guard let id = try? ShortcutsInbox.takeWatchRecording(file.fileURL, metadata: file.metadata) else { return }
    session.transferUserInfo(["kept": id])
    DispatchQueue.main.async {
      if #available(iOS 16, *) { ShortcutsEngine.shared.inboxChanged() }
    }
  }
}
