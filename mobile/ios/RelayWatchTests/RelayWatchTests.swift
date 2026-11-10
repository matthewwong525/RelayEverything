import Foundation
import XCTest

// The watch's queue and length rules, on a watch simulator. RelayWatch/WatchNotes.swift is built into this target.

/// The iPhone link as a fake: it remembers each send, and a transfer stays on its way until [finish].
final class FakeSender: WatchSender {
  var sent: [String] = []
  var sending: Set<String> = []

  func send(_ file: URL, metadata: [String: Any]) {
    let id = metadata["id"] as! String
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    sent.append(id)
    sending.insert(id)
  }

  func finish() { sending = [] }
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
    let sender = FakeSender()
    queue.sendWaiting(sender)
    sender.finish()
    // A transfer that finished is not a kept note: the recording stays until the answer.
    XCTAssertEqual(queue.notes, [note])
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
    queue.sendWaiting(sender)
    XCTAssertEqual(sender.sent, [first.id, second.id])
  }

  func testTheQueueSurvivesAReloadAndALostTransferGoesAgain() throws {
    let note = try WatchQueue(folder: folder).add(try recording(), at: Date(), durationMs: 2000)
    let other = try WatchQueue(folder: folder).add(try recording(), at: Date(), durationMs: 5000)
    let reloaded = WatchQueue(folder: folder)
    XCTAssertEqual(reloaded.notes, [note, other])
    let sender = FakeSender()
    sender.sending = [other.id]
    reloaded.sendWaiting(sender)
    XCTAssertEqual(sender.sent, [note.id])
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
