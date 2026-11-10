import SwiftUI
import WidgetKit

// The Relay Everything button for a watch face: one tap opens the watch app already recording. It shows no data, so
// its one entry never changes.

struct MicEntry: TimelineEntry {
  let date: Date
}

struct MicProvider: TimelineProvider {
  func placeholder(in context: Context) -> MicEntry { MicEntry(date: .now) }

  func getSnapshot(in context: Context, completion: @escaping (MicEntry) -> Void) { completion(MicEntry(date: .now)) }

  func getTimeline(in context: Context, completion: @escaping (Timeline<MicEntry>) -> Void) {
    completion(Timeline(entries: [MicEntry(date: .now)], policy: .never))
  }
}

struct MicButton: View {
  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      switch family {
      case .accessoryInline:
        Label("Talk", systemImage: "mic.fill")
      case .accessoryCorner:
        Image(systemName: "mic.fill").font(.system(size: 22, weight: .semibold))
          .widgetLabel("Talk")
      default:
        ZStack {
          AccessoryWidgetBackground()
          Image(systemName: "mic.fill").font(.system(size: 24, weight: .semibold))
        }
      }
    }
    .widgetURL(URL(string: "relay-watch://record"))
    .containerBackground(for: .widget) { Color.clear }
    .accessibilityLabel("Start a voice note")
  }
}

@main
struct RelayWatchWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "com.matthewwong525.relayApp.watch.talk", provider: MicProvider()) { _ in MicButton() }
      .configurationDisplayName("Relay Everything")
      .description("Start a voice note.")
      .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
  }
}
