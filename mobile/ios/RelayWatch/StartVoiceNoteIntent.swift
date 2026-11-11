import AppIntents

// Start a voice note: opens the watch app already recording. The Apple Watch Ultra's Action button runs it.

struct StartVoiceNoteIntent: AppIntent {
  static var title: LocalizedStringResource = "Start a voice note"
  static var description = IntentDescription("Opens Relay Everything on your watch and starts recording. Tap to save.")
  static var openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    WatchModel.shared.talk()
    return .result()
  }
}

struct RelayWatchShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: StartVoiceNoteIntent(), phrases: ["Start a voice note in \(.applicationName)"],
      shortTitle: "Start a voice note", systemImageName: "mic.fill")
  }
}
