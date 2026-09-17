import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let privacyShield = ScenePrivacyShield()

  override func sceneWillResignActive(_ scene: UIScene) {
    let locked = (UIApplication.shared.delegate as? AppDelegate)?.appLocked ?? true
    // Cover before Flutter's lifecycle callback: UIKit can capture the task image before
    // Dart paints again. A locked page is already safe and stays behind the Face ID prompt.
    privacyShield.willResignActive(in: window, locked: locked)
    super.sceneWillResignActive(scene)
  }

  func protectedFrameReady(_ scene: UIScene) {
    privacyShield.frameReady(isActive: scene.activationState == .foregroundActive)
  }
}

/// Keeps the last sensitive frame out of UIKit's task snapshot. Resuming alone does not
/// remove the cover: Flutter first replaces that frame with the lock page or unlocked UI.
final class ScenePrivacyShield {
  private var cover: UIView?

  func willResignActive(in window: UIWindow?, locked: Bool) {
    guard !locked, let window = window else { return }
    if let cover = cover {
      window.bringSubviewToFront(cover)
      return
    }
    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = .systemBackground
    cover.isOpaque = true
    cover.isUserInteractionEnabled = true
    cover.accessibilityViewIsModal = true
    cover.isAccessibilityElement = true
    cover.accessibilityLabel = "Herdr Remote"
    window.addSubview(cover)
    self.cover = cover
  }

  func frameReady(isActive: Bool) {
    guard isActive else { return }
    cover?.removeFromSuperview()
    cover = nil
  }
}
