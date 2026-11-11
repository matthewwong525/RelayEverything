import Foundation
import XCTest

// The watch's queue, length and screen rules, on a watch simulator. RelayWatch/WatchNotes.swift is built into this
// target.

/// The iPhone link as a fake: it remembers each send and wake, and a transfer stays on its way until [finish]. With
/// [ready] false it sends nothing, as before the session is ready; with [reachable] false the iPhone is away.
final class FakeSender: WatchSender {
  var sent: [String] = []
  var sending: Set<String> = []
  var ready = true
  var reachable = true
  var wakes = 0

  func wake() { wakes += 1 }

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

  func testASendWakesTheIPhoneOnlyWhenItIsNear() throws {
    let queue = WatchQueue(folder: folder)
    _ = try queue.add(try recording(), at: Date(), durationMs: 2000)
    let near = FakeSender()
    queue.sendWaiting(near)
    XCTAssertEqual(near.wakes, 1)
    // Nothing new to send: no wake.
    queue.sendWaiting(near)
    XCTAssertEqual(near.wakes, 1)
    let away = FakeSender()
    away.reachable = false
    _ = try queue.add(try recording(), at: Date(), durationMs: 2000)
    queue.sendWaiting(away)
    XCTAssertEqual([away.sent.count, away.wakes], [1, 0])
  }

  func testAtLaunchAWaitingNoteWakesTheIPhoneEvenWhenItIsInFlight() throws {
    let empty = FakeSender()
    WatchQueue(folder: folder).sendAllWaiting(empty)
    XCTAssertEqual(empty.wakes, 0)
    let note = try WatchQueue(folder: folder).add(try recording(), at: Date(), durationMs: 2000)
    let inFlight = FakeSender()
    inFlight.sending = [note.id]
    WatchQueue(folder: folder).sendAllWaiting(inFlight)
    XCTAssertEqual([inFlight.sent.count, inFlight.wakes], [0, 1])
  }

  func testTheScreenAfterASaveOrTheX() {
    XCTAssertEqual(WatchRules.afterSave(kept: true, seconds: 4), .saved)
    // A recording that could not be kept says so; a quick open and close is not an error.
    XCTAssertEqual(WatchRules.afterSave(kept: false, seconds: 4), .notSaved)
    XCTAssertEqual(WatchRules.afterSave(kept: false, seconds: 1), .notSaved)
    XCTAssertEqual(WatchRules.afterSave(kept: false, seconds: 0.4), .idle)
    XCTAssertEqual(WatchRules.afterCancel, .idle)
  }

  func testTheSavedScreenSaysWhetherTheIPhoneHasTheNote() {
    let sending = WatchRules.iPhoneWords(saved: "a", wait: ["b", "a"])
    XCTAssertEqual(sending.iPhone, "Sending to your iPhone")
    XCTAssertEqual(sending.others, "1 note waits for your iPhone")
    let kept = WatchRules.iPhoneWords(saved: "a", wait: ["b", "c"])
    XCTAssertEqual(kept.iPhone, "On your iPhone")
    XCTAssertEqual(kept.others, "2 notes wait for your iPhone")
    let alone = WatchRules.iPhoneWords(saved: "a", wait: [])
    XCTAssertEqual(alone.iPhone, "On your iPhone")
    XCTAssertNil(alone.others)
    XCTAssertNil(waitingWords(0))
  }

  func testTheAppRecordsAsItOpensAndSavesAsItIsLeft() {
    var rule = PhaseRule()
    // Launch: inactive, then active, records once.
    XCTAssertEqual(rule.enter(.inactive), .nothing)
    XCTAssertEqual(rule.enter(.active), .record)
    // The wrist down for a moment, and up again: it keeps recording.
    XCTAssertEqual(rule.enter(.inactive), .nothing)
    XCTAssertEqual(rule.enter(.active), .nothing)
    // The Digital Crown: it saves; coming back records a new note.
    XCTAssertEqual(rule.enter(.inactive), .nothing)
    XCTAssertEqual(rule.enter(.background), .save)
    XCTAssertEqual(rule.enter(.inactive), .nothing)
    XCTAssertEqual(rule.enter(.active), .record)
  }

  func testRecordingLengthRules() {
    XCTAssertFalse(RecordingRules.keeps(0.4))
    XCTAssertFalse(RecordingRules.keeps(0.999))
    XCTAssertTrue(RecordingRules.keeps(1))
    XCTAssertTrue(RecordingRules.keeps(42))
    XCTAssertEqual(RecordingRules.longest, 300)
  }
}
