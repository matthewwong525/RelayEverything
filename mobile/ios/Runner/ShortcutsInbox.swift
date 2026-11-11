import Foundation

// The inbox lib/shortcuts/inbox.dart keeps notes from: `<id>.json` and the folder `<id>/`. Shortcuts' Add a note and
// the Apple Watch (RelayWatchReceiver.swift) both write it here, so the note's shape has one writer.

/// The app's support folder, the same one Dart's getApplicationSupportDirectory gives.
enum RelayFolders {
  static var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
  static var inbox: URL { support.appendingPathComponent("shortcuts-inbox", isDirectory: true) }
  /// The ids of the last watch notes this phone took, so a note the watch sends again is not kept twice.
  static var watchReceived: URL { support.appendingPathComponent("watch-received.json") }

  /// A path from Dart, full or from the support folder, as a file URL.
  static func url(_ path: String) -> URL {
    path.hasPrefix("/") ? URL(fileURLWithPath: path) : support.appendingPathComponent(path)
  }
}

enum ShortcutsInbox {
  /// A note id Dart keeps: 32 lowercase hex characters. Only such an id becomes a folder name.
  static func isNoteId(_ id: String) -> Bool {
    id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil
  }

  /// The folder that holds note [id]'s files.
  static func folder(_ id: String, in inbox: URL = RelayFolders.inbox) -> URL {
    inbox.appendingPathComponent(id, isDirectory: true)
  }

  /// A note as Dart's `add` and `drainInbox` read it, made at [createdAt] milliseconds. A [durationMs] makes it a voice
  /// note from `<id>/voice.wav`. A [from] of `watch` marks a note the Apple Watch handed over: the app never deletes it
  /// for having no words.
  static func request(id: String, text: String, createdAt: Int, files: [[String: Any]], durationMs: Int?,
    from: String? = nil) -> [String: Any]
  {
    var request: [String: Any] = ["id": id, "text": text, "createdAt": createdAt, "files": files]
    if let from { request["from"] = from }
    if let durationMs {
      request["recording"] = ["path": "shortcuts-inbox/\(id)/voice.wav", "durationMs": durationMs] as [String: Any]
    }
    return request
  }

  /// Leaves [request] for the app to keep the next time it drains the inbox.
  static func leave(_ request: [String: Any], id: String, in inbox: URL = RelayFolders.inbox) throws {
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: request)
    try data.write(to: inbox.appendingPathComponent("\(id).json"), options: .atomic)
  }

  /// Moves a recording the watch handed over, a 16 kHz mono WAV, into the inbox as a voice note, and gives its id.
  /// Metadata with no note id, time or length is refused with nil, and the file is left where it is.
  static func keepWatchRecording(_ file: URL, metadata: [String: Any]?, in inbox: URL = RelayFolders.inbox) throws
    -> String?
  {
    guard let id = metadata?["id"] as? String, isNoteId(id),
      let createdAt = (metadata?["createdAt"] as? NSNumber)?.intValue,
      let durationMs = (metadata?["durationMs"] as? NSNumber)?.intValue, durationMs > 0
    else { return nil }
    let noteFolder = Self.folder(id, in: inbox)
    try FileManager.default.createDirectory(at: noteFolder, withIntermediateDirectories: true)
    var target = noteFolder.appendingPathComponent("voice.wav")
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.moveItem(at: file, to: target)
    // As the app's own recordings: phone backups leave voice out.
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? target.setResourceValues(values)
    try leave(request(id: id, text: "", createdAt: createdAt, files: [], durationMs: durationMs, from: "watch"), id: id,
      in: inbox)
    return id
  }

  /// Takes a recording the watch handed over and gives the id to answer kept for. An id in [received] was taken
  /// before: it writes nothing, so a note the person deleted does not come back, and the watch still gets its kept.
  /// A new id goes into the inbox, then into [received], before the caller answers kept.
  static func takeWatchRecording(
    _ file: URL, metadata: [String: Any]?, in inbox: URL = RelayFolders.inbox,
    received: WatchReceived = WatchReceived()
  ) throws -> String? {
    guard let id = metadata?["id"] as? String, isNoteId(id) else { return nil }
    if received.contains(id) { return id }
    guard let kept = try keepWatchRecording(file, metadata: metadata, in: inbox) else { return nil }
    try received.add(kept)
    return kept
  }
}

/// The ids of the last [limit] watch notes the phone took, oldest first, in one small JSON file. A watch note waits
/// for its kept for at most as long as the person makes [limit] more notes, so an older id is not needed.
struct WatchReceived {
  static let limit = 500

  let file: URL

  init(file: URL = RelayFolders.watchReceived) { self.file = file }

  var ids: [String] {
    guard let data = try? Data(contentsOf: file) else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
  }

  func contains(_ id: String) -> Bool { ids.contains(id) }

  /// Keeps [id] as taken, and lets the oldest go past [limit].
  func add(_ id: String) throws {
    var all = ids.filter { $0 != id }
    all.append(id)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(Array(all.suffix(Self.limit))).write(to: file, options: .atomic)
  }
}
