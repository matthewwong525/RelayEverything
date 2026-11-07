import Foundation
import XCTest

// The share card's Swift copy of Dart: the note body against the fixture the Dart test reads too, and the six cases
// of test/share/draft_test.dart. ShareExtension/ShareNote.swift is built into this target.
class RunnerTests: XCTestCase {
  private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../test/fixtures/shared-note.json").standardized

  func testNoteBodyMatchesTheSharedFixture() throws {
    let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? NSDictionary
    let body = ShareNoteBody.body(
      clientId: "0f1e2d3c4b5a69788796a5b4c3d2e1f0",
      text: "read on the train\nTen rules for slow travel\nhttps://example.com/slow-travel",
      createdAt: 1_793_797_200_000,
      files: [
        ShareFile(id: "a1b2c3d4e5f60718293a4b5c6d7e8f90", name: "IMG_2041.jpg", type: "image/jpeg", size: 2_202_009, url: nil),
        ShareFile(id: "0918273645546372819aabbccddeeff0", name: "receipt.pdf", type: "application/pdf", size: 48_213, url: nil),
      ])
    let sent = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: body)) as? NSDictionary
    XCTAssertEqual(sent, expected)
  }

  private func file(_ name: String, _ size: Int = 1000) -> ShareFile {
    ShareFile(id: ShareRules.newId(), name: name, type: "", size: size, url: nil)
  }

  func testAWebPageBecomesTitleAndLinkAfterYourWords() {
    let draft = ShareDraft(subject: "Ten rules for slow travel", url: "https://example.com/slow-travel")
    XCTAssertEqual(draft.noteText(" read later "), "read later\nTen rules for slow travel\nhttps://example.com/slow-travel")
    // Android browsers share the address as the text, with the title as the subject.
    let android = ShareDraft(text: "https://example.com/slow-travel", subject: "Ten rules for slow travel")
    XCTAssertEqual(android.noteText(""), "Ten rules for slow travel\nhttps://example.com/slow-travel")
  }

  func testTextBecomesTheNoteText() {
    let draft = ShareDraft(text: "Buy oat milk")
    XCTAssertEqual(draft.noteText("from Sam"), "from Sam\nBuy oat milk")
    XCTAssertNil(draft.leftOut)
  }

  func testPhotosAndAFileBecomeFiles() {
    let draft = ShareDraft(files: [file("IMG_2041.jpg"), file("IMG_2042.jpg")])
    XCTAssertEqual(draft.files.map(\.name), ["IMG_2041.jpg", "IMG_2042.jpg"])
    XCTAssertEqual(draft.noteText("Paint colours for the hall"), "Paint colours for the hall")
    XCTAssertTrue(ShareDraft(files: [file("receipt.pdf")]).canSave(""))
  }

  func testTwelvePhotosKeepTheFirstTen() {
    let draft = ShareDraft(files: (1...12).map { file("IMG_\($0).jpg") })
    XCTAssertEqual(draft.files.count, 10)
    XCTAssertEqual(draft.files.last?.name, "IMG_10.jpg")
    XCTAssertEqual(draft.leftOut, "A note holds up to 10 files. 2 files were not added.")
  }

  func testAVideoOver25MBIsLeftOutAndSaveIsOff() {
    let draft = ShareDraft(files: [file("clip.mov", 40 * 1024 * 1024)])
    XCTAssertTrue(draft.files.isEmpty)
    XCTAssertEqual(draft.leftOut, "clip.mov is over 25 MB, so it was not added.")
    XCTAssertFalse(draft.canSave("  "))
    XCTAssertTrue(draft.canSave("the clip from the party"))
  }

  func testACommittedFileIsSentFromTheEntryFolderNotTheStagingFolder() {
    let root = URL(fileURLWithPath: "/inbox/share-inbox", isDirectory: true)
    let staging = root.appendingPathComponent(".tmp-abc", isDirectory: true)
    let entry = root.appendingPathComponent("abc", isDirectory: true)
    let copied = ShareFile(id: "f1", name: "IMG_2041.jpg", type: "image/jpeg", size: 10,
      url: staging.appendingPathComponent("1-IMG_2041.jpg"))
    let moved = copied.moved(to: entry)
    XCTAssertEqual(moved.url?.path, "/inbox/share-inbox/abc/1-IMG_2041.jpg")
    XCTAssertEqual(moved.id, copied.id)
    XCTAssertNil(file("clip.mov").moved(to: entry).url)
  }
}
