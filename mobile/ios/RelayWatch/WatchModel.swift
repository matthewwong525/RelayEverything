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
    // A delivered note waits for kept. A failed one goes at the next saved note or launch, not at once: the system
    // already waits for the iPhone, so an error here comes again at once, and sending at once would loop.
    link.onFinished = { [weak self] id, failed in self?.queue.finished(id, failed: failed) }
    // At each launch, every note with no transfer in flight goes again. A second copy is harmless: the iPhone answers
    // kept for an id it took before and keeps nothing.
    link.onReady = { [weak self] in
      guard let self else { return }
      self.queue.sendAllWaiting(self.link)
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
    guard let recording = recorder.stop(), (try? queue.add(recording.0, at: Date(), durationMs: recording.1)) != nil
    else {
      screen = .main
      return
    }
    queue.sendWaiting(link)
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
