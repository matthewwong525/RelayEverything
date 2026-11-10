import SwiftUI

// The watch's four screens: Talk, recording, Saved and the microphone refused. They mirror the phone's full-screen
// voice-note recording in lib/voice/.

struct WatchRoot: View {
  @ObservedObject var model: WatchModel

  var body: some View {
    Group {
      switch model.screen {
      case .main: MainScreen(model: model)
      case .recording: RecordingScreen(model: model)
      case .saved: SavedScreen()
      case .microphoneRefused: MicrophoneScreen(model: model)
      }
    }
    .foregroundColor(WatchBrand.ink)
  }
}

/// The words for the notes that wait: nil when none does.
func waitingWords(_ count: Int) -> String? {
  switch count {
  case 0: return nil
  case 1: return "1 note waits for your iPhone"
  default: return "\(count) notes wait for your iPhone"
  }
}

struct MainScreen: View {
  @ObservedObject var model: WatchModel

  var body: some View {
    VStack(spacing: 8) {
      Button(action: model.talk) {
        VStack(spacing: 2) {
          Image(systemName: "mic.fill").font(.system(size: 30, weight: .semibold))
          Text("Talk").font(WatchBrand.title)
        }
        .foregroundColor(WatchBrand.onSpark)
        .frame(width: 104, height: 104)
        .background(WatchBrand.spark, in: Circle())
      }
      .buttonStyle(.plain)
      if let words = waitingWords(model.waiting) {
        Text(words).font(WatchBrand.small).foregroundColor(WatchBrand.muted).multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct RecordingScreen: View {
  @ObservedObject var model: WatchModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.1)) { context in
      VStack(spacing: 8) {
        HStack {
          Text(clock(context.date.timeIntervalSince(model.started))).font(WatchBrand.title).monospacedDigit()
          Spacer()
          Button(action: model.cancel) {
            Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
              .frame(width: 32, height: 32)
              .background(WatchBrand.card, in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Cancel")
        }
        Spacer()
        SoundBars(level: model.level())
        Spacer()
        Text("Tap to save").font(WatchBrand.small).foregroundColor(WatchBrand.muted)
      }
    }
    .padding(.horizontal, 4)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // The whole screen saves; the X above takes its own tap first.
    .contentShape(Rectangle())
    .onTapGesture(perform: model.save)
  }

  private func clock(_ seconds: TimeInterval) -> String {
    let whole = max(0, Int(seconds))
    return String(format: "%d:%02d", whole / 60, whole % 60)
  }
}

/// Bars that follow the voice: each a share of the level now, highest in the middle.
struct SoundBars: View {
  let level: Double
  private let shape: [Double] = [0.35, 0.6, 0.85, 1, 0.85, 0.6, 0.35]

  var body: some View {
    HStack(spacing: 5) {
      ForEach(shape.indices, id: \.self) { index in
        Capsule()
          .fill(WatchBrand.spark)
          .frame(width: 7, height: max(7, 56 * level * shape[index]))
      }
    }
    .frame(height: 56)
    .animation(.easeOut(duration: 0.1), value: level)
    .accessibilityHidden(true)
  }
}

struct SavedScreen: View {
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundColor(WatchBrand.spark)
      Text("Saved").font(WatchBrand.title)
      Text("Sending to your iPhone").font(WatchBrand.small).foregroundColor(WatchBrand.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct MicrophoneScreen: View {
  @ObservedObject var model: WatchModel

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "mic.slash.fill").font(.system(size: 28)).foregroundColor(WatchBrand.muted)
      Text("Allow the microphone in Settings › Privacy").font(WatchBrand.body).multilineTextAlignment(.center)
      Button("OK", action: model.back)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
