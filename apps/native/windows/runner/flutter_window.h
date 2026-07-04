#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Registers the com.manykee.native/screen_protection MethodChannel that
  // toggles WDA_EXCLUDEFROMCAPTURE on this window while the vault is
  // unlocked, mirroring FLAG_SECURE on Android and the obscuring overlay on
  // iOS/macOS.
  void RegisterScreenProtectionChannel();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Kept alive for the lifetime of the window; SetMethodCallHandler's
  // closure captures `this` and must remain reachable.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      screen_protection_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
