import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setFrame(MainFlutterWindow.firstFrame(for: self), display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    contentMinSize = NSSize(width: 640, height: 480)
    // The size the player leaves it at is kept for the next launch.
    setFrameAutosaveName("RotaThree")
  }

  /// A 16:10 window most of the screen high, in the middle of it: the game
  /// is drawn to the window, and a large one shows it as it is meant to be.
  static func firstFrame(for window: NSWindow) -> NSRect {
    guard let screen = window.screen ?? NSScreen.main else { return window.frame }
    let visible = screen.visibleFrame
    let height = min(visible.height * 0.86, 1000)
    let width = min(height * 1.6, visible.width * 0.92)
    let content = NSRect(x: 0, y: 0, width: width, height: height)
    var frame = window.frameRect(forContentRect: content)
    frame.origin.x = visible.midX - frame.width / 2
    frame.origin.y = visible.midY - frame.height / 2
    return frame
  }
}
