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

  private let flutterDisplayGate = FlutterDisplayGate()
  // The first Flutter page is locked. This also keeps that safe page visible when the
  // system authentication sheet temporarily makes its scene inactive.
  private(set) var appLocked = true

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BiometricLock") {
      let channel = FlutterMethodChannel(
        name: "dev.herdr.herdr_mobile/biometric_lock", binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [self] call, result in
        switch call.method {
        case "setLocked":
          let arguments = call.arguments as? [String: Any]
          appLocked = arguments?["locked"] as? Bool ?? true
          // Do not remove an existing cover until the replacement Flutter frame is ready.
          result(nil)
        case "frameReady":
          for scene in UIApplication.shared.connectedScenes {
            (scene.delegate as? SceneDelegate)?.protectedFrameReady(scene)
          }
          result(nil)
        case "waitUntilDisplayed":
          flutterDisplayGate.wait(
            for: registrar.viewController as? FlutterViewController, result: result
          )
        default:
          result(FlutterMethodNotImplemented)
        }
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

/// Rasterization can finish while Flutter's native launch view is still fading out.
/// Flutter 3.47 emits this KVO change only after the splash-removal completion. Observing
/// it leaves the engine's single first-render callback available to its existing owner.
final class FlutterDisplayGate {
  private weak var observedController: FlutterViewController?
  private var observation: NSKeyValueObservation?
  private var pending: [FlutterResult] = []

  func wait(for controller: FlutterViewController?, result: @escaping FlutterResult) {
    guard let controller = controller else {
      let error = FlutterError(
        code: "flutter_view_unavailable", message: "Flutter view is unavailable.", details: nil
      )
      complete(error)
      result(error)
      return
    }
    if !pending.isEmpty && observedController !== controller {
      complete(FlutterError(
        code: "flutter_view_changed", message: "Flutter view changed before display.", details: nil
      ))
    }
    if controller.isDisplayingFlutterUI {
      result(nil)
      return
    }
    pending.append(result)
    guard observation == nil else { return }
    observedController = controller
    observation = controller.observe(\.isDisplayingFlutterUI, options: [.new]) {
      [weak self] observed, _ in
      if observed.isDisplayingFlutterUI { self?.complete(nil) }
    }
    // Do not miss a completion between the initial read and observation registration.
    if controller.isDisplayingFlutterUI { complete(nil) }
  }

  private func complete(_ result: Any?) {
    observation?.invalidate()
    observation = nil
    observedController = nil
    let callbacks = pending
    pending.removeAll()
    for callback in callbacks { callback(result) }
  }
}
