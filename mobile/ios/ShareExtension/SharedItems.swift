import Foundation
import UniformTypeIdentifiers

/// Turns what another app shared into a draft. Each file is copied at once into [folder], in the App Group, because the
/// system deletes its own copy; a file over 25 MB is never copied, only named.
enum SharedItems {
  static func draft(from items: [NSExtensionItem], into folder: URL) async -> ShareDraft {
    var texts: [String] = []
    var url: String?
    var subject: String?
    var files: [ShareFile] = []
    for item in items {
      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
          !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
          let link = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL
        {
          url = url ?? link.absoluteString
          // Safari gives the page's title as the item's title or text.
          subject = subject ?? item.attributedTitle?.string ?? item.attributedContentText?.string
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
          let source = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL
        {
          if let file = copy(from: source, name: source.lastPathComponent, index: files.count, into: folder) {
            files.append(file)
          }
        } else if let type = fileType(provider) {
          if let file = await copy(provider, type: type, index: files.count, into: folder) { files.append(file) }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
        {
          texts.append(text)
        }
      }
    }
    return ShareDraft(text: texts.isEmpty ? nil : texts.joined(separator: "\n"), subject: subject, url: url, files: files)
  }

  /// The type to load a file by: an image, a movie, a PDF or any other file, but not plain text or a link.
  private static func fileType(_ provider: NSItemProvider) -> UTType? {
    for identifier in provider.registeredTypeIdentifiers {
      guard let type = UTType(identifier) else { continue }
      if type.conforms(to: .plainText) || type.conforms(to: .url) { continue }
      if type.conforms(to: .data) { return type }
    }
    return nil
  }

  /// A file name safe in a folder: no slashes, no leading dot.
  private static func safeName(_ name: String, _ index: Int) -> String {
    let plain = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    return "\(index + 1)-\(plain.isEmpty ? "file" : plain)"
  }

  private static func copy(_ provider: NSItemProvider, type: UTType, index: Int, into folder: URL) async -> ShareFile? {
    let given = provider.suggestedName ?? "file-\(index + 1)"
    let ext = type.preferredFilenameExtension.map { given.hasSuffix(".\($0)") ? "" : ".\($0)" } ?? ""
    return await withCheckedContinuation { continuation in
      _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { source, _ in
        // The system deletes `source` when this returns, so the copy happens here.
        continuation.resume(returning: source.flatMap { copy(from: $0, name: given + ext, index: index, into: folder) })
      }
    }
  }

  /// Copies one file into [folder] by its URL, never into memory. A file over 25 MB is named, not copied.
  private static func copy(from source: URL, name: String, index: Int, into folder: URL) -> ShareFile? {
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    let type = UTType(filenameExtension: source.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size <= ShareRules.maxFileBytes else {
      return ShareFile(id: ShareRules.newId(), name: name, type: type, size: size, url: nil)
    }
    let target = folder.appendingPathComponent(safeName(name, index))
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try? FileManager.default.removeItem(at: target)
      try FileManager.default.copyItem(at: source, to: target)
      return ShareFile(id: ShareRules.newId(), name: name, type: type, size: size, url: target)
    } catch {
      return nil
    }
  }
}
