import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Kept for the app's life: Sparkle holds its delegate weakly.
  private var updater: Updater?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    updater = Updater(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
