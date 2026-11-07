import Foundation

// The share card's rules and the note body it sends, with no UI, so RunnerTests checks them too. They copy Dart:
// lib/share/draft.dart and lib/data/attachments.dart for the rules, LocalNote.toJson for the body.

enum ShareRules {
  /// The App Group the app and the card share: the inbox folder, the sending setting, and the key's Keychain group.
  static let appGroup = "group.com.matthewwong525.relayApp"
  /// The service name of the key's items, as KeyVault.sharedService in lib/data/connection.dart.
  static let keychainService = "relay.shared"
  static let inboxFolder = "share-inbox"
  static let maxFiles = 10
  static let maxFileBytes = 25 * 1024 * 1024

  /// A note or file id the server takes: 32 lowercase hex characters, as the app makes them.
  static func newId() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
  }
}

/// One shared file. [url] is the card's copy in the inbox, or nil for a file over 25 MB, which is never copied.
struct ShareFile: Equatable {
  var id: String
  var name: String
  var type: String
  var size: Int
  var url: URL?

  /// The same file once its folder is renamed: the copy keeps its name, now in [folder]. A file never copied stays nil.
  func moved(to folder: URL) -> ShareFile {
    var file = self
    file.url = url.map { folder.appendingPathComponent($0.lastPathComponent) }
    return file
  }
}

/// What the other app shared, as the card shows it: the same rules as lib/share/draft.dart.
struct ShareDraft {
  let text: String?
  let title: String?
  let url: String?
  let files: [ShareFile]
  /// The files left out, past the tenth or over 25 MB, in the app's own words.
  let leftOut: String?
  /// Every file given, kept or not, so Cancel and Save can delete the copies the note does not keep.
  let given: [ShareFile]

  init(text: String? = nil, subject: String? = nil, url: String? = nil, files: [ShareFile] = []) {
    var body = Self.clean(text)
    var link = Self.clean(url)
    if link == nil, let shared = body, shared.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil {
      link = shared
      body = nil
    }
    // A link the text already holds is not written a second time.
    if let shared = body, let address = link, shared.contains(address) { link = nil }
    let title = link == nil ? nil : Self.clean(subject)
    let check = Self.checkFiles(files)
    self.text = body
    self.title = title == link ? nil : title
    self.url = link
    self.files = check.kept
    self.leftOut = check.problem
    self.given = files
  }

  var hasItems: Bool { text != nil || url != nil || !files.isEmpty }

  func canSave(_ words: String) -> Bool { Self.clean(words) != nil || hasItems }

  /// The person's words, then the shared text, then the link as its title and address, one per line.
  func noteText(_ words: String) -> String {
    [Self.clean(words), text, title, url].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  static func clean(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
  }

  /// checkFiles in lib/data/attachments.dart: the same order and the same words.
  static func checkFiles(_ picked: [ShareFile]) -> (kept: [ShareFile], problem: String?) {
    var kept: [ShareFile] = []
    var tooBig: [String] = []
    var tooMany = 0
    for file in picked {
      if file.size > ShareRules.maxFileBytes {
        tooBig.append(file.name)
      } else if kept.count >= ShareRules.maxFiles {
        tooMany += 1
      } else {
        kept.append(file)
      }
    }
    var problems: [String] = []
    if tooBig.count == 1 { problems.append("\(tooBig[0]) is over 25 MB, so it was not added.") }
    if tooBig.count > 1 { problems.append("\(tooBig.count) files are over 25 MB, so they were not added.") }
    if tooMany > 0 {
      problems.append("A note holds up to \(ShareRules.maxFiles) files. \(tooMany) \(tooMany == 1 ? "file was" : "files were") not added.")
    }
    return (kept, problems.isEmpty ? nil : problems.joined(separator: " "))
  }
}

/// The body of `POST notes`, the same JSON as LocalNote.toJson for a note with no place.
enum ShareNoteBody {
  static func body(clientId: String, text: String, createdAt: Int, files: [ShareFile]) -> [String: Any] {
    var body: [String: Any] = ["clientId": clientId, "text": text, "createdAt": createdAt]
    if !files.isEmpty {
      body["attachments"] = files.map { ["id": $0.id, "name": $0.name, "type": $0.type, "size": $0.size] as [String: Any] }
    }
    return body
  }
}
