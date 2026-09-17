import Flutter
import Security
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Retained for the app's lifetime: it owns the `NotificationCenter`
  /// observer behind Reduce Transparency change notifications (R-33-051).
  private var chromeReduceTransparencyChannel: ChromeReduceTransparencyChannel?

  private let keychainSession = KeychainSession()
  private let keychainQueue = DispatchQueue(label: "dev.herdr.keychain-session")
  private var pushChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    pushChannel?.invokeMethod("token", arguments: deviceToken.map { String(format: "%02x", $0) }.joined())
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    pushChannel?.invokeMethod("failed", arguments: error.localizedDescription)
  }

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PushChannel") {
      let channel = FlutterMethodChannel(
        name: "dev.herdr.herdr_mobile/push",
        binaryMessenger: registrar.messenger()
      )
      pushChannel = channel
      channel.setMethodCallHandler { call, result in
        guard call.method == "register" else {
          result(FlutterMethodNotImplemented)
          return
        }
        UIApplication.shared.registerForRemoteNotifications()
        result(nil)
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeychainSession") {
      let channel = FlutterMethodChannel(
        name: "dev.herdr.herdr_mobile/keychain_session", binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [self] call, result in
        if call.method == "invalidate" {
          keychainSession.invalidate()
          result(nil)
          return
        }
        guard call.method == "read", let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        let generation = keychainSession.generation
        keychainQueue.async { [self] in
          let (status, value) = keychainSession.read(key: key, generation: generation)
          DispatchQueue.main.async { [self] in
            let status = generation == keychainSession.generation ? status : errSecUserCanceled
            if status == errSecSuccess {
              result(value)
            } else {
              // Preserve KeystoreService's OSStatus classification without logging secrets.
              result(FlutterError(code: "keychain_read", message: "Code: \(status)", details: status))
            }
          }
        }
      }
    }
    if let cameraZoomRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "CameraZoomChannel"
    ) {
      CameraZoomChannel.register(with: cameraZoomRegistrar)
    }

    if let chromeReduceTransparencyRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "ChromeReduceTransparencyChannel"
    ) {
      chromeReduceTransparencyChannel = ChromeReduceTransparencyChannel.register(
        with: chromeReduceTransparencyRegistrar
      )
    }

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppSettingsChannel") else {
      return
    }
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

    // R-22-020: the app icon badge mirrors the unread notification count. Called from
    // `app/lib/services/notifications.dart` over `dev.herdr.herdr_mobile/badge`, "set", with
    // an integer count; zero clears the badge.
    guard let badgeRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "BadgeChannel") else {
      return
    }
    let badgeChannel = FlutterMethodChannel(
      name: "dev.herdr.herdr_mobile/badge",
      binaryMessenger: badgeRegistrar.messenger()
    )
    badgeChannel.setMethodCallHandler { call, result in
      guard call.method == "set", let count = call.arguments as? Int else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in result(nil) }
      } else {
        UIApplication.shared.applicationIconBadgeNumber = count
        result(nil)
      }
    }
  }
}
