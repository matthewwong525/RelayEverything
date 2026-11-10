import Foundation

// The voice notes that wait on the watch until the paired iPhone says it kept them. RelayWatchTests builds this file in.

/// The phone's rules for a voice note, so one rule holds on both: under a second keeps nothing, and 5 minutes stops.
enum RecordingRules {
  static let shortest: TimeInterval = 1
  static let longest: TimeInterval = 5 * 60

  /// True when a recording of [seconds] is kept.
  static func keeps(_ seconds: TimeInterval) -> Bool { seconds >= shortest }
}

/// One saved recording: its note id, the time it was saved and its length, as the iPhone reads them.
struct WatchNote: Codable, Equatable {
  let id: String
  let createdAt: Int
  let durationMs: Int

  /// The metadata the iPhone's RelayWatchReceiver.swift reads.
  var metadata: [String: Any] { ["id": id, "createdAt": createdAt, "durationMs": durationMs] }
}

/// The way to the iPhone: WatchLink.swift on the watch, a fake in the tests.
protocol WatchSender: AnyObject {
  /// The ids of notes whose transfer is still on its way.
  var sending: Set<String> { get }
  func send(_ file: URL, metadata: [String: Any])
}

/// The notes that wait, each `<id>.wav` beside `notes.json` in `watch-queue/`. A note goes only after the iPhone's kept.
final class WatchQueue {
  private let folder: URL
  private(set) var notes: [WatchNote]

  init(folder: URL) {
    self.folder = folder
    let saved = try? Data(contentsOf: folder.appendingPathComponent("notes.json"))
    notes = saved.flatMap { try? JSONDecoder().decode([WatchNote].self, from: $0) } ?? []
  }

  /// The queue in the watch app's own support folder.
  static func onWatch() -> WatchQueue {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return WatchQueue(folder: support.appendingPathComponent("watch-queue", isDirectory: true))
  }

  func file(_ note: WatchNote) -> URL { folder.appendingPathComponent("\(note.id).wav") }

  /// Keeps [recording] as a new note, saved at [at], and gives it back.
  func add(_ recording: URL, at: Date, durationMs: Int) throws -> WatchNote {
    let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let note = WatchNote(id: id, createdAt: Int(at.timeIntervalSince1970 * 1000), durationMs: durationMs)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: recording, to: file(note))
    notes.append(note)
    try save()
    return note
  }

  /// The iPhone kept note [id]: its recording goes. An id that is not here, such as a second answer, changes nothing.
  func kept(_ id: String) {
    guard let note = notes.first(where: { $0.id == id }) else { return }
    try? FileManager.default.removeItem(at: file(note))
    notes.removeAll { $0.id == id }
    try? save()
  }

  /// Sends each waiting note that has no transfer on its way, so none goes twice at once.
  func sendWaiting(_ sender: WatchSender) {
    let busy = sender.sending
    for note in notes where !busy.contains(note.id) {
      sender.send(file(note), metadata: note.metadata)
    }
  }

  private func save() throws {
    try JSONEncoder().encode(notes).write(to: folder.appendingPathComponent("notes.json"), options: .atomic)
  }
}
