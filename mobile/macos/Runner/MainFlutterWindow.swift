import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Kept for the app's life: Sparkle holds its delegate weakly.
  private var updater: Updater?
  /// Gives a note's paste the clipboard's HTML, so pasted words keep their lists and styles.
  private var clipboard: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    updater = Updater(messenger: flutterViewController.engine.binaryMessenger)
    clipboard = FlutterMethodChannel(name: "relay/clipboard", binaryMessenger: flutterViewController.engine.binaryMessenger)
    clipboard?.setMethodCallHandler { call, result in
      guard call.method == "html" else { return result(FlutterMethodNotImplemented) }
      result(NSPasteboard.general.string(forType: .html))
    }

    super.awakeFromNib()
  }
}
