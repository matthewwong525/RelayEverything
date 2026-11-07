import Foundation

/// One share's entry in the App Group's `share-inbox/`. The card copies files into `.tmp-<id>/`, then writes
/// `note.json` and renames the folder to `<id>/`, so the app never reads half a share. lib/share/inbox.dart drains it.
struct ShareInbox {
  let clientId: String
  let root: URL

  /// The inbox in the App Group, or nil when this build has no App Group.
  init?(clientId: String) {
    guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ShareRules.appGroup) else {
      return nil
    }
    self.init(clientId: clientId, root: group.appendingPathComponent(ShareRules.inboxFolder, isDirectory: true))
  }

  init(clientId: String, root: URL) {
    self.clientId = clientId
    self.root = root
  }

  var staging: URL { root.appendingPathComponent(".tmp-\(clientId)", isDirectory: true) }
  var entry: URL { root.appendingPathComponent(clientId, isDirectory: true) }

  /// Writes the note and puts the entry in place. From here the app keeps the note, even if the card is killed. Gives
  /// back the files at their new place in the entry: the copies in `.tmp-<id>/` are gone after the rename.
  func commit(text: String, createdAt: Int, files: [ShareFile]) throws -> [ShareFile] {
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    try write(to: staging, text: text, createdAt: createdAt, files: files, sentNote: false, sentFiles: [])
    try FileManager.default.moveItem(at: staging, to: entry)
    return files.map { $0.moved(to: entry) }
  }

  /// Notes what the card sent, so the app sends only the rest. The app may have taken the entry already: then nothing.
  func markSent(text: String, createdAt: Int, files: [ShareFile], sentNote: Bool, sentFiles: [String]) {
    guard FileManager.default.fileExists(atPath: entry.path) else { return }
    try? write(to: entry, text: text, createdAt: createdAt, files: files, sentNote: sentNote, sentFiles: sentFiles)
  }

  /// Cancel: the copies go, and nothing is kept.
  func discard() {
    try? FileManager.default.removeItem(at: staging)
  }

  private func write(to folder: URL, text: String, createdAt: Int, files: [ShareFile], sentNote: Bool,
    sentFiles: [String]) throws
  {
    let note: [String: Any] = [
      "v": 1, "clientId": clientId, "text": text, "createdAt": createdAt,
      "files": files.map { file -> [String: Any] in
        ["id": file.id, "name": file.name, "type": file.type, "size": file.size, "file": file.url?.lastPathComponent ?? ""]
      },
      "sentNote": sentNote, "sentFiles": sentFiles,
    ]
    let data = try JSONSerialization.data(withJSONObject: note)
    try data.write(to: folder.appendingPathComponent("note.json"), options: .atomic)
  }
}
