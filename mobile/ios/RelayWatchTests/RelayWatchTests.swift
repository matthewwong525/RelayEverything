import Foundation
import XCTest

// The watch's queue and length rules, on a watch simulator. RelayWatch/WatchNotes.swift is built into this target.

/// The iPhone link as a fake: it remembers each send, and a transfer stays on its way until [finish]. With [ready]
/// false it sends nothing, as before the session is ready.
final class FakeSender: WatchSender {
  var sent: [String] = []
  var sending: Set<String> = []
  var ready = true

  func send(_ file: URL, metadata: [String: Any]) -> Bool {
    guard ready else { return false }
    let id = metadata["id"] as! String
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    sent.append(id)
    sending.insert(id)
    return true
  }

  /// Each transfer on its way ends, as WatchLink's didFinish tells [queue].
  func finish(_ queue: WatchQueue, failed: Bool = false) {
    for id in sending { queue.finished(id, failed: failed) }
    sending = []
  }
}

class RelayWatchTests: XCTestCase {
  private var root: URL!
  private var folder: URL { root.appendingPathComponent("watch-queue", isDirectory: true) }

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  /// A recording as WatchRecorder leaves it, outside the queue.
  private func recording() throws -> URL {
    let scratch = root.appendingPathComponent("rec", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let file = scratch.appendingPathComponent("\(UUID().uuidString).wav")
    try Data([82, 73, 70, 70]).write(to: file)
    return file
  }

  func testANoteWaitsUntilTheIPhoneSaysKept() throws {
    let queue = WatchQueue(folder: folder)
    let at = Date(timeIntervalSince1970: 1_793_790_000)
    let note = try queue.add(try recording(), at: at, durationMs: 4200)
    XCTAssertEqual(note.createdAt, 1_793_790_000_000)
    XCTAssertTrue(note.id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil)
    XCTAssertEqual(note.transfer, .unsent)
    let sender = FakeSender()
    queue.sendWaiting(sender)
    sender.finish(queue)
    // A transfer that reached the iPhone is not a kept note: the recording stays until the answer.
    XCTAssertEqual(queue.notes.map(\.id), [note.id])
    XCTAssertEqual(queue.notes.map(\.transfer), [.delivered])
    XCTAssertTrue(FileManager.default.fileExists(atPath: queue.file(note).path))
    queue.kept(note.id)
    XCTAssertEqual(queue.notes, [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: queue.file(note).path))
    // A second kept for the same note changes nothing.
    queue.kept(note.id)
    XCTAssertEqual(queue.notes, [])
  }

  func testANoteOnItsWayIsNeverSentTwice() throws {
    let queue = WatchQueue(folder: folder)
    let first = try queue.add(try recording(), at: Date(), durationMs: 2000)
    let sender = FakeSender()
    queue.sendWaiting(sender)
    let second = try queue.add(try recording(), at: Date(), durationMs: 3000)
    queue.sendWaiting(sender)
    queue.sendAllWaiting(sender)
    XCTAssertEqual(sender.sent, [first.id, second.id])
  }

  func testTheQueueSurvivesAReloadAndANoteNeverSentGoesAtLaunch() throws {
    let note = try WatchQueue(folder: folder).add(try recording(), at: Date(), durationMs: 2000)
    let other = try WatchQueue(folder: folder).add(try recording(), at: Date(), durationMs: 5000)
    let reloaded = WatchQueue(folder: folder)
    XCTAssertEqual(reloaded.notes, [note, other])
    let sender = FakeSender()
    sender.sending = [other.id]
    reloaded.sendAllWaiting(sender)
    XCTAssertEqual(sender.sent, [note.id])
  }

  func testANoteSavedBeforeTheSessionIsReadyGoesWhenItIs() throws {
    let queue = WatchQueue(folder: folder)
    let note = try queue.add(try recording(), at: Date(), durationMs: 2000)
    let sender = FakeSender()
    sender.ready = false
    queue.sendWaiting(sender)
    XCTAssertEqual(WatchQueue(folder: folder).notes.map(\.transfer), [.unsent])
    sender.ready = true
    queue.sendWaiting(sender)
    XCTAssertEqual(sender.sent, [note.id])
  }

  func testADeliveredNoteGoesOnlyAtLaunchUntilKept() throws {
    // The iPhone has the note, but its kept has not come: a saved note sends nothing more, and the next launch sends
    // it again, which the iPhone answers with kept and no second note.
    let queue = WatchQueue(folder: folder)
    let note = try queue.add(try recording(), at: Date(), durationMs: 2000)
    let sender = FakeSender()
    queue.sendWaiting(sender)
    sender.finish(queue)
    queue.sendWaiting(sender)
    XCTAssertEqual(sender.sent, [note.id])
    let reloaded = WatchQueue(folder: folder)
    XCTAssertEqual(reloaded.notes.map(\.transfer), [.delivered])
    let atLaunch = FakeSender()
    reloaded.sendAllWaiting(atLaunch)
    XCTAssertEqual(atLaunch.sent, [note.id])
    // The kept that comes late still deletes the recording.
    reloaded.kept(note.id)
    XCTAssertEqual(WatchQueue(folder: folder).notes, [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: reloaded.file(note).path))
  }

  func testANoteOnItsWayButNotInFlightAtAReloadIsSentAgain() throws {
    let queue = WatchQueue(folder: folder)
    let note = try queue.add(try recording(), at: Date(), durationMs: 2000)
    queue.sendWaiting(FakeSender())
    XCTAssertEqual(queue.notes.map(\.transfer), [.sending])
    // The system dropped the transfer and no didFinish came, as when the person moves to a new iPhone.
    let atLaunch = FakeSender()
    WatchQueue(folder: folder).sendAllWaiting(atLaunch)
    XCTAssertEqual(atLaunch.sent, [note.id])
    // A transfer the system still has in flight does not go twice.
    let inFlight = FakeSender()
    inFlight.sending = [note.id]
    WatchQueue(folder: folder).sendAllWaiting(inFlight)
    XCTAssertEqual(inFlight.sent, [])
  }

  func testAFailedTransferGoesAgain() throws {
    let queue = WatchQueue(folder: folder)
    let note = try queue.add(try recording(), at: Date(), durationMs: 2000)
    let sender = FakeSender()
    queue.sendWaiting(sender)
    sender.finish(queue, failed: true)
    let reloaded = WatchQueue(folder: folder)
    XCTAssertEqual(reloaded.notes.map(\.transfer), [.unsent])
    let atLaunch = FakeSender()
    reloaded.sendWaiting(atLaunch)
    XCTAssertEqual(atLaunch.sent, [note.id])
    XCTAssertEqual(reloaded.notes.map(\.transfer), [.sending])
    // A kept for a note whose transfer then ends changes nothing.
    reloaded.kept(note.id)
    reloaded.finished(note.id, failed: false)
    XCTAssertEqual(reloaded.notes, [])
  }

  func testAQueueSavedWithNoTransferStateReadsAsUnsent() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let id = String(repeating: "b", count: 32)
    try Data(#"[{"id":"\#(id)","createdAt":1793790000000,"durationMs":4200}]"#.utf8)
      .write(to: folder.appendingPathComponent("notes.json"))
    XCTAssertEqual(WatchQueue(folder: folder).notes,
      [WatchNote(id: id, createdAt: 1_793_790_000_000, durationMs: 4200, transfer: .unsent)])
  }

  func testMetadataIsWhatTheIPhoneReads() throws {
    let note = WatchNote(id: String(repeating: "a", count: 32), createdAt: 1_793_790_000_000, durationMs: 4200)
    XCTAssertEqual(note.metadata as NSDictionary,
      ["id": String(repeating: "a", count: 32), "createdAt": 1_793_790_000_000, "durationMs": 4200] as NSDictionary)
  }

  func testRecordingLengthRules() {
    XCTAssertFalse(RecordingRules.keeps(0.4))
    XCTAssertFalse(RecordingRules.keeps(0.999))
    XCTAssertTrue(RecordingRules.keeps(1))
    XCTAssertTrue(RecordingRules.keeps(42))
    XCTAssertEqual(RecordingRules.longest, 300)
  }
}
