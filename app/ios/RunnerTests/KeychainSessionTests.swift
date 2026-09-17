import LocalAuthentication
import Security
import XCTest
@testable import Runner

final class KeychainSessionTests: XCTestCase {
  private let deviceKey = "device_x25519_private_key"

  #if targetEnvironment(simulator)
  func testRealKeychainReadsLegacyProtectedRecordsAfterOneUnlock() throws {
    // A separate service contains only synthetic fixtures. Never read or modify real pairings.
    let service = "herdr.faceid.regression." + UUID().uuidString
    let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
    defer { SecItemDelete(base as CFDictionary) }
    var error: Unmanaged<CFError>?
    let access = try XCTUnwrap(SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      [.biometryCurrentSet, .devicePasscode, .or], &error))
    let keys = [deviceKey, "host_static_public_key_test", "host_routing_handle_test",
                "host_relay_origin_test"]
    for key in keys {
      var item = base
      item[kSecAttrAccount] = key
      item[kSecAttrAccessControl] = access
      item[kSecValueData] = Data("fixture".utf8)
      let status = SecItemAdd(item as CFDictionary, nil)
      if status != errSecSuccess {
        throw XCTSkip("Simulator cannot create biometric Keychain items (OSStatus \(status)).")
      }
    }
    let finished = expectation(description: "one unlock reads every legacy item")
    var interactiveReads = 0
    let session = KeychainSession { query in
      var scoped = query
      scoped[kSecAttrService] = service
      if !(query[kSecUseAuthenticationContext] as! LAContext).interactionNotAllowed {
        interactiveReads += 1
      }
      var value: CFTypeRef?
      let status = SecItemCopyMatching(scoped as CFDictionary, &value)
      return (status, value as? Data)
    }
    defer { session.invalidate() }
    DispatchQueue.global().async {
      for key in keys {
        let result = session.read(key: key, generation: session.generation)
        XCTAssertEqual(result.0, errSecSuccess)
        XCTAssertEqual(result.1, "fixture")
      }
      finished.fulfill()
    }
    wait(for: [finished], timeout: 30)
    XCTAssertEqual(interactiveReads, 1)
  }
  #endif

  func testLegacyHostReadsReuseTheUnlockContextWithoutMorePrompts() {
    var authenticated: LAContext?
    var prompts = 0
    let session = KeychainSession { query in
      let context = query[kSecUseAuthenticationContext] as! LAContext
      XCTAssertEqual(query[kSecAttrService] as? String, "flutter_secure_storage_service")
      XCTAssertEqual(query[kSecAttrAccessible] as? String,
                     kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
      if context !== authenticated {
        guard !context.interactionNotAllowed else { return (errSecInteractionNotAllowed, nil) }
        prompts += 1
        authenticated = context
      } else {
        XCTAssertTrue(context.interactionNotAllowed)
      }
      return (errSecSuccess, Data("stored-value".utf8))
    }
    XCTAssertEqual(session.read(key: deviceKey, generation: session.generation).1, "stored-value")
    for key in ["host_static_public_key_test", "host_routing_handle_test", "host_relay_origin_test"] {
      XCTAssertEqual(session.read(key: key, generation: session.generation).1, "stored-value")
    }
    XCTAssertEqual(prompts, 1)
    session.invalidate()
    XCTAssertEqual(session.read(key: "host_routing_handle_test", generation: session.generation).0,
                   errSecInteractionNotAllowed)
    XCTAssertEqual(prompts, 1)
    XCTAssertEqual(session.read(key: deviceKey, generation: session.generation).0, errSecSuccess)
    XCTAssertEqual(prompts, 2)
  }

  func testCancelledReauthenticationPreservesTheUnlockedSession() {
    var authenticated: LAContext?
    var attempts = 0
    let session = KeychainSession { query in
      let context = query[kSecUseAuthenticationContext] as! LAContext
      if !context.interactionNotAllowed {
        attempts += 1
        if attempts == 2 { return (errSecUserCanceled, nil) }
        authenticated = context
      } else if context !== authenticated {
        return (errSecInteractionNotAllowed, nil)
      }
      return (errSecSuccess, Data("fixture".utf8))
    }
    XCTAssertEqual(session.read(key: deviceKey, generation: session.generation).0, errSecSuccess)
    XCTAssertEqual(session.read(key: deviceKey, generation: session.generation).0, errSecUserCanceled)
    XCTAssertEqual(session.read(key: "host_routing_handle_test", generation: session.generation).1,
                   "fixture")
    XCTAssertEqual(attempts, 2)
  }

  func testExplicitAuthenticationUsesAFreshContext() {
    var contexts: [LAContext] = []
    let session = KeychainSession { query in
      let context = query[kSecUseAuthenticationContext] as! LAContext
      XCTAssertFalse(context.interactionNotAllowed)
      contexts.append(context)
      return (errSecSuccess, Data("seed".utf8))
    }
    _ = session.read(key: deviceKey, generation: session.generation)
    _ = session.read(key: deviceKey, generation: session.generation)
    XCTAssertFalse(contexts[0] === contexts[1])
  }

  func testQueuedReadCannotStartAfterLock() {
    var reads = 0
    let session = KeychainSession { _ in reads += 1; return (errSecSuccess, Data()) }
    let generation = session.generation
    session.invalidate()
    XCTAssertEqual(session.read(key: deviceKey, generation: generation).0, errSecUserCanceled)
    XCTAssertEqual(reads, 0)
  }

  func testInFlightReadCannotReturnDataAfterLock() {
    var session: KeychainSession!
    session = KeychainSession { _ in
      session.invalidate()
      return (errSecSuccess, Data("seed".utf8))
    }
    let result = session.read(key: deviceKey, generation: session.generation)
    XCTAssertEqual(result.0, errSecUserCanceled)
    XCTAssertNil(result.1)
  }

  func testFailedAuthenticationDiscardsContextAndDoesNotRetry() {
    var contexts: [LAContext] = []
    let session = KeychainSession { query in
      contexts.append(query[kSecUseAuthenticationContext] as! LAContext)
      return (errSecUserCanceled, nil)
    }
    XCTAssertEqual(session.read(key: deviceKey, generation: session.generation).0, errSecUserCanceled)
    XCTAssertEqual(contexts.count, 1)
    _ = session.read(key: "host_relay_origin_test", generation: session.generation)
    XCTAssertTrue(contexts[1].interactionNotAllowed)
    XCTAssertFalse(contexts[0] === contexts[1])
  }

  func testMissingItemIsNilAndInvalidDataIsAnError() {
    let missing = KeychainSession { _ in (errSecItemNotFound, nil) }
    let absent = missing.read(key: deviceKey, generation: missing.generation)
    XCTAssertEqual(absent.0, errSecSuccess)
    XCTAssertNil(absent.1)
    let invalid = KeychainSession { _ in (errSecSuccess, Data([0xFF])) }
    XCTAssertEqual(invalid.read(key: deviceKey, generation: invalid.generation).0, errSecDecode)
  }

  func testOnlyTheDeviceKeyMayPresentAuthentication() {
    var reads = 0
    let session = KeychainSession { query in
      reads += 1
      XCTAssertTrue((query[kSecUseAuthenticationContext] as! LAContext).interactionNotAllowed)
      return (errSecSuccess, Data("origin".utf8))
    }
    XCTAssertEqual(session.read(key: "host_relay_origin_test", generation: session.generation).1,
                   "origin")
    XCTAssertEqual(session.read(key: "unrelated_key", generation: session.generation).0, errSecParam)
    XCTAssertEqual(reads, 1)
  }
}
