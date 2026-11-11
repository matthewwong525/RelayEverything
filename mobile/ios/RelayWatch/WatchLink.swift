import Foundation
import WatchConnectivity

// The watch's only way out: WatchConnectivity to the paired iPhone, which queues each file, survives a restart and
// sends when the phone is near. The iPhone answers `kept` with transferUserInfo (Runner/RelayWatchReceiver.swift), and
// a `wake` message starts the iPhone app when it is near.

final class WatchLink: NSObject, WCSessionDelegate, WatchSender {
  /// Runs on the main thread with the id of each note the iPhone kept.
  var onKept: (String) -> Void = { _ in }
  /// Runs on the main thread when a transfer ends, with its note id and true when it failed.
  var onFinished: (String, Bool) -> Void = { _, _ in }
  /// Runs on the main thread once the session is ready to send.
  var onReady: () -> Void = {}

  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  var sending: Set<String> {
    Set(WCSession.default.outstandingFileTransfers.compactMap { $0.file.metadata?["id"] as? String })
  }

  func send(_ file: URL, metadata: [String: Any]) -> Bool {
    guard WCSession.default.activationState == .activated else { return false }
    WCSession.default.transferFile(file, metadata: metadata)
    return true
  }

  var reachable: Bool { WCSession.default.activationState == .activated && WCSession.default.isReachable }

  /// A message from the watch starts the iPhone app in the background; its session then takes the waiting files at once.
  /// The message holds no note: the files go by transferFile, which keeps them until the iPhone has them.
  func wake() {
    WCSession.default.sendMessage(["wake": true], replyHandler: nil, errorHandler: nil)
  }

  func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
    guard state == .activated else { return }
    DispatchQueue.main.async { self.onReady() }
  }

  /// With no error the file reached the iPhone; the iPhone's kept may still be on its way.
  func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
    guard let id = fileTransfer.file.metadata?["id"] as? String else { return }
    let failed = error != nil
    DispatchQueue.main.async { self.onFinished(id, failed) }
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    guard let id = userInfo["kept"] as? String else { return }
    DispatchQueue.main.async { self.onKept(id) }
  }
}
