import Flutter
import UIKit

/// The iPhone's own *Paste* in a note keeps the words' formatting. Flutter's text view pastes only the clipboard's
/// plain words, so its `paste:` is replaced here: it reads the clipboard's HTML (or a web archive, or RTF made into
/// simple HTML) with the plain words and hands both to the app on `relay/paste` (lib/screens/note_editor.dart). The
/// reads run inside the person's own Paste, so the phone asks no *Allow Paste?* question. When the app answers false,
/// fails, or no channel is set, the plain words go in as Flutter's own `paste:` puts them. If a Flutter update renames
/// the view or its method, nothing is replaced and Paste stays plain.
///
/// A paste the app starts itself, from its drawn menu (iOS 15) or ⌘V on a keyboard, asks `relay/clipboard` for `html`:
/// the same formatted words, or nil when the clipboard holds only plain words.
enum RelayPaste {
  private static var channel: FlutterMethodChannel?
  private static var clipboard: FlutterMethodChannel?
  private static var replaced = false

  static func register(_ messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "relay/paste", binaryMessenger: messenger)
    clipboard = FlutterMethodChannel(name: "relay/clipboard", binaryMessenger: messenger)
    clipboard?.setMethodCallHandler { call, result in
      guard call.method == "html" else { return result(FlutterMethodNotImplemented) }
      result(RelayPaste.formattedHtml(UIPasteboard.general))
    }
    replacePaste()
  }

  /// [htmlOf] the clipboard, read only when it holds formatted words: the list of types reads no words, so a clipboard
  /// of plain words is read once, by Flutter, not again here.
  private static func formattedHtml(_ board: UIPasteboard) -> String? {
    let formatted: Set<String> = ["public.html", "Apple Web Archive pasteboard type", "com.apple.webarchive",
                                  "public.rtf", "com.apple.flat-rtfd"]
    guard board.types.contains(where: formatted.contains) else { return nil }
    return htmlOf(board)
  }

  /// Puts [paste(into:)] in front of the Flutter text view's own `paste:`, once.
  private static func replacePaste() {
    guard !replaced, let viewClass = NSClassFromString("FlutterTextInputView") else { return }
    let selector = #selector(UIResponderStandardEditActions.paste(_:))
    guard let method = class_getInstanceMethod(viewClass, selector) else { return }
    typealias PasteFunction = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    let original = unsafeBitCast(method_getImplementation(method), to: PasteFunction.self)
    let replacement: @convention(block) (AnyObject, AnyObject?) -> Void = { view, sender in
      if !RelayPaste.paste(into: view) { original(view, selector, sender) }
    }
    let implementation = imp_implementationWithBlock(replacement)
    // A method the view only inherits is added to the view alone, so no other responder changes.
    if !class_addMethod(viewClass, selector, implementation, method_getTypeEncoding(method)) {
      method_setImplementation(method, implementation)
    }
    replaced = true
  }

  /// Reads the clipboard now and sends it to the app. False when there is no channel or no plain words, so the view's
  /// own `paste:` runs.
  private static func paste(into view: AnyObject) -> Bool {
    guard let channel = channel, let plain = UIPasteboard.general.string else { return false }
    var words: [String: Any] = ["plain": plain]
    if let html = htmlOf(UIPasteboard.general) { words["html"] = html }
    weak var target: AnyObject? = view
    channel.invokeMethod("paste", arguments: words) { result in
      if let handled = result as? Bool, handled { return }
      // The plain words read at the paste, as Flutter's own paste: inserts them; no second clipboard read.
      (target as? UIKeyInput)?.insertText(plain)
    }
    return true
  }

  /// The clipboard's formatted words as HTML: a page's HTML, else Safari's web archive, else RTF from Apple Notes or
  /// Pages made into simple HTML. Nil when it holds only plain words.
  static func htmlOf(_ board: UIPasteboard) -> String? {
    if let html = text(board, "public.html") { return html }
    for type in ["Apple Web Archive pasteboard type", "com.apple.webarchive"] {
      if let data = board.data(forPasteboardType: type),
         let archive = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
         let main = archive["WebMainResource"] as? [String: Any],
         let page = main["WebResourceData"] as? Data,
         let html = String(data: page, encoding: .utf8) {
        return html
      }
    }
    for (type, kind) in [("public.rtf", NSAttributedString.DocumentType.rtf),
                         ("com.apple.flat-rtfd", NSAttributedString.DocumentType.rtfd)] {
      if let data = board.data(forPasteboardType: type),
         let words = try? NSAttributedString(data: data, options: [.documentType: kind], documentAttributes: nil) {
        return html(of: words)
      }
    }
    return nil
  }

  private static func text(_ board: UIPasteboard, _ type: String) -> String? {
    if let value = board.value(forPasteboardType: type) as? String { return value }
    if let data = board.data(forPasteboardType: type) { return String(data: data, encoding: .utf8) }
    return nil
  }

  /// Simple HTML of [words]: a paragraph or list item for each paragraph, and bold, italic, underlined and struck
  /// words and links in it. Not NSAttributedString's own HTML, whose styles sit in CSS classes the app does not read.
  static func html(of words: NSAttributedString) -> String {
    let all = words.string as NSString
    var out = ""
    var openList: String?
    all.enumerateSubstrings(in: NSRange(location: 0, length: all.length), options: .byParagraphs) { _, range, _, _ in
      var tag: String?
      var level = 1
      if #available(iOS 16.0, *), range.length > 0 {
        if let style = words.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
           let list = style.textLists.last {
          tag = RelayPaste.unordered.contains(list.markerFormat) ? "ul" : "ol"
          level = style.textLists.count
        }
      }
      if openList != tag {
        if let open = openList { out += "</\(open)>" }
        if let tag = tag { out += "<\(tag)>" }
        openList = tag
      }
      var body = range
      // RTF writes a list's own marker as words first: a tab, `•` or `1.`, then a tab.
      let text = all.substring(with: range)
      if tag != nil, let marker = text.range(of: "^\\t[^\\t]*\\t", options: .regularExpression) {
        let skip = text[marker].utf16.count
        body = NSRange(location: range.location + skip, length: range.length - skip)
      }
      var line = ""
      words.enumerateAttributes(in: body, options: []) { attributes, part, _ in
        line += RelayPaste.inline(all.substring(with: part), attributes)
      }
      if tag != nil {
        out += "<li aria-level=\"\(level)\">\(line)</li>"
      } else {
        out += line.isEmpty ? "<p><br></p>" : "<p>\(line)</p>"
      }
    }
    if let open = openList { out += "</\(open)>" }
    return out
  }

  @available(iOS 16.0, *)
  private static var unordered: Set<NSTextList.MarkerFormat> {
    [.box, .check, .circle, .diamond, .disc, .hyphen, .square]
  }

  /// One run of words in its inline tags.
  private static func inline(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> String {
    var html = escape(text)
    if html.isEmpty { return html }
    let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
    if traits.contains(.traitBold) { html = "<b>\(html)</b>" }
    if traits.contains(.traitItalic) { html = "<i>\(html)</i>" }
    if let underline = attributes[.underlineStyle] as? Int, underline != 0 { html = "<u>\(html)</u>" }
    if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 { html = "<s>\(html)</s>" }
    let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
    if let link = link { html = "<a href=\"\(escape(link))\">\(html)</a>" }
    return html
  }

  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }
}
