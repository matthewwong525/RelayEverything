import SwiftUI
import UIKit

// Relay Everything in the iPhone's share list: a card over the app the person shares from. Save keeps the note in the
// App Group's inbox, sends it at once while sending is on, and closes. The words match lib/share/share_card.dart.

enum ShareWords {
  static let sendingOn = "Sending is on: this goes to your space."
  static let sendingOff = "Kept on this phone. Sending is off."
  static let sendingNow = "Sending…"
  static let sent = "Sent"
  static let later = "Kept. It sends when you open Relay Everything."
  static let noGroup = "Relay Everything can't keep this. Open the app once, then share again."
}

@MainActor
final class ShareModel: ObservableObject {
  @Published var draft: ShareDraft?
  @Published var words = ""
  @Published var saving = false
  @Published var foot: String?

  let inbox: ShareInbox?
  let sending: Bool
  /// How long the card waits for the note and its files before it closes and the app sends the rest.
  static let wait: TimeInterval = 20
  var close: (_ saved: Bool) -> Void = { _ in }

  init() {
    inbox = ShareInbox(clientId: ShareRules.newId())
    sending = ShareSettings.sending && ShareConnection.read() != nil
  }

  var footLine: String { foot ?? (inbox == nil ? ShareWords.noGroup : sending ? ShareWords.sendingOn : keptLine) }
  /// While the app sends to the person's own webhook, the card keeps the share and the app sends it.
  var keptLine: String { ShareSettings.later ? ShareWords.later : ShareWords.sendingOff }
  var canSave: Bool { !saving && inbox != nil && (draft?.canSave(words) ?? false) }

  func load(_ items: [NSExtensionItem]) async {
    guard let inbox else {
      draft = ShareDraft()
      return
    }
    draft = await SharedItems.draft(from: items, into: inbox.staging)
    // Copies the note does not keep, past the tenth file, go at once.
    for file in draft?.given ?? [] where !(draft?.files.contains(file) ?? false) {
      if let url = file.url { try? FileManager.default.removeItem(at: url) }
    }
  }

  func cancel() {
    inbox?.discard()
    close(false)
  }

  func save() async {
    guard let inbox, let draft, canSave else { return }
    saving = true
    let text = draft.noteText(words)
    let createdAt = Int(Date().timeIntervalSince1970 * 1000)
    let files: [ShareFile]
    do {
      files = try inbox.commit(text: text, createdAt: createdAt, files: draft.files)
    } catch {
      saving = false
      foot = ShareWords.noGroup
      return
    }
    if sending, let connection = ShareConnection.read() {
      foot = ShareWords.sendingNow
      foot = await send(connection, inbox: inbox, text: text, createdAt: createdAt, files: files)
    } else {
      foot = keptLine
    }
    try? await Task.sleep(nanoseconds: 900_000_000)
    close(true)
  }

  private func send(_ connection: ShareConnection, inbox: ShareInbox, text: String, createdAt: Int, files: [ShareFile])
    async -> String
  {
    let body = ShareNoteBody.body(clientId: inbox.clientId, text: text, createdAt: createdAt, files: files)
    let sender = ShareSender(connection: connection)
    do {
      try await sender.send(body: body, files: files, until: Date().addingTimeInterval(Self.wait)) { note, sentFiles in
        inbox.markSent(text: text, createdAt: createdAt, files: files, sentNote: note, sentFiles: sentFiles)
      }
      return ShareWords.sent
    } catch {
      return ShareWords.later
    }
  }
}

struct ShareCardView: View {
  @ObservedObject var model: ShareModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Button("Cancel") { model.cancel() }.font(Brand.body).foregroundColor(Color(Brand.accentText))
          .disabled(model.saving)
        Spacer()
        Text("Relay Everything").font(Brand.title).foregroundColor(Color(Brand.ink))
        Spacer()
        Button("Save") { Task { await model.save() } }.buttonStyle(BrandFilledButton()).disabled(!model.canSave)
      }
      if let draft = model.draft {
        shared(draft)
        TextField("Add words", text: $model.words).font(Brand.body).foregroundColor(Color(Brand.ink))
          .padding(12).background(Color(Brand.card), in: RoundedRectangle(cornerRadius: Brand.fieldCorners))
          .disabled(model.saving)
        if let leftOut = draft.leftOut { Text(leftOut).font(Brand.small).foregroundColor(Color(Brand.danger)) }
      } else {
        ProgressView().tint(Color(Brand.accent))
      }
      Text(model.footLine).font(Brand.small).foregroundColor(Color(Brand.muted))
      Spacer()
    }
    .padding()
    .background(Color(Brand.paper).ignoresSafeArea())
    .tint(Color(Brand.accentText))
  }

  @ViewBuilder private func shared(_ draft: ShareDraft) -> some View {
    if draft.title != nil || draft.url != nil {
      VStack(alignment: .leading, spacing: 4) {
        if let title = draft.title { Text(title).font(Brand.body).foregroundColor(Color(Brand.ink)) }
        if let url = draft.url { Text(url).font(Brand.small).foregroundColor(Color(Brand.muted)).lineLimit(2) }
      }
      .padding(12).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(Brand.card), in: RoundedRectangle(cornerRadius: Brand.cardCorners))
    }
    if let text = draft.text {
      Text(text).font(Brand.body).foregroundColor(Color(Brand.ink)).lineLimit(4).padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(Brand.card), in: RoundedRectangle(cornerRadius: Brand.cardCorners))
    }
    if !draft.files.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(draft.files, id: \.id) { file in
            Text("\(file.name) · \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
              .font(Brand.small).foregroundColor(Color(Brand.ink)).padding(.horizontal, 10).padding(.vertical, 4)
              .background(Color(Brand.line), in: Capsule())
          }
        }
      }
    }
  }
}

/// The extension's principal class, named in Info.plist.
final class ShareViewController: UIViewController {
  private let model = ShareModel()

  override func viewDidLoad() {
    super.viewDidLoad()
    model.close = { [weak self] saved in
      if saved {
        self?.extensionContext?.completeRequest(returningItems: nil)
      } else {
        self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
      }
    }
    let card = UIHostingController(rootView: ShareCardView(model: model))
    addChild(card)
    card.view.frame = view.bounds
    card.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(card.view)
    card.didMove(toParent: self)
    let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    Task { await model.load(items) }
  }
}
