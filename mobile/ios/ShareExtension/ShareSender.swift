import Foundation
import Security

/// The phone's own key, from the Keychain group the app shares with the card (KeyVault in lib/data/connection.dart).
struct ShareConnection {
  let server: String
  let headers: [String: String]

  static func read() -> ShareConnection? {
    guard let server = item("relay.server") else { return nil }
    if let key = item("relay.key") { return ShareConnection(server: server, headers: ["Authorization": "Bearer \(key)"]) }
    guard let id = item("relay.clientId"), let secret = item("relay.clientSecret") else { return nil }
    return ShareConnection(server: server, headers: ["CF-Access-Client-Id": id, "CF-Access-Client-Secret": secret])
  }

  private static func item(_ account: String) -> String? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword, kSecAttrService: ShareRules.keychainService,
      kSecAttrAccessGroup: ShareRules.appGroup, kSecAttrAccount: account, kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var found: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

/// True only while the app has sending on and a key: the app writes it on each change (`setShareSettings`). An app
/// that never wrote it reads as off.
enum ShareSettings {
  static var sending: Bool { UserDefaults(suiteName: ShareRules.appGroup)?.bool(forKey: "sending") ?? false }
}

/// Sends a shared note, then each file from disk, with the phone's key, until one deadline. It stops at the first
/// failure: the app sends the rest, and the server stores a note or file sent twice once.
struct ShareSender {
  let connection: ShareConnection
  let session: URLSession = .shared

  enum Failure: Error { case notSent, late }

  /// Tells [sent] after each call that lands: the note, then the ids of the files so far. Throws at the first that
  /// does not, or at the deadline.
  func send(body: [String: Any], files: [ShareFile], until deadline: Date, sent: (_ note: Bool, _ files: [String]) -> Void)
    async throws
  {
    var note = try request("notes", until: deadline)
    note.setValue("application/json", forHTTPHeaderField: "Content-Type")
    note.httpBody = try JSONSerialization.data(withJSONObject: body)
    let noteRequest = note
    let session = self.session
    try await answer(until: deadline) { try await session.data(for: noteRequest) }
    var landed: [String] = []
    sent(true, landed)
    let noteId = body["clientId"] as? String ?? ""
    for file in files {
      guard let url = file.url else { continue }
      var upload = try request("attachments", until: deadline)
      upload.setValue(file.type.isEmpty ? "application/octet-stream" : file.type, forHTTPHeaderField: "Content-Type")
      upload.setValue(noteId, forHTTPHeaderField: "X-Note-Client-Id")
      upload.setValue(file.id, forHTTPHeaderField: "X-Attachment-Id")
      let uploadRequest = upload
      try await answer(until: deadline) { try await session.upload(for: uploadRequest, fromFile: url) }
      landed.append(file.id)
      sent(true, landed)
    }
  }

  private func request(_ route: String, until deadline: Date) throws -> URLRequest {
    guard let url = URL(string: "\(connection.server)/apps/relay/api/\(route)") else { throw Failure.notSent }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = max(1, deadline.timeIntervalSinceNow)
    connection.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  /// What a call answered: a JSON 200 is the only success, as Access answers a refused key with its sign-in page.
  private struct Answer: Sendable {
    let ok: Bool
  }

  /// Runs one call, cut off at the deadline.
  private func answer(until deadline: Date, call: @escaping @Sendable () async throws -> (Data, URLResponse))
    async throws
  {
    let answer = try await withThrowingTaskGroup(of: Answer?.self) { group -> Answer in
      group.addTask {
        let http = try await call().1 as? HTTPURLResponse
        let json = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").hasPrefix("application/json")
        return Answer(ok: http?.statusCode == 200 && json)
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(max(0, deadline.timeIntervalSinceNow) * 1_000_000_000))
        return nil
      }
      let first = try await group.next() ?? nil
      group.cancelAll()
      guard let first else { throw Failure.late }
      return first
    }
    if !answer.ok { throw Failure.notSent }
  }
}
