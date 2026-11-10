import Foundation

// The voice notes that wait on the watch until the paired iPhone says it kept them. RelayWatchTests builds this file in.

/// The phone's rules for a voice note, so one rule holds on both: under a second keeps nothing, and 5 minutes stops.
enum RecordingRules {
  static let shortest: TimeInterval = 1
  static let longest: TimeInterval = 5 * 60

  /// True when a recording of [seconds] is kept.
  static func keeps(_ seconds: TimeInterval) -> Bool { seconds >= shortest }
}

/// One saved recording: its note id, the time it was saved and its length, as the iPhone reads them, and how far its
/// transfer got.
struct WatchNote: Codable, Equatable {
  /// Not sent yet, or its transfer failed: it goes at the next send. Sending: a transfer was started. Delivered: the
  /// transfer reached the iPhone. A sending or delivered note goes again only at launch, when no transfer is in flight.
  enum Transfer: String, Codable { case unsent, sending, delivered }

  let id: String
  let createdAt: Int
  let durationMs: Int
  var transfer: Transfer

  init(id: String, createdAt: Int, durationMs: Int, transfer: Transfer = .unsent) {
    self.id = id
    self.createdAt = createdAt
    self.durationMs = durationMs
    self.transfer = transfer
  }

  /// A queue saved with no transfer state reads as unsent.
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    createdAt = try values.decode(Int.self, forKey: .createdAt)
    durationMs = try values.decode(Int.self, forKey: .durationMs)
    transfer = try values.decodeIfPresent(Transfer.self, forKey: .transfer) ?? .unsent
  }

  /// The metadata the iPhone's RelayWatchReceiver.swift reads.
  var metadata: [String: Any] { ["id": id, "createdAt": createdAt, "durationMs": durationMs] }
}

/// The way to the iPhone: WatchLink.swift on the watch, a fake in the tests.
protocol WatchSender: AnyObject {
  /// The ids of notes whose transfer is still on its way.
  var sending: Set<String> { get }
  /// Starts a transfer, and gives false when it could not, such as before the session is ready.
  func send(_ file: URL, metadata: [String: Any]) -> Bool
}

/// The notes that wait, each `<id>.wav` beside `notes.json` in `watch-queue/`. A recording goes only after the iPhone's
/// kept. A note can go to the iPhone more than once: the iPhone remembers each id it took, keeps it once, and answers
/// kept again, so a note the person deleted there does not come back.
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

  /// After a saved note: sends each note that was never sent or whose transfer failed, and no note in flight.
  func sendWaiting(_ sender: WatchSender) { send(sender, all: false) }

  /// At launch and when the session is ready: sends each note with no transfer in flight, sending and delivered too,
  /// because a transfer the system dropped, or a kept lost with an old iPhone, tells the watch nothing.
  func sendAllWaiting(_ sender: WatchSender) { send(sender, all: true) }

  private func send(_ sender: WatchSender, all: Bool) {
    let busy = sender.sending
    var changed = false
    for index in notes.indices where (all || notes[index].transfer == .unsent) && !busy.contains(notes[index].id) {
      guard sender.send(file(notes[index]), metadata: notes[index].metadata) else { continue }
      notes[index].transfer = .sending
      changed = true
    }
    if changed { try? save() }
  }

  /// Note [id]'s transfer ended: with no [failed], it reached the iPhone and waits for kept; else it goes at the next
  /// saved note or launch. A note that is not here, such as one kept already, changes nothing.
  func finished(_ id: String, failed: Bool) {
    guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
    notes[index].transfer = failed ? .unsent : .delivered
    try? save()
  }

  private func save() throws {
    try JSONEncoder().encode(notes).write(to: folder.appendingPathComponent("notes.json"), options: .atomic)
  }
}
