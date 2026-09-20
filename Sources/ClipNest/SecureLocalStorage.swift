import CryptoKit
import Foundation
import Security

enum SecureLocalStorageError: LocalizedError {
  case invalidKey
  case invalidEnvelope
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidKey:
      L10n.text(
        "storage.error.invalid_key", fallback: "The local encryption key is invalid.")
    case .invalidEnvelope:
      L10n.text(
        "storage.error.invalid_envelope",
        fallback: "The local encrypted data is damaged or cannot be unlocked."
      )
    case .keychain(let status):
      L10n.format(
        "storage.error.keychain",
        fallback: "The macOS Keychain could not provide ClipNest's local encryption key (%d).",
        status
      )
    }
  }
}

/// Encrypts ClipNest's live local store. The recognizable prefix lets us migrate legacy plaintext
/// files without ever guessing whether damaged ciphertext is plaintext.
struct SecureLocalStorage: Sendable {
  private static let envelopePrefix = Data("CLIPNEST-SEALED\u{0}\u{1}".utf8)
  private let key: SymmetricKey

  init(keyData: Data) throws {
    guard keyData.count == 32 else { throw SecureLocalStorageError.invalidKey }
    key = SymmetricKey(data: keyData)
  }

  static func production() throws -> SecureLocalStorage {
    try SecureLocalStorage(keyData: LocalStorageKeychain.loadOrCreateKey())
  }

  func seal(_ plaintext: Data) throws -> Data {
    let box = try AES.GCM.seal(plaintext, using: key)
    guard let combined = box.combined else { throw SecureLocalStorageError.invalidEnvelope }
    var envelope = Self.envelopePrefix
    envelope.append(combined)
    return envelope
  }

  func open(_ storedData: Data) throws -> (data: Data, wasPlaintext: Bool) {
    guard storedData.starts(with: Self.envelopePrefix) else {
      return (storedData, true)
    }
    let combined = storedData.dropFirst(Self.envelopePrefix.count)
    guard !combined.isEmpty else { throw SecureLocalStorageError.invalidEnvelope }
    do {
      let box = try AES.GCM.SealedBox(combined: combined)
      return (try AES.GCM.open(box, using: key), false)
    } catch {
      throw SecureLocalStorageError.invalidEnvelope
    }
  }

  static func isEncrypted(_ data: Data) -> Bool {
    data.starts(with: envelopePrefix)
  }

  /// Reads only the fixed envelope header. Payload authentication still happens in `open(_:)`
  /// when the attachment is actually used; startup migration does not need to load every image.
  static func fileHasEncryptedEnvelope(at url: URL) throws -> Bool {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let header = try handle.read(upToCount: envelopePrefix.count) ?? Data()
    return header == envelopePrefix
  }
}

private enum LocalStorageKeychain {
  private static let service = "app.clipnest.ClipNest.secure-local-storage"
  private static let account = "primary"

  static func loadOrCreateKey() throws -> Data {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess {
      guard let data = result as? Data, data.count == 32 else {
        throw SecureLocalStorageError.invalidKey
      }
      return data
    }
    guard status == errSecItemNotFound else {
      throw SecureLocalStorageError.keychain(status)
    }

    var bytes = Data(count: 32)
    let randomStatus = bytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard randomStatus == errSecSuccess else {
      throw SecureLocalStorageError.keychain(randomStatus)
    }

    var add = baseQuery
    add[kSecValueData as String] = bytes
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    if addStatus == errSecDuplicateItem {
      return try loadOrCreateKey()
    }
    guard addStatus == errSecSuccess else {
      throw SecureLocalStorageError.keychain(addStatus)
    }
    return bytes
  }

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
