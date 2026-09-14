import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Retained for the app's lifetime: it owns the `NotificationCenter`
  /// observer behind Reduce Transparency change notifications (R-33-051).
  private var chromeReduceTransparencyChannel: ChromeReduceTransparencyChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Opens the app's settings screen for a person to grant a permission
  /// denied at the OS level, per `docs/31-mockups/02-pair-scan.md`'s
  /// "Permission denied" state. Called from
  /// `app/lib/screens/qr_scan_screen.dart` (WP-15-b) over the
  /// `dev.herdr.herdr_mobile/app_settings` channel, "open" method.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let chromeReduceTransparencyRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "ChromeReduceTransparencyChannel"
    )
    chromeReduceTransparencyChannel = ChromeReduceTransparencyChannel.register(
      with: chromeReduceTransparencyRegistrar
    )

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppSettingsChannel")
    let channel = FlutterMethodChannel(
      name: "dev.herdr.herdr_mobile/app_settings",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(FlutterError(code: "invalid_url", message: "openSettingsURLString invalid", details: nil))
        return
      }
      UIApplication.shared.open(url) { success in
        result(success)
      }
    }
  }
}
