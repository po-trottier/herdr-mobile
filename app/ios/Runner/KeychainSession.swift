import Foundation
import LocalAuthentication
import Security

/// WP-13-a: read existing flutter_secure_storage items with one session's LAContext.
/// The device-key read remains the OS-enforced gate. Host reads cannot display UI,
/// including records that older builds wrote with biometric access controls.
final class KeychainSession {
  typealias CopyMatching = ([CFString: Any]) -> (OSStatus, Data?)
  private let copyMatching: CopyMatching
  private let lock = NSLock()
  private var context: LAContext?
  private var pendingContext: LAContext?
  private var currentGeneration = 0

  init(copyMatching: @escaping CopyMatching = { query in
    var value: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &value)
    return (status, value as? Data)
  }) {
    self.copyMatching = copyMatching
  }

  var generation: Int {
    lock.lock()
    defer { lock.unlock() }
    return currentGeneration
  }

  func invalidate() {
    lock.lock()
    defer { lock.unlock() }
    context?.invalidate()
    pendingContext?.invalidate()
    context = nil
    pendingContext = nil
    currentGeneration += 1
  }

  /// Called on the channel's serial background queue. Invalidation may interrupt a read.
  func read(key: String, generation: Int) -> (OSStatus, String?) {
    let authenticating = key == "device_x25519_private_key"
    guard authenticating || ["host_static_public_key_", "host_routing_handle_",
                            "host_relay_origin_"].contains(where: { key.hasPrefix($0) }) else {
      return (errSecParam, nil)
    }
    lock.lock()
    guard generation == currentGeneration else {
      lock.unlock()
      return (errSecUserCanceled, nil)
    }
    let active: LAContext
    if authenticating {
      pendingContext?.invalidate()
      active = LAContext()
      active.localizedReason = "Unlock to continue"
      pendingContext = active
    } else {
      active = context ?? LAContext()
      active.interactionNotAllowed = true
    }
    lock.unlock()

    // Match the plugin's existing account, service and accessibility class. Access control
    // is enforced by the stored item; do not put write-only access-control flags in a read.
    let (status, data) = copyMatching([
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: "flutter_secure_storage_service",
      kSecAttrAccount: key,
      kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecAttrSynchronizable: false,
      kSecMatchLimit: kSecMatchLimitOne,
      kSecReturnData: true,
      kSecUseAuthenticationContext: active,
    ])

    lock.lock()
    defer { lock.unlock() }
    guard generation == currentGeneration else { return (errSecUserCanceled, nil) }
    active.interactionNotAllowed = true
    if authenticating { pendingContext = nil }
    if status != errSecSuccess {
      if authenticating {
        active.invalidate()
        if status == errSecItemNotFound {
          context?.invalidate()
          context = nil
        }
      }
      return (status == errSecItemNotFound ? errSecSuccess : status, nil)
    }
    guard let data = data, let value = String(data: data, encoding: .utf8) else {
      if authenticating { active.invalidate() }
      return (errSecDecode, nil)
    }
    if authenticating {
      context?.invalidate()
      context = active
    }
    return (errSecSuccess, value)
  }
}
