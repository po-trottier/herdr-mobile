import Flutter
import UIKit
import XCTest
@testable import Runner

@MainActor
final class RunnerTests: XCTestCase {
  func testDisplayWaitersCompleteTogetherOnlyAfterNativeSplashCompletion() {
    let controller = DisplayFixtureController(project: nil, nibName: nil, bundle: nil)
    let gate = FlutterDisplayGate()
    var replies: [Any?] = []
    gate.wait(for: controller) { replies.append($0) }
    gate.wait(for: controller) { replies.append($0) }
    XCTAssertTrue(replies.isEmpty)

    controller.setDisplayed(false)
    XCTAssertTrue(replies.isEmpty)
    controller.setDisplayed(true)
    XCTAssertEqual(replies.count, 2)
    XCTAssertTrue(replies.allSatisfy { $0 == nil })
    controller.setDisplayed(false)
    controller.setDisplayed(true)
    XCTAssertEqual(replies.count, 2, "Each channel request completes exactly once.")
  }

  func testAlreadyDisplayedFlutterViewDoesNotWaitForAnotherFrame() {
    let controller = DisplayFixtureController(project: nil, nibName: nil, bundle: nil)
    controller.setDisplayed(true)
    let gate = FlutterDisplayGate()
    var completed = false
    gate.wait(for: controller) {
      XCTAssertNil($0)
      completed = true
    }
    XCTAssertTrue(completed)
  }

  func testUnavailableFlutterViewFailsClosed() {
    let gate = FlutterDisplayGate()
    var failure: FlutterError?
    gate.wait(for: nil) { failure = $0 as? FlutterError }
    XCTAssertEqual(failure?.code, "flutter_view_unavailable")
  }

  func testReplacingTheFlutterViewCannotReleaseItsOldDisplayWaiters() {
    let old = DisplayFixtureController(project: nil, nibName: nil, bundle: nil)
    let current = DisplayFixtureController(project: nil, nibName: nil, bundle: nil)
    let gate = FlutterDisplayGate()
    var oldFailure: FlutterError?
    var completed = false
    gate.wait(for: old) { oldFailure = $0 as? FlutterError }
    gate.wait(for: current) {
      XCTAssertNil($0)
      completed = true
    }
    XCTAssertEqual(oldFailure?.code, "flutter_view_changed")
    old.setDisplayed(true)
    XCTAssertFalse(completed)
    current.setDisplayed(true)
    XCTAssertTrue(completed)
  }

  func testInactiveUnlockedContentHasAnOpaqueCover() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let content = UILabel(frame: window.bounds)
    content.text = "Synthetic terminal fixture"
    window.addSubview(content)
    let shield = ScenePrivacyShield()

    shield.willResignActive(in: window, locked: false)

    let cover = try XCTUnwrap(window.subviews.last)
    XCTAssertFalse(cover === content)
    XCTAssertEqual(cover.frame, window.bounds)
    XCTAssertTrue(cover.isOpaque)
    XCTAssertEqual(cover.alpha, 1)
    XCTAssertEqual(cover.backgroundColor?.cgColor.alpha, 1)
    XCTAssertTrue(cover.isUserInteractionEnabled)
    XCTAssertTrue(cover.accessibilityViewIsModal)
    XCTAssertTrue(cover.isAccessibilityElement)
    XCTAssertFalse(cover is UIImageView)
  }

  func testLockedFaceIDPageStaysVisibleWhenAuthenticationMakesSceneInactive() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let lockPage = UIView(frame: window.bounds)
    window.addSubview(lockPage)
    let shield = ScenePrivacyShield()

    shield.willResignActive(in: window, locked: true)

    XCTAssertEqual(window.subviews, [lockPage])
  }

  func testCoverCannotLeaveUntilProtectedFrameIsReadyInActiveScene() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let content = UIView(frame: window.bounds)
    window.addSubview(content)
    let shield = ScenePrivacyShield()
    shield.willResignActive(in: window, locked: false)

    // A delayed frame callback while still backgrounded must not uncover the snapshot.
    shield.frameReady(isActive: false)
    XCTAssertEqual(window.subviews.count, 2)
    // Locking during resume also must not expose the old frame before Flutter replaces it.
    shield.willResignActive(in: window, locked: true)
    XCTAssertEqual(window.subviews.count, 2)

    shield.frameReady(isActive: true)
    XCTAssertEqual(window.subviews, [content])
  }

  func testRepeatedInactiveEventsKeepOneCoverAcrossWindowResize() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    let shield = ScenePrivacyShield()
    shield.willResignActive(in: window, locked: false)
    let cover = try XCTUnwrap(window.subviews.last)
    shield.willResignActive(in: window, locked: false)
    XCTAssertEqual(window.subviews.count, 1)

    window.frame = CGRect(x: 0, y: 0, width: 640, height: 320)
    window.layoutIfNeeded()
    XCTAssertEqual(cover.frame, window.bounds)
    shield.frameReady(isActive: true)
    XCTAssertTrue(window.subviews.isEmpty)
  }
}

/// Controls only the native display-completion boundary. No view is loaded, no Flutter
/// entrypoint runs, and no real biometric, pairing, or device data is read.
private final class DisplayFixtureController: FlutterViewController {
  private var displayed = false
  override var isDisplayingFlutterUI: Bool { displayed }

  func setDisplayed(_ value: Bool) {
    willChangeValue(forKey: "displayingFlutterUI")
    displayed = value
    didChangeValue(forKey: "displayingFlutterUI")
  }
}
