import Flutter
import UIKit

private let screenProtectionChannel = "com.manykee.native/screen_protection"

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var isSecureEnabled = false
  private var privacyOverlay: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: screenProtectionChannel,
        binaryMessenger: controller.binaryMessenger
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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    showPrivacyOverlayIfNeeded()
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    hidePrivacyOverlay()
  }

  private func showPrivacyOverlayIfNeeded() {
    guard isSecureEnabled, privacyOverlay == nil, let window = self.window else { return }
    let overlay = UIView(frame: window.bounds)
    overlay.backgroundColor = .black
    window.addSubview(overlay)
    privacyOverlay = overlay
  }

  private func hidePrivacyOverlay() {
    privacyOverlay?.removeFromSuperview()
    privacyOverlay = nil
  }
}
