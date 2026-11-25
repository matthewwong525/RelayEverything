import UIKit
import WebKit

/// The note's words are edited in a web view (lib/editor/web_note/). Two changes make its keyboard work as a note's:
///
/// - No bar with arrows and *Done* over the keyboard: the note page has its own tool bar there.
/// - A focus the editor page asks for, such as a new note opening, brings the keyboard up. WebKit shows the keyboard
///   only for a focus that comes from a tap, so its focus method is told the person is interacting.
///
/// Both change WebKit's own content view. Each name is looked up first: if a WebKit update renames one, that change
/// is not made, the app runs on, and the keyboard works as WebKit has it (a tap in the words still brings it up).
enum RelayWebKeyboard {
  private static var applied = false

  static func apply() {
    guard !applied, let content = NSClassFromString("WKContentView") else { return }
    applied = true
    removeAccessoryBar(content)
    allowFocusFromPage(content)
  }

  /// The content view's `inputAccessoryView` gives no bar.
  private static func removeAccessoryBar(_ content: AnyClass) {
    let selector = #selector(getter: UIResponder.inputAccessoryView)
    guard let method = class_getInstanceMethod(content, selector) else { return }
    let none: @convention(block) (AnyObject) -> UIView? = { _ in nil }
    let implementation = imp_implementationWithBlock(none)
    // A method the view only inherits is added to the view alone, so no other responder changes.
    if !class_addMethod(content, selector, implementation, method_getTypeEncoding(method)) {
      method_setImplementation(method, implementation)
    }
  }

  /// The content view's focus method, as WebKit has it since iOS 13, always says the person is interacting.
  private static func allowFocusFromPage(_ content: AnyClass) {
    let selector = sel_getUid("_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:")
    guard let method = class_getInstanceMethod(content, selector) else { return }
    typealias Focus = @convention(c) (AnyObject, Selector, UnsafeRawPointer?, Bool, Bool, UInt64, AnyObject?) -> Void
    let original = unsafeBitCast(method_getImplementation(method), to: Focus.self)
    let replacement: @convention(block) (AnyObject, UnsafeRawPointer?, Bool, Bool, UInt64, AnyObject?) -> Void = {
      view, information, _, blurPrevious, changes, userObject in
      original(view, selector, information, true, blurPrevious, changes, userObject)
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
  }
}
