import AppIntents
import Flutter
import Foundation
import UniformTypeIdentifiers

// Relay Everything's actions in Apple Shortcuts, Siri, Spotlight and the Action button: Add a note, Get notes and
// Start a voice note. They need iOS 16; on iOS 15 the app runs without them.
//
// The actions run the app's own Dart code (lib/shortcuts/), so a shortcut's note is kept, pinned and sent the same
// way as a note typed in the app. While the app's own engine runs, the call goes to it; otherwise a background engine
// starts on `shortcutsMain` and stays warm while the process lives. When neither answers in 20 seconds, Add a note
// leaves its note in `shortcuts-inbox/`, and the app keeps it the next time it opens.

/// The app's support folder, the same one Dart's getApplicationSupportDirectory gives.
enum RelayFolders {
  static var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
  static var inbox: URL { support.appendingPathComponent("shortcuts-inbox", isDirectory: true) }

  /// A path from Dart, full or from the support folder, as a file URL.
  static func url(_ path: String) -> URL {
    path.hasPrefix("/") ? URL(fileURLWithPath: path) : support.appendingPathComponent(path)
  }
}

@available(iOS 16, *)
enum RelayIntentError: Error, CustomLocalizedStringResourceConvertible {
  /// The app's own words, such as a note with nothing in it.
  case message(String)
  /// No engine answered in time.
  case noAnswer
  /// The engine has no answer for this call, such as an app engine that is not ready yet.
  case notReady

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .message(let text): return LocalizedStringResource(stringLiteral: text)
    case .noAnswer, .notReady: return "Relay Everything did not answer. Try again."
    }
  }
}

/// One answer or a timeout, whichever comes first. Each step runs on the main thread, as Flutter's channels do.
@available(iOS 16, *)
final class OneAnswer {
  private var continuation: CheckedContinuation<Any?, Error>?

  func wait(until deadline: Date, start: @escaping (OneAnswer) -> Void) async throws -> Any? {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async {
        self.continuation = continuation
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow)) {
          self.finish(.failure(RelayIntentError.noAnswer))
        }
        start(self)
      }
    }
  }

  func finish(_ result: Result<Any?, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(with: result)
  }
}

/// The way from an action to Dart, on the `relay/shortcuts` channel. Its state is read and written on the main thread
/// only.
@available(iOS 16, *)
final class ShortcutsEngine {
  static let shared = ShortcutsEngine()
  static let channelName = "relay/shortcuts"

  private var appChannel: FlutterMethodChannel?
  private var appReady = false
  private var pendingVoice = false
  private var engine: FlutterEngine?
  private var engineChannel: FlutterMethodChannel?
  private var engineReady = false
  private var readyWaiters: [() -> Void] = []

  /// AppDelegate calls this when the app's own engine starts. Dart says `ready` once it answers.
  func attachApp(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "ready" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
      self?.appIsReady()
    }
    appChannel = channel
    appReady = false
  }

  private func appIsReady() {
    appReady = true
    if pendingVoice {
      pendingVoice = false
      appChannel?.invokeMethod("startVoiceNote", arguments: nil)
    }
  }

  /// Opens the recording sheet in the app, now or as soon as the app's engine is ready.
  func startVoiceNote() {
    if appReady, let channel = appChannel {
      channel.invokeMethod("startVoiceNote", arguments: nil)
    } else {
      pendingVoice = true
    }
  }

  /// The background engine, started once and kept while the process lives.
  private func headless() -> FlutterMethodChannel {
    if let channel = engineChannel { return channel }
    let engine = FlutterEngine(name: "relay-shortcuts", project: nil, allowHeadlessExecution: true)
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "ready" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
      self?.engineIsReady()
    }
    engine.run(withEntrypoint: "shortcutsMain", libraryURI: "package:relay_app/shortcuts/entry.dart")
    GeneratedPluginRegistrant.register(with: engine)
    if let registrar = engine.registrar(forPlugin: "RelayChannels") { RelayChannels.register(registrar.messenger()) }
    self.engine = engine
    engineChannel = channel
    return channel
  }

  private func engineIsReady() {
    engineReady = true
    let waiters = readyWaiters
    readyWaiters = []
    waiters.forEach { $0() }
  }

  /// The app's channel when its engine is ready, or else the background engine's, once it is ready.
  private func readyChannel(until deadline: Date) async throws -> FlutterMethodChannel {
    let (channel, ready) = await MainActor.run { () -> (FlutterMethodChannel, Bool) in
      if self.appReady, let app = self.appChannel { return (app, true) }
      return (self.headless(), self.engineReady)
    }
    if ready { return channel }
    _ = try await OneAnswer().wait(until: deadline) { answer in
      if self.engineReady {
        answer.finish(.success(nil))
      } else {
        self.readyWaiters.append { answer.finish(.success(nil)) }
      }
    }
    return channel
  }

  private func invoke(_ channel: FlutterMethodChannel, _ method: String, _ arguments: Any?, until deadline: Date)
    async throws -> Any?
  {
    try await OneAnswer().wait(until: deadline) { answer in
      channel.invokeMethod(method, arguments: arguments) { result in
        if let error = result as? FlutterError {
          answer.finish(.failure(RelayIntentError.message(error.message ?? "Relay Everything could not do that.")))
        } else if (result as AnyObject) === FlutterMethodNotImplemented {
          answer.finish(.failure(RelayIntentError.notReady))
        } else {
          answer.finish(.success(result))
        }
      }
    }
  }

  /// Calls Dart and gives its answer, or throws when no engine answers within [seconds].
  func call(_ method: String, _ arguments: Any?, seconds: TimeInterval = 20) async throws -> Any? {
    let deadline = Date().addingTimeInterval(seconds)
    let channel = try await readyChannel(until: deadline)
    do {
      return try await invoke(channel, method, arguments, until: deadline)
    } catch RelayIntentError.notReady {
      // The app's engine went away: the background engine answers instead.
      let wasApp = await MainActor.run { () -> Bool in
        let app = channel === self.appChannel
        if app { self.appReady = false }
        return app
      }
      if !wasApp { throw RelayIntentError.noAnswer }
      return try await invoke(try await readyChannel(until: deadline), method, arguments, until: deadline)
    }
  }
}

/// A note on this phone, as Shortcuts passes it to the next step.
@available(iOS 16, *)
struct RelayNoteEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Relay Everything note"
  static var defaultQuery = RelayNoteQuery()

  let id: String

  @Property(title: "Words")
  var text: String

  @Property(title: "Time")
  var createdAt: Date

  @Property(title: "Place")
  var place: String?

  @Property(title: "Kind")
  var kind: String

  @Property(title: "Files")
  var files: [IntentFile]

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(text.isEmpty ? "\(files.count) files" : text)")
  }

  init(id: String, text: String, createdAt: Date, place: String?, kind: String, files: [IntentFile]) {
    self.id = id
    self.text = text
    self.createdAt = createdAt
    self.place = place
    self.kind = kind
    self.files = files
  }

  /// A note as `lib/shortcuts/bridge.dart` gives it.
  init?(_ note: [String: Any]) {
    guard let id = note["id"] as? String else { return nil }
    let milliseconds = (note["createdAt"] as? NSNumber)?.doubleValue ?? 0
    let files = (note["files"] as? [[String: Any]] ?? []).compactMap { file -> IntentFile? in
      guard let path = file["path"] as? String else { return nil }
      let url = RelayFolders.url(path)
      let type = (file["type"] as? String).flatMap { UTType(mimeType: $0) }
      return IntentFile(fileURL: url, filename: file["name"] as? String ?? url.lastPathComponent, type: type)
    }
    self.init(id: id, text: note["text"] as? String ?? "", createdAt: Date(timeIntervalSince1970: milliseconds / 1000),
      place: note["place"] as? String, kind: note["kind"] as? String == "voice" ? "Voice" : "Typed", files: files)
  }
}

@available(iOS 16, *)
struct RelayNoteQuery: EntityQuery {
  private func notes(_ request: [String: Any]) async throws -> [RelayNoteEntity] {
    let answer = try await ShortcutsEngine.shared.call("get", request)
    return (answer as? [[String: Any]] ?? []).compactMap { RelayNoteEntity($0) }
  }

  func entities(for identifiers: [String]) async throws -> [RelayNoteEntity] {
    try await notes(["limit": 1000]).filter { identifiers.contains($0.id) }
  }

  func suggestedEntities() async throws -> [RelayNoteEntity] {
    try await notes(["limit": 10])
  }
}

/// Add a note: words, files, or both. It runs without opening the app, and gives the new note back.
@available(iOS 16, *)
struct AddNoteIntent: AppIntent {
  static var title: LocalizedStringResource = "Add a note"
  static var description = IntentDescription(
    "Keeps a note in Relay Everything, with words, files, or both. With sending on, it goes to your space too.")
  static var openAppWhenRun = false

  @Parameter(title: "Words")
  var text: String?

  @Parameter(title: "Files")
  var files: [IntentFile]?

  static var parameterSummary: some ParameterSummary {
    Summary("Add \(\.$text) to Relay Everything") {
      \.$files
    }
  }

  /// A file name safe in a folder: no slashes, no leading dot.
  private func safeName(_ name: String, _ index: Int) -> String {
    let plain = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    return "\(index + 1)-\(plain.isEmpty ? "file" : plain)"
  }

  /// The same limit as the app's: 25 MB a file.
  static let maxFileBytes = 25 * 1024 * 1024

  /// The words for files left out because they are over the limit, as the app says them; empty when none were.
  private func tooBigMessage(_ names: [String]) -> String {
    switch names.count {
    case 0: return ""
    case 1: return "\(names[0]) is over 25 MB, so it was not added. "
    default: return "\(names.count) files are over 25 MB, so they were not added. "
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<RelayNoteEntity> & ProvidesDialog {
    let words = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let given = files ?? []
    // Run with nothing, such as from Siri or the app's tile in Shortcuts, it asks for the words.
    if words.isEmpty && given.isEmpty { throw $text.needsValueError("What do you want to keep?") }
    let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let createdAt = Date()
    let folder = RelayFolders.inbox.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    // Shortcuts deletes its own copy of each file once this returns, so the app keeps one first. A file over the limit
    // is never read: the size comes from its URL, and the copy goes by URL too.
    var list: [[String: Any]] = []
    var tooBig: [String] = []
    for (index, file) in given.enumerated() {
      let stored = safeName(file.filename, index)
      let target = folder.appendingPathComponent(stored)
      if let source = file.fileURL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > Self.maxFileBytes {
          tooBig.append(file.filename.isEmpty ? stored : file.filename)
          continue
        }
        try FileManager.default.copyItem(at: source, to: target)
      } else {
        // A file with no URL is already in memory, such as text from an earlier step.
        if file.data.count > Self.maxFileBytes {
          tooBig.append(file.filename.isEmpty ? stored : file.filename)
          continue
        }
        try file.data.write(to: target)
      }
      list.append([
        "path": "shortcuts-inbox/\(id)/\(stored)", "name": file.filename.isEmpty ? stored : file.filename,
        "type": file.type?.preferredMIMEType ?? "",
      ])
    }
    let request: [String: Any] = [
      "id": id, "text": words, "createdAt": Int(createdAt.timeIntervalSince1970 * 1000), "files": list,
    ]
    do {
      let answer = try await ShortcutsEngine.shared.call("add", request)
      guard let note = answer as? [String: Any], let entity = RelayNoteEntity(note) else {
        throw RelayIntentError.noAnswer
      }
      try? FileManager.default.removeItem(at: folder)
      let message = note["message"] as? String ?? "Saved to Relay Everything."
      return .result(value: entity, dialog: IntentDialog(stringLiteral: tooBigMessage(tooBig) + message))
    } catch RelayIntentError.message(let text) {
      try? FileManager.default.removeItem(at: folder)
      throw RelayIntentError.message(tooBigMessage(tooBig) + text)
    } catch {
      // No engine answered: the note waits in the inbox, and the app keeps it on its next open. The same id keeps a
      // note the engine saved late from being kept twice.
      let data = try JSONSerialization.data(withJSONObject: request)
      try data.write(to: RelayFolders.inbox.appendingPathComponent("\(id).json"), options: .atomic)
      let entity = RelayNoteEntity(
        id: id, text: words, createdAt: createdAt, place: nil, kind: "Typed",
        files: list.compactMap { file in
          (file["path"] as? String).map { IntentFile(fileURL: RelayFolders.url($0), filename: file["name"] as? String) }
        })
      return .result(value: entity, dialog: IntentDialog(
        stringLiteral: tooBigMessage(tooBig) + "Saved. It shows when you open Relay Everything."))
    }
  }
}

/// Get notes: this phone's notes for the next step, newest first. It reads only the phone and sends nothing.
@available(iOS 16, *)
struct GetNotesIntent: AppIntent {
  static var title: LocalizedStringResource = "Get notes"
  static var description = IntentDescription(
    "Gives the notes on this phone to the next step, newest first: their words, time, place and files. It sends nothing.")
  static var openAppWhenRun = false

  @Parameter(title: "How many", default: 10)
  var limit: Int

  @Parameter(title: "Holds words")
  var query: String?

  @Parameter(title: "Since")
  var since: Date?

  static var parameterSummary: some ParameterSummary {
    Summary("Get the newest \(\.$limit) notes") {
      \.$query
      \.$since
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<[RelayNoteEntity]> {
    var request: [String: Any] = ["limit": limit]
    if let query, !query.isEmpty { request["query"] = query }
    if let since { request["since"] = Int(since.timeIntervalSince1970 * 1000) }
    let answer = try await ShortcutsEngine.shared.call("get", request)
    return .result(value: (answer as? [[String: Any]] ?? []).compactMap { RelayNoteEntity($0) })
  }
}

/// Start a voice note: opens the app and records at once. Made for the Action button.
@available(iOS 16, *)
struct StartVoiceNoteIntent: AppIntent {
  static var title: LocalizedStringResource = "Start a voice note"
  static var description = IntentDescription("Opens Relay Everything and starts recording. Tap Stop to save.")
  static var openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    ShortcutsEngine.shared.startVoiceNote()
    return .result()
  }
}

/// The actions Siri and Spotlight know without a shortcut made first.
@available(iOS 16, *)
struct RelayShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: AddNoteIntent(), phrases: [
      "Add a note to \(.applicationName)",
      "Keep a note in \(.applicationName)",
    ])
    AppShortcut(intent: GetNotesIntent(), phrases: ["Get notes from \(.applicationName)"])
    AppShortcut(intent: StartVoiceNoteIntent(), phrases: ["Start a voice note in \(.applicationName)"])
  }
}
