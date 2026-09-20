import Foundation
import Security

struct CommercialReleaseConfiguration: Equatable, Sendable {
  enum Field: String, Equatable, Sendable {
    case providerIdentifier
    case productIdentifier
    case checkoutURL
    case supportEmail
    case privacyPolicyURL
    case termsURL
    case refundPolicyURL
  }

  enum ValidationError: Error, Equatable, Sendable {
    case missing(Field)
    case tooLong(Field)
    case invalidHTTPSURL(Field)
    case invalidSupportEmail
    case invalidDeviceAllowance(Int)
  }

  let providerIdentifier: String
  let productIdentifier: String
  let checkoutURL: URL
  let supportEmail: String
  let privacyPolicyURL: URL
  let termsURL: URL
  let refundPolicyURL: URL
  let deviceAllowance: Int
  let policy: CommercialAccessPolicy

  init(
    providerIdentifier: String,
    productIdentifier: String,
    checkoutURL: URL,
    supportEmail: String,
    privacyPolicyURL: URL,
    termsURL: URL,
    refundPolicyURL: URL,
    deviceAllowance: Int,
    policy: CommercialAccessPolicy = CommercialAccessPolicy()
  ) throws {
    self.providerIdentifier = try Self.validatedIdentifier(
      providerIdentifier,
      field: .providerIdentifier
    )
    self.productIdentifier = try Self.validatedIdentifier(
      productIdentifier,
      field: .productIdentifier
    )
    self.checkoutURL = try Self.validatedHTTPSURL(checkoutURL, field: .checkoutURL)
    self.supportEmail = try Self.validatedSupportEmail(supportEmail)
    self.privacyPolicyURL = try Self.validatedHTTPSURL(
      privacyPolicyURL,
      field: .privacyPolicyURL
    )
    self.termsURL = try Self.validatedHTTPSURL(termsURL, field: .termsURL)
    self.refundPolicyURL = try Self.validatedHTTPSURL(
      refundPolicyURL,
      field: .refundPolicyURL
    )
    guard (1...10).contains(deviceAllowance) else {
      throw ValidationError.invalidDeviceAllowance(deviceAllowance)
    }
    self.deviceAllowance = deviceAllowance
    self.policy = policy
  }

  private static func validatedIdentifier(_ value: String, field: Field) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { throw ValidationError.missing(field) }
    guard normalized.count <= 256 else { throw ValidationError.tooLong(field) }
    return normalized
  }

  private static func validatedHTTPSURL(_ url: URL, field: Field) throws -> URL {
    guard url.absoluteString.count <= 2_048 else { throw ValidationError.tooLong(field) }
    guard
      url.scheme?.lowercased() == "https",
      url.host?.isEmpty == false,
      url.user == nil,
      url.password == nil,
      url.fragment == nil
    else { throw ValidationError.invalidHTTPSURL(field) }
    return url
  }

  private static func validatedSupportEmail(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { throw ValidationError.missing(.supportEmail) }
    guard normalized.count <= 254 else { throw ValidationError.tooLong(.supportEmail) }
    let parts = normalized.split(separator: "@", omittingEmptySubsequences: false)
    guard
      parts.count == 2,
      !parts[0].isEmpty,
      parts[1].contains("."),
      !normalized.contains(where: \.isWhitespace)
    else { throw ValidationError.invalidSupportEmail }
    return normalized
  }
}

struct CommercialAccessPolicy: Equatable, Sendable {
  let trialDays: Int
  let offlineGraceDays: Int
  let clockRollbackTolerance: TimeInterval

  init(
    trialDays: Int = 14,
    offlineGraceDays: Int = 7,
    clockRollbackTolerance: TimeInterval = 5 * 60
  ) {
    self.trialDays = max(1, min(trialDays, 60))
    self.offlineGraceDays = max(0, min(offlineGraceDays, 30))
    self.clockRollbackTolerance = max(0, min(clockRollbackTolerance, 24 * 60 * 60))
  }
}

struct VerifiedCommercialEntitlement: Codable, Equatable, Sendable {
  let licenseID: String
  let verifiedAt: Date
  let nextOnlineVerificationAt: Date
  let isRevoked: Bool

  init(
    licenseID: String,
    verifiedAt: Date,
    nextOnlineVerificationAt: Date,
    isRevoked: Bool = false
  ) {
    self.licenseID = String(licenseID.prefix(256))
    self.verifiedAt = verifiedAt
    self.nextOnlineVerificationAt = max(nextOnlineVerificationAt, verifiedAt)
    self.isRevoked = isRevoked
  }
}

struct CommercialAccessRecord: Codable, Equatable, Sendable {
  let installationID: UUID
  let trialStartedAt: Date
  var lastObservedAt: Date
  var entitlement: VerifiedCommercialEntitlement?

  init(
    installationID: UUID = UUID(),
    trialStartedAt: Date,
    lastObservedAt: Date? = nil,
    entitlement: VerifiedCommercialEntitlement? = nil
  ) {
    self.installationID = installationID
    self.trialStartedAt = trialStartedAt
    self.lastObservedAt = max(lastObservedAt ?? trialStartedAt, trialStartedAt)
    self.entitlement = entitlement
  }

  mutating func observe(_ date: Date) {
    lastObservedAt = max(lastObservedAt, date)
  }
}

enum CommercialAccessState: Equatable, Sendable {
  case unmanaged
  case trial(expiresAt: Date, daysRemaining: Int)
  case licensed(nextVerificationAt: Date)
  case offlineGrace(expiresAt: Date, daysRemaining: Int)
  case needsOnlineVerification
  case expired
}

enum CommercialAccessEvaluator {
  static func evaluate(
    configuration: CommercialReleaseConfiguration?,
    record: CommercialAccessRecord?,
    now: Date
  ) -> CommercialAccessState {
    guard let configuration else { return .unmanaged }
    guard let record else { return .expired }
    let policy = configuration.policy

    if now.addingTimeInterval(policy.clockRollbackTolerance) < record.lastObservedAt {
      return .needsOnlineVerification
    }

    if let entitlement = record.entitlement {
      guard !entitlement.isRevoked else { return .expired }
      if now <= entitlement.nextOnlineVerificationAt {
        return .licensed(nextVerificationAt: entitlement.nextOnlineVerificationAt)
      }
      let graceEnd = Calendar(identifier: .gregorian).date(
        byAdding: .day,
        value: policy.offlineGraceDays,
        to: entitlement.nextOnlineVerificationAt
      ) ?? entitlement.nextOnlineVerificationAt
      if now <= graceEnd {
        return .offlineGrace(
          expiresAt: graceEnd,
          daysRemaining: remainingDays(until: graceEnd, now: now)
        )
      }
      return .needsOnlineVerification
    }

    let trialEnd = Calendar(identifier: .gregorian).date(
      byAdding: .day,
      value: policy.trialDays,
      to: record.trialStartedAt
    ) ?? record.trialStartedAt
    guard now < trialEnd else { return .expired }
    return .trial(
      expiresAt: trialEnd,
      daysRemaining: remainingDays(until: trialEnd, now: now)
    )
  }

  private static func remainingDays(until end: Date, now: Date) -> Int {
    max(1, Int(ceil(end.timeIntervalSince(now) / (24 * 60 * 60))))
  }
}

enum CommercialAccessStoreError: Error, Equatable {
  case keychain(OSStatus)
  case invalidRecord
}

protocol CommercialAccessRecordStore: Sendable {
  func load() throws -> CommercialAccessRecord?
  func save(_ record: CommercialAccessRecord) throws
  func delete() throws
}

struct KeychainCommercialAccessRecordStore: CommercialAccessRecordStore {
  private let service: String
  private let account: String

  init(
    service: String = "app.clipnest.ClipNest.commercial-access",
    account: String = "primary"
  ) {
    self.service = service
    self.account = account
  }

  func load() throws -> CommercialAccessRecord? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw CommercialAccessStoreError.keychain(status) }
    guard let data = result as? Data,
      let record = try? JSONDecoder().decode(CommercialAccessRecord.self, from: data)
    else { throw CommercialAccessStoreError.invalidRecord }
    return record
  }

  func save(_ record: CommercialAccessRecord) throws {
    let data = try JSONEncoder().encode(record)
    let updateStatus = SecItemUpdate(
      baseQuery as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw CommercialAccessStoreError.keychain(updateStatus)
    }
    var add = baseQuery
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw CommercialAccessStoreError.keychain(addStatus)
    }
  }

  func delete() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CommercialAccessStoreError.keychain(status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
