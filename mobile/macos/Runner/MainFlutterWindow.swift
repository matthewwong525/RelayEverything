import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Kept for the app's life: Sparkle holds its delegate weakly.
  private var updater: Updater?
  /// Cut, Copy and Paste from the Edit menu for a note's words: the web view takes them only as the system's own
  /// actions, sent to the view that has the keyboard.
  private var webEdit: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    updater = Updater(messenger: flutterViewController.engine.binaryMessenger)
    webEdit = FlutterMethodChannel(name: "relay/web-edit", binaryMessenger: flutterViewController.engine.binaryMessenger)
    webEdit?.setMethodCallHandler { call, result in
      let actions = ["cut": #selector(NSText.cut(_:)), "copy": #selector(NSText.copy(_:)),
                     "paste": #selector(NSText.paste(_:))]
      guard let action = actions[call.method] else { return result(FlutterMethodNotImplemented) }
      result(NSApp.sendAction(action, to: nil, from: nil))
    }

    super.awakeFromNib()
  }
}
