import Cocoa
import FlutterMacOS

private let screenProtectionChannel = "com.manykee.native/screen_protection"
private let securityScopedFilesChannel = "com.manykee.native/security_scoped_files"

@main
class AppDelegate: FlutterAppDelegate {
  private var isSecureEnabled = false
  private var privacyOverlay: NSView?
  private var activeSecurityScopedURLs: [String: URL] = [:]

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    if let controller = NSApp.windows.first?.contentViewController as? FlutterViewController {
      let screenChannel = FlutterMethodChannel(
        name: screenProtectionChannel,
        binaryMessenger: controller.engine.binaryMessenger
      )
      screenChannel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "setSecure" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let args = call.arguments as? [String: Any]
        self?.isSecureEnabled = args?["enabled"] as? Bool ?? false
        result(nil)
      }

      let filesChannel = FlutterMethodChannel(
        name: securityScopedFilesChannel,
        binaryMessenger: controller.engine.binaryMessenger
      )
      filesChannel.setMethodCallHandler { [weak self] call, result in
        self?.handleSecurityScopedFileCall(call, result: result)
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    stopAllSecurityScopedAccess()
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

  private func handleSecurityScopedFileCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "bookmarkForPath":
      createSecurityScopedBookmark(call, result: result)
    case "startAccessingBookmark":
      startAccessingSecurityScopedBookmark(call, result: result)
    case "stopAccessing":
      stopAccessingSecurityScopedBookmark(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func createSecurityScopedBookmark(
    _ call: FlutterMethodCall,
    result: FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let path = args["path"] as? String
    else {
      result(FlutterError(
        code: "BAD_ARGS",
        message: "Expected a file path.",
        details: nil
      ))
      return
    }

    do {
      let url = URL(fileURLWithPath: path)
      let bookmark = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      result(bookmark.base64EncodedString())
    } catch {
      result(FlutterError(
        code: "BOOKMARK_FAILED",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func startAccessingSecurityScopedBookmark(
    _ call: FlutterMethodCall,
    result: FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let encodedBookmark = args["bookmark"] as? String,
      let bookmark = Data(base64Encoded: encodedBookmark)
    else {
      result(FlutterError(
        code: "BAD_ARGS",
        message: "Expected a base64 security-scoped bookmark.",
        details: nil
      ))
      return
    }

    do {
      var stale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
      guard url.startAccessingSecurityScopedResource() else {
        result(FlutterError(
          code: "ACCESS_DENIED",
          message: "Could not start security-scoped file access.",
          details: nil
        ))
        return
      }

      let token = UUID().uuidString
      activeSecurityScopedURLs[token] = url
      result([
        "token": token,
        "path": url.path,
        "stale": stale
      ])
    } catch {
      result(FlutterError(
        code: "RESOLVE_FAILED",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func stopAccessingSecurityScopedBookmark(
    _ call: FlutterMethodCall,
    result: FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let token = args["token"] as? String
    else {
      result(FlutterError(
        code: "BAD_ARGS",
        message: "Expected an access token.",
        details: nil
      ))
      return
    }

    if let url = activeSecurityScopedURLs.removeValue(forKey: token) {
      url.stopAccessingSecurityScopedResource()
    }
    result(nil)
  }

  private func stopAllSecurityScopedAccess() {
    for url in activeSecurityScopedURLs.values {
      url.stopAccessingSecurityScopedResource()
    }
    activeSecurityScopedURLs.removeAll()
  }
}
