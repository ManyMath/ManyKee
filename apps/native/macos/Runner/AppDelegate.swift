import Cocoa
import FlutterMacOS

private let screenProtectionChannel = "com.manykee.native/screen_protection"

@main
class AppDelegate: FlutterAppDelegate {
  private var isSecureEnabled = false
  private var privacyOverlay: NSView?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    if let controller = NSApp.windows.first?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: screenProtectionChannel,
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "setSecure" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let args = call.arguments as? [String: Any]
        self?.isSecureEnabled = args?["enabled"] as? Bool ?? false
        result(nil)
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillResignActive(_ notification: Notification) {
    showPrivacyOverlayIfNeeded()
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    hidePrivacyOverlay()
  }

  private func showPrivacyOverlayIfNeeded() {
    guard isSecureEnabled, privacyOverlay == nil,
      let contentView = NSApp.windows.first?.contentView
    else { return }
    let overlay = NSView(frame: contentView.bounds)
    overlay.wantsLayer = true
    overlay.layer?.backgroundColor = NSColor.black.cgColor
    overlay.autoresizingMask = [.width, .height]
    contentView.addSubview(overlay)
    privacyOverlay = overlay
  }

  private func hidePrivacyOverlay() {
    privacyOverlay?.removeFromSuperview()
    privacyOverlay = nil
  }
}
