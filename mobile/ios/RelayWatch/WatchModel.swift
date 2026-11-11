import Foundation
import WatchKit

// The watch app's one state: what shows, the recording, and the notes that wait for the iPhone. Main thread only.
// The rules that need no microphone are in WatchNotes.swift, where RelayWatchTests checks them.

final class WatchModel: ObservableObject {
  static let shared = WatchModel()

  /// The recording look from the first frame, before the microphone is on.
  @Published private(set) var screen = WatchRules.atOpen(allowed: WatchRecorder.allowed)
  /// The ids of the notes that wait for the iPhone, oldest first.
  @Published private(set) var waiting: [String] = []
  /// The id of the note saved last, so the Saved screen says whether the iPhone has it.
  @Published private(set) var lastSaved: String?
  @Published private(set) var started = Date()

  private let recorder = WatchRecorder()
  private let queue = WatchQueue.onWatch()
  private let link = WatchLink()
  private var phases = PhaseRule()

  private init() {
    waiting = queue.notes.map(\.id)
    recorder.onLongest = { [weak self] in self?.save() }
    link.onKept = { [weak self] id in
      guard let self else { return }
      self.queue.kept(id)
      self.waiting = self.queue.notes.map(\.id)
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

  /// The app opened, came back, or was left: it records, wakes the iPhone or saves by PhaseRule. After a leave the
  /// screen goes back to the recording look, so the next open shows no *Saved* first.
  func phase(_ phase: AppPhase) {
    switch phases.enter(phase) {
    case .record: talk()
    case .wake: if screen == .recording { link.wakeIfNear() }
    case .save:
      save()
      screen = WatchRules.afterLeave(screen)
    case .nothing: break
    }
  }

  /// Opening the app, a tap on a screen that is not recording, a watch face button or the Action button: asks for the
  /// microphone the first time only, then records. A call while it records changes nothing.
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
    guard screen != .recording else { return }
    do {
      try recorder.start()
      started = Date()
      screen = .recording
      // The iPhone app is awake when the save sends its file, even a save on leave, when the app is off screen.
      link.wakeIfNear()
    } catch {
      screen = .notSaved
    }
  }

  /// A tap anywhere while it records, leaving the app, or the longest time: keeps the note and hands it to the iPhone.
  func save() {
    guard screen == .recording else { return }
    let seconds = Date().timeIntervalSince(started)
    let note = recorder.stop().flatMap { try? queue.add($0.0, at: Date(), durationMs: $0.1) }
    screen = WatchRules.afterSave(kept: note != nil, seconds: seconds)
    guard let note else {
      if screen == .notSaved { WKInterfaceDevice.current().play(.failure) }
      return
    }
    lastSaved = note.id
    queue.sendWaiting(link)
    waiting = queue.notes.map(\.id)
    WKInterfaceDevice.current().play(.success)
  }

  /// The X: stops and keeps nothing.
  func cancel() {
    recorder.cancel()
    screen = WatchRules.afterCancel
  }
}
