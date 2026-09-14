import Flutter
import UIKit

/// The native iOS handler for **Reduce Transparency**
/// (`docs/33-platform-chrome.md` R-33-051, `docs/90-implementation-plan.md` Phase 22):
/// answers `isReduceTransparencyEnabled` over the `herdr_mobile/chrome_reduce_transparency`
/// method channel with `UIAccessibility.isReduceTransparencyEnabled`, and pushes a
/// `reduceTransparencyChanged` call to Dart whenever
/// `UIAccessibility.reduceTransparencyStatusDidChangeNotification` fires, so the app's opaque
/// chrome variant (R-33-068) takes effect without a restart. Flutter's own `MediaQueryData`
/// exposes no reduce-transparency field, which is why this channel exists at all — R-33-051's
/// own words.
///
/// Registered once, from `AppDelegate.didInitializeImplicitFlutterEngine`, mirroring the
/// `AppSettingsChannel` registration already there.
final class ChromeReduceTransparencyChannel: NSObject {
  private let channel: FlutterMethodChannel

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  /// Creates the channel, wires its method handler, and starts observing the system
  /// notification. Returns the instance so its owner (`AppDelegate`) can keep it alive for the
  /// life of the app; `NotificationCenter` holds only a weak-by-convention observer reference,
  /// so a caller that drops this value would silently stop receiving change notifications.
  @discardableResult
  static func register(with registrar: FlutterPluginRegistrar) -> ChromeReduceTransparencyChannel {
    let channel = FlutterMethodChannel(
      name: "herdr_mobile/chrome_reduce_transparency",
      binaryMessenger: registrar.messenger()
    )
    let instance = ChromeReduceTransparencyChannel(channel: channel)
    channel.setMethodCallHandler { call, result in
      guard call.method == "isReduceTransparencyEnabled" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(UIAccessibility.isReduceTransparencyEnabled)
    }
    NotificationCenter.default.addObserver(
      instance,
      selector: #selector(reduceTransparencyStatusDidChange),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil
    )
    return instance
  }

  @objc private func reduceTransparencyStatusDidChange() {
    channel.invokeMethod(
      "reduceTransparencyChanged",
      arguments: UIAccessibility.isReduceTransparencyEnabled
    )
  }
}
