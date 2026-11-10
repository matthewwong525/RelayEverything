import SwiftUI

// The Relay Everything watch app: tap, talk, tap to save. The watch face button opens relay-watch://record.

@main
struct RelayWatchApp: App {
  @ObservedObject private var model = WatchModel.shared

  var body: some Scene {
    WindowGroup {
      WatchRoot(model: model)
        .onOpenURL { url in
          if url.scheme == "relay-watch" && url.host == "record" { model.talk() }
        }
    }
  }
}
