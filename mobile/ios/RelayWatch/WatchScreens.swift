import SwiftUI

// The watch's screens: Tap to record, recording, Saved, Not saved and the microphone refused. The app records as it
// opens, so the first is seen only after the X. They mirror the phone's full-screen voice-note recording in lib/voice/.

struct WatchRoot: View {
  @ObservedObject var model: WatchModel

  var body: some View {
    Group {
      switch model.screen {
      case .idle: IdleScreen(model: model)
      case .recording: RecordingScreen(model: model)
      case .saved: SavedScreen(model: model)
      case .notSaved: NotSavedScreen(model: model)
      case .microphoneRefused: MicrophoneScreen()
      }
    }
    .foregroundColor(WatchBrand.ink)
  }
}

/// Small grey words, centered, such as how many notes wait.
struct SmallLine: View {
  let words: String

  var body: some View {
    Text(words).font(WatchBrand.small).foregroundColor(WatchBrand.muted).multilineTextAlignment(.center)
  }
}

/// A screen that is not recording: a tap anywhere records a new note.
private extension View {
  func tapRecords(_ model: WatchModel) -> some View {
    frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .onTapGesture(perform: model.talk)
  }
}

struct IdleScreen: View {
  @ObservedObject var model: WatchModel

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "mic.fill").font(.system(size: 30, weight: .semibold)).foregroundColor(WatchBrand.spark)
      Text("Tap to record").font(WatchBrand.title)
      if let words = waitingWords(model.waiting.count) { SmallLine(words: words) }
    }
    .tapRecords(model)
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
        SmallLine(words: "Tap to save")
        if let words = waitingWords(model.waiting.count) { SmallLine(words: words) }
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

/// After a save: whether the iPhone has the note yet, and how many others wait. It stays until a tap records again,
/// as watchOS lets no app close itself.
struct SavedScreen: View {
  @ObservedObject var model: WatchModel

  var body: some View {
    let words = WatchRules.iPhoneWords(saved: model.lastSaved, wait: model.waiting)
    VStack(spacing: 4) {
      Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundColor(WatchBrand.spark)
      Text("Saved").font(WatchBrand.title)
      SmallLine(words: words.iPhone)
      if let others = words.others { SmallLine(words: others) }
      Text("Tap for a new note").font(WatchBrand.smallest)
        .foregroundColor(WatchBrand.muted).padding(.top, 4)
    }
    .tapRecords(model)
  }
}

/// The recording could not be kept, such as on a full watch.
struct NotSavedScreen: View {
  @ObservedObject var model: WatchModel

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "exclamationmark.circle.fill").font(.system(size: 36)).foregroundColor(WatchBrand.muted)
      Text("Not saved").font(WatchBrand.title)
      SmallLine(words: "Tap to record again")
      if let words = waitingWords(model.waiting.count) { SmallLine(words: words) }
    }
    .tapRecords(model)
  }
}

/// The person refused the microphone: it stays until they allow it and come back to the app, which then asks again.
struct MicrophoneScreen: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "mic.slash.fill").font(.system(size: 28)).foregroundColor(WatchBrand.muted)
      Text("Allow the microphone in Settings › Privacy").font(WatchBrand.body).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
