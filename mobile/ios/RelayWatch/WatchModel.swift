import Foundation
import WatchKit

// The watch app's one state: what shows, the recording, and the notes that wait for the iPhone. Main thread only.

final class WatchModel: ObservableObject {
  enum Screen: Equatable { case main, recording, saved, microphoneRefused }

  static let shared = WatchModel()

  @Published private(set) var screen = Screen.main
  @Published private(set) var waiting = 0
  @Published private(set) var started = Date()

  private let recorder = WatchRecorder()
  private let queue = WatchQueue.onWatch()
  private let link = WatchLink()

  private init() {
    waiting = queue.notes.count
    recorder.onLongest = { [weak self] in self?.save() }
    link.onKept = { [weak self] id in
      self?.queue.kept(id)
      self?.waiting = self?.queue.notes.count ?? 0
    }
    // At each launch, a note whose transfer was lost goes again; one still on its way does not.
    link.onReady = { [weak self] in
      guard let self else { return }
      self.queue.sendWaiting(self.link)
    }
    link.activate()
  }

  /// The sound level for the bars, from 0 to 1.
  func level() -> Double { recorder.level() }

  /// Talk, a watch face button or the Action button: asks for the microphone on the first tap only, then records.
  func talk() {
    guard screen != .recording else { return }
    switch WatchRecorder.allowed {
    case true?: record()
    case false?: screen = .microphoneRefused
    case nil:
      WatchRecorder.ask { [weak self] granted in
        if granted { self?.record() } else { self?.screen = .microphoneRefused }
      }
    }
  }

  private func record() {
    do {
      try recorder.start()
      started = Date()
      screen = .recording
    } catch {
      screen = .main
    }
  }

  /// A tap anywhere while it records, or the longest time: keeps the note and hands it to the iPhone.
  func save() {
    guard screen == .recording else { return }
    guard let recording = recorder.stop(), let note = try? queue.add(recording.0, at: Date(), durationMs: recording.1)
    else {
      screen = .main
      return
    }
    link.send(queue.file(note), metadata: note.metadata)
    waiting = queue.notes.count
    WKInterfaceDevice.current().play(.success)
    screen = .saved
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      if self?.screen == .saved { self?.screen = .main }
    }
  }

  /// The X: stops and keeps nothing.
  func cancel() {
    recorder.cancel()
    screen = .main
  }

  func back() { screen = .main }
}
