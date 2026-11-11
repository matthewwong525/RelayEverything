import Foundation
import XCTest

// A recording the Apple Watch hands over becomes the inbox note test/fixtures/watch-note.json, which the Dart test
// keeps as a voice note. Runner/ShortcutsInbox.swift is built into this target.
class ShortcutsInboxTests: XCTestCase {
  private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../test/fixtures/watch-note.json").standardized
  private let id = "5d41402abc4b2a76b9719d911017c592"
  private var root: URL!
  private var inbox: URL { root.appendingPathComponent("shortcuts-inbox", isDirectory: true) }

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  /// A file as WatchConnectivity gives it, in a folder of its own.
  private func received(_ bytes: [UInt8] = [82, 73, 70, 70]) throws -> URL {
    let file = root.appendingPathComponent("received.wav")
    try Data(bytes).write(to: file)
    return file
  }

  func testAWatchRecordingBecomesTheInboxNoteDartKeeps() throws {
    let file = try received()
    let kept = try ShortcutsInbox.keepWatchRecording(
      file, metadata: ["id": id, "createdAt": 1_793_790_000_000, "durationMs": 4200], in: inbox)
    XCTAssertEqual(kept, id)
    let written = try JSONSerialization.jsonObject(
      with: Data(contentsOf: inbox.appendingPathComponent("\(id).json"))) as? NSDictionary
    let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? NSDictionary
    XCTAssertEqual(written, expected)
    XCTAssertEqual(written?["from"] as? String, "watch")
    let wav = inbox.appendingPathComponent("\(id)/voice.wav")
    XCTAssertEqual(try Data(contentsOf: wav), Data([82, 73, 70, 70]))
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
  }

  func testAddANoteWritesTheSameShapeForAVoiceNoteWithNoWatchMark() throws {
    let request = ShortcutsInbox.request(id: id, text: "", createdAt: 1_793_790_000_000, files: [], durationMs: 4200)
    let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? NSDictionary
    let unmarked = expected?.mutableCopy() as? NSMutableDictionary
    unmarked?.removeObject(forKey: "from")
    XCTAssertEqual(request as NSDictionary, unmarked)
    XCTAssertEqual(ShortcutsInbox.request(id: id, text: "", createdAt: 1_793_790_000_000, files: [], durationMs: 4200,
      from: "watch") as NSDictionary, expected)
  }

  func testTheSameNoteHandedTwiceLeavesOneNote() throws {
    for bytes: [UInt8] in [[1], [2]] {
      _ = try ShortcutsInbox.keepWatchRecording(
        try received(bytes), metadata: ["id": id, "createdAt": 1_793_790_000_000, "durationMs": 4200], in: inbox)
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: inbox.path).sorted()
    XCTAssertEqual(names, [id, "\(id).json"])
    XCTAssertEqual(try Data(contentsOf: inbox.appendingPathComponent("\(id)/voice.wav")), Data([2]))
  }

  func testARepeatedIdWritesNothingAndStillAnswersKept() throws {
    let taken = WatchReceived(file: root.appendingPathComponent("watch-received.json"))
    let metadata: [String: Any] = ["id": id, "createdAt": 1_793_790_000_000, "durationMs": 4200]
    XCTAssertEqual(try ShortcutsInbox.takeWatchRecording(try received(), metadata: metadata, in: inbox,
      received: taken), id)
    XCTAssertEqual(taken.ids, [id])
    // The app kept the note and the person deleted it; the watch, with no kept, sends it again.
    try FileManager.default.removeItem(at: inbox)
    let again = try received([2])
    XCTAssertEqual(try ShortcutsInbox.takeWatchRecording(again, metadata: metadata, in: inbox, received: taken), id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: again.path))
    XCTAssertEqual(taken.ids, [id])
  }

  func testTheReceivedListKeepsOnlyTheLastIds() throws {
    let taken = WatchReceived(file: root.appendingPathComponent("watch-received.json"))
    let ids = (0...WatchReceived.limit).map { String(format: "%032lx", $0) }
    for one in ids { try taken.add(one) }
    XCTAssertEqual(taken.ids, Array(ids.dropFirst()))
    XCTAssertFalse(taken.contains(ids[0]))
    XCTAssertTrue(taken.contains(ids[WatchReceived.limit]))
  }

  func testABadIdOrNoLengthIsRefusedAndWritesNothing() throws {
    let file = try received()
    for metadata: [String: Any]? in [
      ["id": "../../Documents", "createdAt": 1, "durationMs": 1000],
      ["id": id.uppercased(), "createdAt": 1, "durationMs": 1000],
      ["id": id, "createdAt": 1],
      ["id": id, "durationMs": 1000],
      nil,
    ] {
      XCTAssertNil(try ShortcutsInbox.keepWatchRecording(file, metadata: metadata, in: inbox))
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
  }
}
