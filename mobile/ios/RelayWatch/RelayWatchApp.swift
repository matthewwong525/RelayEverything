import SwiftUI

// The Relay Everything watch app: it records as it opens, and a tap or leaving the app saves. The watch face button
// opens relay-watch://record.

@main
struct RelayWatchApp: App {
  @ObservedObject private var model = WatchModel.shared
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      WatchRoot(model: model)
        .onOpenURL { url in
          if url.scheme == "relay-watch" && url.host == "record" { model.talk() }
        }
    }
    .onChange(of: scenePhase, initial: true) { _, phase in
      switch phase {
      case .active: model.phase(.active)
      case .background: model.phase(.background)
      default: model.phase(.inactive)
      }
    }
  }
}
