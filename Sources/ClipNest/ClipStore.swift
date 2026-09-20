import AppKit
import ApplicationServices
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

private final class ImageExportCancellationFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }
}

struct ArchiveImportSummary: Equatable, Sendable {
  let added: Int
  let merged: Int
  let skipped: Int
  let stacked: Int
  let savedViews: Int
  let boards: Int

  init(
    added: Int,
    merged: Int,
    skipped: Int,
    stacked: Int = 0,
    savedViews: Int = 0,
    boards: Int = 0
  ) {
    self.added = added
    self.merged = merged
    self.skipped = skipped
    self.stacked = stacked
    self.savedViews = savedViews
    self.boards = boards
  }
}

enum EditedClipResult: Equatable, Sendable {
  case created(UUID)
  case reused(UUID)
  case empty
  case unchanged
  case tooLarge

  var succeededID: UUID? {
    switch self {
    case .created(let id), .reused(let id): id
    case .empty, .unchanged, .tooLarge: nil
    }
  }

  var errorMessage: String? {
    switch self {
    case .created, .reused: nil
    case .empty:
      L10n.text("edit_clip.error_empty", fallback: "Enter some text before saving the edited copy.")
    case .unchanged:
      L10n.text(
        "edit_clip.error_unchanged", fallback: "Make a change before creating an edited copy.")
    case .tooLarge:
      L10n.text("edit_clip.too_large", fallback: "Keep edited text under 2 MB.")
    }
  }
}

enum SnippetCreationResult: Equatable, Sendable {
  case created(UUID)
  case reused(UUID)
  case empty
  case tooLarge
  case invalid(String)

  var succeededID: UUID? {
    switch self {
    case .created(let id), .reused(let id): id
    case .empty, .tooLarge, .invalid: nil
    }
  }

  var errorMessage: String? {
    switch self {
    case .created, .reused:
      nil
    case .empty:
      L10n.text("new_snippet.error_empty", fallback: "Enter snippet content before saving.")
    case .tooLarge:
      L10n.text("edit_clip.too_large", fallback: "Keep edited text under 2 MB.")
    case .invalid(let message):
      message
    }
  }
}

enum FileReferenceRelinkResult: Equatable, Sendable {
  case relinked
  case itemUnavailable
  case originalAvailable
  case replacementUnavailable
  case duplicatePath
  case duplicateGroup

  var message: String {
    switch self {
    case .relinked:
      L10n.text("notice.file_relinked", fallback: "File reference updated")
    case .itemUnavailable:
      L10n.text(
        "notice.file_relink_item_missing",
        fallback: "This file group is no longer available."
      )
    case .originalAvailable:
      L10n.text(
        "notice.file_relink_original_available",
        fallback: "The original file is available again; no update is needed."
      )
    case .replacementUnavailable:
      L10n.text(
        "notice.file_relink_replacement_missing",
        fallback: "Choose an existing local file or folder."
      )
    case .duplicatePath:
      L10n.text(
        "notice.file_relink_duplicate_path",
        fallback: "That location is already part of this file group."
      )
    case .duplicateGroup:
      L10n.text(
        "notice.file_relink_duplicate_group",
        fallback: "This exact file group already exists in another clip."
      )
    }
  }
}

struct StoreNotice: Equatable, Sendable {
  let message: String
  let systemImage: String
  let action: StoreNoticeAction?
}

enum StoreNoticeAction: Equatable, Sendable {
  case undoDeletion
  case undoStackAdvance
  case undoStackCollection(previousIDs: [UUID])
  case undoBoardCollection(boardID: UUID, addedItemIDs: [UUID])
}

struct StorageIssue: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case persistence
    case recoveredHistory
  }

  let kind: Kind
  let message: String
  let detail: String
  let recoveryFileName: String?
}

enum ScreenshotSnapshotLoadResult: Sendable {
  case success([ScreenshotFileSnapshot])
  case failure
}

enum StoredImageDataLoadResult: Sendable {
  case success(Data)
  case failure(PersistenceWriteError, secureStorageFailure: Bool)
}

enum FileReferenceStatus: Equatable, Sendable {
  case checking
  case available
  case missing
}

enum CachedImageStatus: Equatable, Sendable {
  case unavailable
  case loading
  case available
  case failed
}

struct PersistenceWriteError: LocalizedError, Equatable, Sendable {
  let message: String

  var errorDescription: String? { message }
}

struct ImageImportProgress: Equatable, Sendable {
  let total: Int
  var completed: Int
  var imported: Int
  var duplicates: Int
  var unreadable: Int
  var failed: Int
  var isCancelling: Bool

  var skipped: Int { duplicates + unreadable + failed }
}

struct ImageImportResult: Equatable, Sendable {
  let total: Int
  let completed: Int
  let imported: Int
  let duplicates: Int
  let unreadable: Int
  let failed: Int
  let wasCancelled: Bool

  var skipped: Int { duplicates + unreadable + failed }

  var message: String {
    if wasCancelled {
      return L10n.format(
        "notice.import_cancelled_detailed",
        fallback:
          "Import stopped after %d/%d · %d added · %d duplicates · %d unreadable · %d failed",
        completed,
        total,
        imported,
        duplicates,
        unreadable,
        failed
      )
    }
    if skipped > 0 {
      return L10n.format(
        "notice.import_finished_detailed",
        fallback: "Imported %d · %d duplicates · %d unreadable · %d failed",
        imported,
        duplicates,
        unreadable,
        failed
      )
    }
    return L10n.format(
      "notice.import_finished",
      fallback: "Imported %d screenshots",
      imported
    )
  }

  var systemImage: String {
    wasCancelled
      ? "stop.circle.fill"
      : failed > 0 || unreadable > 0 ? "exclamationmark.triangle.fill" : "photo.stack.fill"
  }
}

struct BulkOCRRetryResult: Equatable, Sendable {
  let scheduled: Int
  let unavailable: Int
}

struct BulkOCRRetryProgress: Equatable, Sendable {
  let total: Int
  var completed: Int
  var recognized: Int
  var noText: Int
  var failed: Int
  let unavailable: Int
  var isCancelling: Bool
}

struct OCRLibrarySummary: Equatable, Sendable {
  let total: Int
  let pending: Int
  let recognized: Int
  let lowConfidence: Int
  let unrated: Int
  let noText: Int
  let failed: Int
  let searchable: Int

  init(items: [ClipItem]) {
    var total = 0
    var pending = 0
    var recognized = 0
    var lowConfidence = 0
    var unrated = 0
    var noText = 0
    var failed = 0
    var searchable = 0

    for item in items where item.kind == .image {
      total += 1
      if item.hasSearchableOCR { searchable += 1 }
      if item.hasLowConfidenceOCR { lowConfidence += 1 }
      if item.hasUnratedOCR { unrated += 1 }
      switch item.ocrState {
      case .pending, .notApplicable: pending += 1
      case .complete: recognized += 1
      case .noText: noText += 1
      case .failed: failed += 1
      }
    }

    self.total = total
    self.pending = pending
    self.recognized = recognized
    self.lowConfidence = lowConfidence
    self.unrated = unrated
    self.noText = noText
    self.failed = failed
    self.searchable = searchable
  }

  var analyzed: Int { max(0, total - pending) }
  var review: Int { lowConfidence + unrated + noText + failed }
  var analyzedFraction: Double {
    guard total > 0 else { return 0 }
    return Double(analyzed) / Double(total)
  }
}

struct SourceApplicationFacet: Identifiable, Equatable, Sendable {
  let name: String
  let bundleIdentifier: String?
  let count: Int

  var id: String {
    bundleIdentifier.map { "bundle:\($0)" }
      ?? "name:\(SearchMatcher.normalize(name))"
  }
}

enum ImageExportResult: Equatable, Sendable {
  case exported
  case cancelled
  case failed(String)
}

@MainActor
final class ClipStore: ObservableObject {
  private struct RecommendationCacheKey: Hashable {
    let limit: Int
    let preferredBoardID: UUID?
  }

  nonisolated static let maximumCustomTitleLength = 120
  nonisolated static let maximumTagCount = 8
  nonisolated static let maximumTagLength = 24
  nonisolated static let maximumStackCount = 20
  nonisolated static let maximumEditedTextBytes = 2_000_000
  nonisolated static let maximumNewSnippetDraftStorageBytes = 8 * 1_024 * 1_024
  nonisolated static let maximumFilesPerClip = 50
  nonisolated static let maximumSynchronousQuickActionBytes = 128 * 1_024

  @Published private(set) var items: [ClipItem] = [] {
    didSet {
      purgeChangedSemanticVectors(previousItems: oldValue, currentItems: items)
      itemRevision &+= 1
      semanticSearchTask?.cancel()
      semanticSearchTask = nil
      semanticSearchTaskKey = nil
      semanticSearchResultKey = nil
      semanticSearchResultIDs.removeAll(keepingCapacity: true)
      semanticSearchResultScores.removeAll(keepingCapacity: true)
      semanticSearchStatus = .inactive
      quickPasteActionTasks.values.forEach { $0.cancel() }
      quickPasteActionTasks.removeAll(keepingCapacity: true)
      quickPasteActionGenerations.removeAll(keepingCapacity: true)
      quickPasteActionCache.removeAll(keepingCapacity: true)
      quickPickerRecommendationCache.removeAll(keepingCapacity: true)
      sourceApplicationFacetsCache = nil
      searchResultsCache = nil
      popularTagsCache = nil
      hasQuickAliasesCache = nil
      stackItemsCache = nil
    }
  }
  @Published var searchText = "" {
    didSet {
      if semanticSearchOrigin?.queryKey != SemanticSearchRequest(searchText)?.cacheKey {
        semanticSearchOrigin = nil
      }
      searchAsLiteral = false
      normalizeSelection()
    }
  }
  @Published private(set) var searchAsLiteral = false
  @Published var filter: ClipFilter = .all {
    didSet { normalizeSelection() }
  }
  @Published var selectedTag: String? {
    didSet { normalizeSelection() }
  }
  @Published var selectedBoardID: UUID? {
    didSet { normalizeSelection() }
  }
  @Published var isMonitoring = true
  @Published private(set) var isSessionActive = true
  @Published var selectedID: UUID?
  @Published private(set) var notice: StoreNotice?
  @Published private(set) var pauseUntil: Date?
  @Published private(set) var canUndoDeletion = false
  @Published private(set) var storageIssue: StorageIssue?
  @Published private(set) var isUnlockingStorage = false
  @Published private(set) var isStorageUnlockTakingLong = false
  @Published private(set) var storageInventory: StorageInventory?
  @Published private(set) var isInspectingStorage = false
  @Published private(set) var isCleaningStorage = false
  @Published private(set) var isIgnoringNextCopy = false
  @Published private(set) var secureCopyExpiration: Date?
  @Published private(set) var stackIDs: [UUID] = [] {
    didSet { stackItemsCache = nil }
  }
  @Published private(set) var savedViews: [SavedClipView] = []
  @Published private(set) var boards: [ClipBoard] = []
  @Published private(set) var privacyRules: [ClipboardPrivacyRule] = []
  @Published private(set) var isWatchingScreenshots = false
  @Published private(set) var screenshotWatchIssue: String?
  @Published private(set) var isRetryingScreenshotWatch = false
  @Published private(set) var isCapturingRegion = false
  @Published private(set) var imageImportProgress: ImageImportProgress?
  @Published private(set) var lastImageImportResult: ImageImportResult?
  @Published private(set) var bulkOCRRetryProgress: BulkOCRRetryProgress?
  @Published private(set) var isExportingImage = false
  @Published private(set) var preparingImageCopyID: UUID?
  @Published private(set) var screenOCRShortcutRegistrationSucceeded = true
  @Published private(set) var snippetShortcutRegistrationSucceeded = true
  @Published private(set) var newSnippetShortcutRegistrationSucceeded = true
  @Published private(set) var textActionShortcutRegistrationSucceeded = true
  @Published private(set) var quickPickerShortcutRegistrationSucceeded = true
  @Published private(set) var imageCacheRevision = 0
  @Published private(set) var quickPasteActionRevision = 0
  @Published private(set) var semanticSearchRevision = 0
  @Published private(set) var fileReferenceRevision = 0
  @Published private(set) var hasPendingNewSnippetDraft = false
  @Published private var fileReferenceAvailability: FileReferenceAvailability?

  private(set) var pendingNewSnippetDraft: NewSnippetDraft?

  let preferences: ClipPreferences

  private let pasteboard: NSPasteboard
  private var lastChangeCount: Int
  private var timer: Timer?
  private var expirationTimer: Timer?
  private var screenshotTimer: Timer?
  private var screenshotPollingTask: Task<Void, Never>?
  private var clipboardImageCaptureTask: Task<Void, Never>?
  private var clipboardImageCaptureGeneration: UUID?
  private var historyPersistenceTask: Task<Void, Never>?
  private var historyPersistenceNeeded = false
  private var historyPersistenceGeneration = 0
  private var historyPersistenceErrorMessage: String?
  private var isApplyingArchiveImport = false
  private var archiveRetainedImageNames = Set<String>()
  private var archiveRetainedRichTextNames = Set<String>()
  private var newSnippetDraftPersistenceTask: Task<Void, Never>?
  private var newSnippetDraftPersistenceNeeded = false
  private var newSnippetDraftPersistenceGeneration = 0
  private var htmlRichTextConversionTasks: [UUID: Task<Void, Never>] = [:]
  private var fileReferenceCheckTask: Task<Void, Never>?
  private var imageLoadTasks: [String: Task<Void, Never>] = [:]
  private var failedImageLoads = Set<String>()
  private var imageImportTask: Task<Void, Never>?
  private var recoverableImageImportURLs: [URL] = []
  private var imageExportTask: Task<ImageExportWorkResult, Never>?
  private var imageExportCancellation: ImageExportCancellationFlag?
  private var imageExportGeneration: UUID?
  private var imageCopyTask: Task<StoredImageDataLoadResult, Never>?
  private var imageCopyGeneration: UUID?
  private var storageInventoryTask: Task<Void, Never>?
  private let fileManager = FileManager.default
  private let rootURL: URL
  private let imagesURL: URL
  private let richTextURL: URL
  private let metadataURL: URL
  private let stackURL: URL
  private let savedViewsURL: URL
  private let boardsURL: URL
  private let privacyRulesURL: URL
  private let newSnippetDraftURL: URL
  private var storageProtector: SecureLocalStorage?
  private let storageProtectorLoader: @Sendable () throws -> SecureLocalStorage
  private var storageUnlockTask: Task<Void, Never>?
  private var storageUnlockWatchdogTask: Task<Void, Never>?
  private let storageUnlockLongWaitDuration: Duration
  private let requiresStorageProtection: Bool
  private var resumeTask: Task<Void, Never>?
  private var secureCopyTask: Task<Void, Never>?
  private var secureCopyGeneration: UUID?
  private var secureCopyExpectedChangeCount: Int?
  private var regionCaptureProcess: Process?
  private var regionCaptureIngestionTask: Task<Void, Never>?
  private var preferenceCancellables = Set<AnyCancellable>()
  private var deletedClips: [DeletedClip] = []
  private var lastConsumedStackEntry: (id: UUID, index: Int)?
  private var persistenceBlockedByUnreadableHistory = false
  private var boardStorageReadable = true
  private var oneShotCaptureGuard = OneShotCaptureGuard()
  private var isCapturingSelectedText = false
  private var contentKindCache: [UUID: ClipContentKind] = [:]
  private var searchIndexCache: [UUID: SearchIndexEntry] = [:]
  private var quickPickerRecommendationCache: [RecommendationCacheKey: RecommendationCacheEntry] =
    [:]
  private var quickPasteActionCache: [UUID: QuickPasteActionCacheEntry] = [:]
  private var quickPasteActionTasks: [UUID: Task<Void, Never>] = [:]
  private var quickPasteActionGenerations: [UUID: UUID] = [:]
  private let quickPasteActionGate = ImageAnalysisGate(maximumConcurrent: 2)
  private let semanticSearchIndex: SemanticSearchIndex
  private var semanticSearchTask: Task<Void, Never>?
  private var semanticSearchTaskKey: SemanticSearchKey?
  private var semanticSearchResultKey: SemanticSearchKey?
  private var semanticSearchResultIDs: [UUID] = []
  private var semanticSearchResultScores: [UUID: Float] = [:]
  private var semanticSearchStatus: SemanticSearchStatus = .inactive
  private var semanticSearchOrigin: SemanticSearchOrigin?
  private var itemRevision = 0
  private var sourceApplicationFacetsCache: [SourceApplicationFacet]?
  private var searchResultsCache: SearchResultsCacheEntry?
  private var popularTagsCache: [String]?
  private var hasQuickAliasesCache: Bool?
  private var stackItemsCache: [ClipItem]?
  private var privacyRegexCache: [UUID: SafeRegexSearch] = [:]
  private let imageDataCache = NSCache<NSString, NSData>()
  private let decodedImageCache = NSCache<NSString, NSImage>()
  private let sourceApplicationIconCache = NSCache<NSString, NSImage>()
  private var missingSourceApplicationIcons = Set<String>()
  private let screenshotDirectoryOverride: URL?
  private let canWatchSystemScreenshots: Bool
  private let screenshotSnapshotLoader: @Sendable (URL) -> ScreenshotSnapshotLoadResult
  private let screenshotImageDataLoader: @Sendable (URL) -> Data?
  private let clipboardImageNormalizer: @Sendable (Data) -> Data?
  private let clipboardImageWriter:
    @Sendable (Data, URL, SecureLocalStorage?, Bool) -> PersistenceWriteError?
  private let storedImageDataLoader:
    @Sendable (URL, SecureLocalStorage?, Bool) -> StoredImageDataLoadResult
  private let persistsHistoryInBackground: Bool
  private let historyMetadataWriter:
    @Sendable ([ClipItem], URL, SecureLocalStorage?, Bool) -> PersistenceWriteError?
  private let fileReferenceChecker: @Sendable ([String]) -> Set<String>
  private let captureFeedbackPlayer: @MainActor @Sendable () -> Void
  private let imageAnalyzer: @Sendable (Data, [String], [String]) async -> ImageAnalysisResult
  private let imageAnalysisGate = ImageAnalysisGate(maximumConcurrent: 2)
  private var scheduledImageAnalysisIDs = Set<UUID>()
  private var imageAnalysisCallbacks: [UUID: [(ImageAnalysisResult) -> Void]] = [:]
  private var imageAnalysisTasks: [UUID: Task<Void, Never>] = [:]
  private var imageAnalysisGenerations: [UUID: UUID] = [:]
  private var pendingRecoveryImageIDs: [UUID] = []
  private var activeRecoveryImageIDs = Set<UUID>()
  private var recoveryImageLoadTasks: [UUID: Task<Void, Never>] = [:]
  private var recoveryImageLoadGenerations: [UUID: UUID] = [:]
  private var bulkOCRRetrySnapshots: [UUID: BulkOCRRetrySnapshot] = [:]
  private var screenshotWatchingStartedAt = Date.distantFuture
  private var watchedScreenshotDirectory: URL?
  private var seenScreenshotIdentities = Set<String>()
  private var pendingClipboardImages: [PendingClipboardImage] = []

  private struct PendingClipboardImage: Sendable {
    let data: Data
    let source: String
    let sourceBundleIdentifier: String?
    let capturedAt: Date
    let requiresNormalization: Bool
    let validatesGIF: Bool
    let fallbackImageData: Data?
    let fallbackImageRequiresNormalization: Bool
    let fallbackText: String?
    let fallbackRichTextData: Data?
  }

  private struct PreparedClipboardImageData: Sendable {
    let data: Data
    let fingerprint: String
    let metadata: StoredImageMetadata?
  }

  private struct PreparedStoredImageLoad: Sendable {
    let result: StoredImageDataLoadResult
    let metadata: StoredImageMetadata?
  }

  private struct BulkOCRRetrySnapshot {
    let ocrText: String
    let ocrState: OCRState
    let ocrConfidence: Float?
    let detectedBarcodes: [DetectedBarcode]
    let isConcealed: Bool
  }

  private struct ImageExportWorkResult: Sendable {
    let result: ImageExportResult
    let secureStorageFailure: Bool
  }

  private enum BackgroundImageIngestResult {
    case added(UUID)
    case duplicate(UUID)
    case failed
  }

  private struct FileReferenceAvailability: Equatable, Sendable {
    let itemID: UUID
    let fingerprint: String
    let existingPaths: Set<String>?
    let checkedAt: Date?
  }

  private struct RecommendationCacheEntry {
    let expiresAt: Date
    let items: [ClipItem]
  }

  private struct QuickPasteActionCacheEntry {
    let item: ClipItem
    let actions: [QuickPasteAction]
  }

  private struct SearchResultsCacheKey: Equatable {
    let query: String
    let filter: String
    let tag: String?
    let boardID: UUID?
    let interpretsNaturalLanguage: Bool
    let limit: Int?
  }

  private struct SearchResultsCacheEntry {
    let key: SearchResultsCacheKey
    let expiresAt: Date
    let items: [ClipItem]
  }

  private struct SemanticSearchKey: Equatable {
    let query: String
    let itemRevision: Int
    let filter: String
    let tag: String?
    let boardID: UUID?
    let limit: Int?
    let excludedID: UUID?
  }

  private struct SemanticSearchOrigin {
    let queryKey: String
    let itemID: UUID
  }

  private struct DeletedClip {
    let item: ClipItem
    let imageData: Data?
    let richTextData: Data?
    let stackIndex: Int?
  }

  private struct ArchiveExportSnapshot: Sendable {
    let exportedAt: Date
    let items: [ClipItem]
    let imagesURL: URL
    let richTextURL: URL
    let stackFingerprints: [String]
    let savedViews: [SavedClipView]
    let boards: [ClipBoard]
    let storageProtector: SecureLocalStorage?
    let requiresStorageProtection: Bool
  }

  init(
    rootURL: URL? = nil,
    startsMonitoring: Bool = true,
    preferences: ClipPreferences? = nil,
    pasteboard: NSPasteboard = .general,
    screenshotDirectoryURL: URL? = nil,
    storageProtector: SecureLocalStorage? = nil,
    asynchronouslyLoadsStorageProtector: Bool? = nil,
    storageProtectorLoader: @escaping @Sendable () throws -> SecureLocalStorage = {
      try SecureLocalStorage.production()
    },
    storageUnlockLongWaitDuration: Duration = .seconds(6),
    imageAnalyzer: (@Sendable (Data) async -> ImageAnalysisResult)? = nil,
    languageAwareImageAnalyzer: (@Sendable (Data, [String]) async -> ImageAnalysisResult)? = nil,
    ocrConfiguredImageAnalyzer:
      (@Sendable (Data, [String], [String]) async -> ImageAnalysisResult)? = nil,
    ocrRecognizer: (@Sendable (Data) async -> OCRResult)? = nil,
    barcodeRecognizer: (@Sendable (Data) async -> [DetectedBarcode])? = nil,
    screenshotImageDataLoader: @escaping @Sendable (URL) -> Data? = {
      if $0.pathExtension.lowercased() == "gif" {
        guard let data = try? Data(contentsOf: $0), ImageMetadata.isValidGIF(data) else {
          return nil
        }
        return data
      }
      return ScreenshotInbox.pngData(at: $0)
    },
    clipboardImageNormalizer: @escaping @Sendable (Data) -> Data? = {
      ScreenshotInbox.pngData(from: $0)
    },
    clipboardImageWriter: @escaping @Sendable (
      Data, URL, SecureLocalStorage?, Bool
    ) -> PersistenceWriteError? = { data, url, protector, requiresProtection in
      do {
        let storedData: Data
        if let protector {
          storedData = try protector.seal(data)
        } else if requiresProtection {
          throw SecureLocalStorageError.invalidKey
        } else {
          storedData = data
        }
        try storedData.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o600],
          ofItemAtPath: url.path
        )
        return nil
      } catch {
        try? FileManager.default.removeItem(at: url)
        return PersistenceWriteError(message: error.localizedDescription)
      }
    },
    storedImageDataLoader: @escaping @Sendable (
      URL, SecureLocalStorage?, Bool
    ) -> StoredImageDataLoadResult = { url, protector, requiresProtection in
      do {
        let storedData = try Data(contentsOf: url, options: .mappedIfSafe)
        if let protector {
          return .success(try protector.open(storedData).data)
        }
        if requiresProtection { throw SecureLocalStorageError.invalidKey }
        return .success(storedData)
      } catch {
        return .failure(
          PersistenceWriteError(message: error.localizedDescription),
          secureStorageFailure: error is SecureLocalStorageError
        )
      }
    },
    persistsHistoryInBackground: Bool? = nil,
    historyMetadataWriter: @escaping @Sendable (
      [ClipItem], URL, SecureLocalStorage?, Bool
    ) -> PersistenceWriteError? = { items, url, protector, requiresProtection in
      do {
        let data = try JSONEncoder().encode(items)
        let storedData: Data
        if let protector {
          storedData = try protector.seal(data)
        } else if requiresProtection {
          throw SecureLocalStorageError.invalidKey
        } else {
          storedData = data
        }
        try storedData.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o600],
          ofItemAtPath: url.path
        )
        return nil
      } catch {
        return PersistenceWriteError(message: error.localizedDescription)
      }
    },
    fileReferenceChecker: @escaping @Sendable ([String]) -> Set<String> = { paths in
      let fileManager = FileManager.default
      return Set(paths.filter { fileManager.fileExists(atPath: $0) })
    },
    screenshotSnapshotLoader: @escaping @Sendable (URL) -> ScreenshotSnapshotLoadResult = {
      directory in
      do {
        return .success(try ScreenshotInbox.snapshots(in: directory))
      } catch {
        return .failure
      }
    },
    captureFeedbackPlayer: @escaping @MainActor @Sendable () -> Void = {
      NSSound(named: NSSound.Name("Tink"))?.play()
    },
    semanticSearchIndex: SemanticSearchIndex = SemanticSearchIndex()
  ) {
    let usesLiveStore = rootURL == nil
    let needsAsynchronousStorageUnlock =
      (asynchronouslyLoadsStorageProtector ?? usesLiveStore) && storageProtector == nil
    // The display-name change must not move or orphan existing local history.
    let base =
      rootURL
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ClipNest", isDirectory: true)
    self.rootURL = base
    self.imagesURL = base.appendingPathComponent("Images", isDirectory: true)
    self.richTextURL = base.appendingPathComponent("RichText", isDirectory: true)
    self.metadataURL = base.appendingPathComponent("clips.json")
    self.stackURL = base.appendingPathComponent("stack.json")
    self.savedViewsURL = base.appendingPathComponent("saved-views.json")
    self.boardsURL = base.appendingPathComponent("boards.json")
    self.privacyRulesURL = base.appendingPathComponent("privacy-rules.json")
    self.newSnippetDraftURL = base.appendingPathComponent("new-snippet-draft.json")
    self.storageProtector = storageProtector
    self.storageProtectorLoader = storageProtectorLoader
    self.storageUnlockLongWaitDuration = storageUnlockLongWaitDuration
    self.requiresStorageProtection =
      usesLiveStore || storageProtector != nil || needsAsynchronousStorageUnlock
    self.preferences = preferences ?? ClipPreferences()
    self.pasteboard = pasteboard
    self.screenshotDirectoryOverride = screenshotDirectoryURL
    self.canWatchSystemScreenshots = rootURL == nil || screenshotDirectoryURL != nil
    if let ocrConfiguredImageAnalyzer {
      self.imageAnalyzer = ocrConfiguredImageAnalyzer
    } else if let languageAwareImageAnalyzer {
      self.imageAnalyzer = { data, languages, _ in
        await languageAwareImageAnalyzer(data, languages)
      }
    } else if let imageAnalyzer {
      self.imageAnalyzer = { data, _, _ in await imageAnalyzer(data) }
    } else if ocrRecognizer != nil || barcodeRecognizer != nil {
      let recognizeText = ocrRecognizer ?? { data in await OCRService.recognizeText(in: data) }
      let recognizeBarcodes =
        barcodeRecognizer ?? { data in await OCRService.detectBarcodes(in: data) }
      self.imageAnalyzer = { data, _, _ in
        async let ocr = recognizeText(data)
        async let barcodes = recognizeBarcodes(data)
        return await ImageAnalysisResult(ocr: ocr, barcodes: barcodes)
      }
    } else {
      self.imageAnalyzer = { data, preferredLanguages, customWords in
        await OCRService.analyzeImage(
          data,
          preferredLanguages: preferredLanguages,
          customWords: customWords
        )
      }
    }
    self.screenshotSnapshotLoader = screenshotSnapshotLoader
    self.screenshotImageDataLoader = screenshotImageDataLoader
    self.clipboardImageNormalizer = clipboardImageNormalizer
    self.clipboardImageWriter = clipboardImageWriter
    self.storedImageDataLoader = storedImageDataLoader
    self.persistsHistoryInBackground = persistsHistoryInBackground ?? usesLiveStore
    self.historyMetadataWriter = historyMetadataWriter
    self.fileReferenceChecker = fileReferenceChecker
    self.captureFeedbackPlayer = captureFeedbackPlayer
    self.semanticSearchIndex = semanticSearchIndex
    self.lastChangeCount = pasteboard.changeCount
    self.isMonitoring = startsMonitoring
    imageDataCache.countLimit = 64
    imageDataCache.totalCostLimit = 64 * 1_024 * 1_024
    decodedImageCache.countLimit = 48
    decodedImageCache.totalCostLimit = 128 * 1_024 * 1_024
    do {
      try prepareStorage()
      removeAbandonedHistoryStagingFiles()
    } catch {
      setPersistenceIssue(error)
    }
    if needsAsynchronousStorageUnlock {
      persistenceBlockedByUnreadableHistory = true
      storageIssue = StorageIssue(
        kind: .persistence,
        message: L10n.text("storage.unlocking", fallback: "Unlocking local history…"),
        detail: L10n.text(
          "storage.unlocking_detail",
          fallback: "Clipskein is waiting for macOS Keychain. History stays locked and unchanged."
        ),
        recoveryFileName: nil
      )
    }
    if !needsAsynchronousStorageUnlock {
      load()
      loadStack()
      loadSavedViews()
      loadBoards()
      loadPrivacyRules()
      loadNewSnippetDraft()
      migrateStoredPayloadsIfNeeded()
      pruneBoardReferences()
      purgeExpired()
      resumePendingImageAnalysis()
    }
    startExpirationTimer()
    observePreferences()
    if needsAsynchronousStorageUnlock {
      beginStorageUnlock(startMonitoringWhenReady: startsMonitoring)
    } else {
      configureScreenshotWatching()
      if startsMonitoring { startMonitoring() }
    }
  }

  isolated deinit {
    timer?.invalidate()
    expirationTimer?.invalidate()
    screenshotTimer?.invalidate()
    screenshotPollingTask?.cancel()
    clipboardImageCaptureTask?.cancel()
    historyPersistenceTask?.cancel()
    newSnippetDraftPersistenceTask?.cancel()
    storageUnlockTask?.cancel()
    storageUnlockWatchdogTask?.cancel()
    htmlRichTextConversionTasks.values.forEach { $0.cancel() }
    fileReferenceCheckTask?.cancel()
    imageLoadTasks.values.forEach { $0.cancel() }
    imageImportTask?.cancel()
    storageInventoryTask?.cancel()
    resumeTask?.cancel()
    secureCopyTask?.cancel()
    regionCaptureIngestionTask?.cancel()
    regionCaptureProcess?.terminate()
    imageAnalysisTasks.values.forEach { $0.cancel() }
    recoveryImageLoadTasks.values.forEach { $0.cancel() }
    quickPasteActionTasks.values.forEach { $0.cancel() }
    semanticSearchTask?.cancel()
  }

  var filteredItems: [ClipItem] {
    searchItems(
      query: searchText,
      filter: filter,
      tag: selectedTag,
      boardID: selectedBoardID,
      interpretNaturalLanguage: !searchAsLiteral,
      excludingSemanticItemID: semanticSearchOrigin?.itemID
    )
  }

  var currentSearchInterpretation: NaturalLanguageSearch? {
    guard SemanticSearchRequest(searchText) == nil else { return nil }
    let interpretation = NaturalLanguageSearch.interpret(
      searchText,
      knownApplications: knownSourceApplications
    )
    return interpretation.isActive ? interpretation : nil
  }

  var currentRegexSearchStatus: RegexSearchStatus {
    guard SemanticSearchRequest(searchText) == nil else { return .inactive }
    return ClipSearchQuery(searchText, interpretNaturalLanguage: false).regexStatus
  }

  var currentSemanticSearchStatus: SemanticSearchStatus {
    semanticSearchStatus(for: searchText)
  }

  var stackItems: [ClipItem] {
    if let stackItemsCache { return stackItemsCache }
    let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    let resolved = stackIDs.compactMap { itemsByID[$0] }
    stackItemsCache = resolved
    return resolved
  }

  var pendingImageAnalysisCount: Int {
    imageAnalysisSummary.pending
  }

  var retryableImageAnalysisCount: Int {
    imageAnalysisSummary.review
  }

  var imageAnalysisSummary: OCRLibrarySummary { OCRLibrarySummary(items: items) }

  var stackRequiresSecureCopy: Bool {
    stackItems.contains(where: \.isConcealed)
  }

  var isStorageEncrypted: Bool {
    requiresStorageProtection && storageProtector != nil
  }

  var canSaveCurrentView: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || filter != .all
      || selectedTag != nil
      || selectedBoardID != nil
  }

  var activeSavedViewID: UUID? {
    savedViews.first {
      $0.matches(
        query: searchText,
        filter: filter,
        tag: selectedTag,
        boardID: selectedBoardID,
        interpretsNaturalLanguage: !searchAsLiteral
      )
    }?.id
  }

  var popularTags: [String] {
    if let popularTagsCache { return popularTagsCache }
    var counts: [String: Int] = [:]
    var labels: [String: String] = [:]
    for item in items {
      for tag in item.tags {
        let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        counts[key, default: 0] += 1
        if labels[key] == nil { labels[key] = tag }
      }
    }
    let tags = counts.keys.sorted {
      let leftCount = counts[$0, default: 0]
      let rightCount = counts[$1, default: 0]
      if leftCount != rightCount { return leftCount > rightCount }
      return (labels[$0] ?? $0).localizedCaseInsensitiveCompare(labels[$1] ?? $1)
        == .orderedAscending
    }.prefix(8).compactMap { labels[$0] }
    popularTagsCache = tags
    return tags
  }

  var hasQuickAliases: Bool {
    if let hasQuickAliasesCache { return hasQuickAliasesCache }
    let result = items.contains { $0.alias != nil }
    hasQuickAliasesCache = result
    return result
  }

  func searchItems(
    query: String,
    filter: ClipFilter = .all,
    tag: String? = nil,
    boardID: UUID? = nil,
    interpretNaturalLanguage: Bool = true,
    limit: Int? = nil,
    excludingSemanticItemID: UUID? = nil
  ) -> [ClipItem] {
    if let semanticRequest = SemanticSearchRequest(query) {
      return semanticSearchItems(
        request: semanticRequest,
        filter: filter,
        tag: tag,
        boardID: boardID,
        limit: limit,
        excludedID: excludingSemanticItemID
      )
    }
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedQuery.isEmpty, filter == .all, tag == nil, boardID == nil {
      guard let limit else { return items }
      return Array(items.prefix(max(0, limit)))
    }
    let cacheKey = SearchResultsCacheKey(
      query: query,
      filter: filter.rawValue,
      tag: tag,
      boardID: boardID,
      interpretsNaturalLanguage: interpretNaturalLanguage,
      limit: limit
    )
    let now = Date()
    if let searchResultsCache,
      searchResultsCache.key == cacheKey,
      searchResultsCache.expiresAt > now
    {
      return searchResultsCache.items
    }
    let structuredQuery = ClipSearchQuery(
      query,
      knownApplications: interpretNaturalLanguage && !trimmedQuery.isEmpty
        ? knownSourceApplications : [],
      interpretNaturalLanguage: interpretNaturalLanguage
    )
    var matches: [ClipItem] = []
    matches.reserveCapacity(min(items.count, 128))
    for item in items {
      let searchIndex = searchIndex(for: item)
      let classifiedKind =
        filter.classifiedKind != nil || structuredQuery.requiresContentClassification
        ? contentKind(for: item) : nil
      let matchesFilter = filter.matches(item, classifiedKind: classifiedKind)
      let matchesQuery = structuredQuery.matches(
        item,
        classifiedKind: classifiedKind,
        normalizedSearchableText: searchIndex.searchableText,
        searchableTokens: searchIndex.searchableTokens,
        normalizedTags: searchIndex.tags,
        normalizedSource: searchIndex.source
      )
      let matchesTag =
        tag.map { selectedTag in
          let selectedKey = selectedTag.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
          return searchIndex.tags.contains(selectedKey)
        } ?? true
      let matchesBoard = boardID.map { item.boardIDs.contains($0) } ?? true
      if matchesFilter && matchesQuery && matchesTag && matchesBoard {
        matches.append(item)
      }
    }
    guard !structuredQuery.matcher.isEmpty else {
      let results = limit.map { Array(matches.prefix(max(0, $0))) } ?? matches
      searchResultsCache = SearchResultsCacheEntry(
        key: cacheKey,
        expiresAt: now.addingTimeInterval(1),
        items: results
      )
      return results
    }
    var scoredMatches: [(item: ClipItem, score: Double)] = []
    scoredMatches.reserveCapacity(matches.count)
    for item in matches {
      let score = searchScore(
        for: item,
        index: searchIndex(for: item),
        matcher: structuredQuery.matcher
      )
      scoredMatches.append((item, score))
    }
    let results = rankedItems(scoredMatches, limit: limit)
    searchResultsCache = SearchResultsCacheEntry(
      key: cacheKey,
      expiresAt: now.addingTimeInterval(1),
      items: results
    )
    return results
  }

  private func semanticSearchItems(
    request: SemanticSearchRequest,
    filter: ClipFilter,
    tag: String?,
    boardID: UUID?,
    limit: Int?,
    excludedID: UUID?
  ) -> [ClipItem] {
    guard isSessionActive else { return [] }
    let key = SemanticSearchKey(
      query: request.cacheKey,
      itemRevision: itemRevision,
      filter: filter.rawValue,
      tag: tag.map(SearchMatcher.normalize),
      boardID: boardID,
      limit: limit,
      excludedID: excludedID
    )
    if semanticSearchResultKey == key {
      let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
      return semanticSearchResultIDs.compactMap { itemsByID[$0] }
    }
    guard request.isValid else {
      semanticSearchTask?.cancel()
      semanticSearchTask = nil
      semanticSearchTaskKey = key
      semanticSearchResultKey = nil
      semanticSearchResultIDs.removeAll(keepingCapacity: true)
      semanticSearchResultScores.removeAll(keepingCapacity: true)
      semanticSearchStatus = .invalidQuery
      return []
    }
    if semanticSearchTaskKey != key {
      semanticSearchTask?.cancel()
      semanticSearchTaskKey = key
      semanticSearchResultKey = nil
      semanticSearchResultIDs.removeAll(keepingCapacity: true)
      semanticSearchResultScores.removeAll(keepingCapacity: true)
      semanticSearchStatus = .preparing(query: request.query)

      let normalizedTag = tag.map(SearchMatcher.normalize)
      let candidates = items.filter { item in
        guard !item.isConcealed, item.id != excludedID else { return false }
        let classifiedKind = filter.classifiedKind.map { _ in contentKind(for: item) }
        let matchesFilter = filter.matches(item, classifiedKind: classifiedKind)
        let matchesTag = normalizedTag.map { searchIndex(for: item).tags.contains($0) } ?? true
        let matchesBoard = boardID.map { item.boardIDs.contains($0) } ?? true
        return matchesFilter && matchesTag && matchesBoard
      }
      let index = semanticSearchIndex
      let resultLimit = min(max(0, limit ?? 100), 100)
      semanticSearchTask = Task { @MainActor [weak self] in
        let documentTask = Task.detached(priority: .userInitiated) {
          var documents: [SemanticSearchDocument] = []
          documents.reserveCapacity(candidates.count)
          for item in candidates {
            if Task.isCancelled { break }
            if let document = SemanticSearchDocument(item: item) {
              documents.append(document)
            }
          }
          return documents
        }
        let documents = await withTaskCancellationHandler {
          await documentTask.value
        } onCancel: {
          documentTask.cancel()
        }
        guard !Task.isCancelled, let self, self.semanticSearchTaskKey == key,
          self.itemRevision == key.itemRevision, self.isSessionActive
        else { return }
        if documents.count > 500 {
          let initialDocuments = Array(documents.prefix(500))
          let initialResult = await index.search(
            request: request,
            documents: initialDocuments,
            limit: resultLimit,
            prunesMissingDocuments: false
          )
          guard !Task.isCancelled, self.semanticSearchTaskKey == key,
            self.itemRevision == key.itemRevision, self.isSessionActive
          else { return }
          self.applySemanticSearchResult(
            initialResult,
            request: request,
            key: key,
            totalDocumentCount: documents.count,
            isFinal: false
          )
        }
        let result = await index.search(
          request: request,
          documents: documents,
          limit: resultLimit
        )
        guard !Task.isCancelled, self.semanticSearchTaskKey == key,
          self.itemRevision == key.itemRevision, self.isSessionActive
        else { return }
        self.semanticSearchTask = nil
        self.applySemanticSearchResult(
          result,
          request: request,
          key: key,
          totalDocumentCount: documents.count,
          isFinal: true
        )
      }
    }
    return []
  }

  private func applySemanticSearchResult(
    _ result: SemanticSearchResult,
    request: SemanticSearchRequest,
    key: SemanticSearchKey,
    totalDocumentCount: Int,
    isFinal: Bool
  ) {
    switch result.availability {
    case .available:
      let threshold: Float
      if let topScore = result.hits.first?.score {
        threshold = max(0.18, topScore - 0.28)
      } else {
        threshold = 1
      }
      let acceptedHits = result.hits.filter { $0.score >= threshold }
      semanticSearchResultIDs = acceptedHits.map(\.id)
      semanticSearchResultScores = Dictionary(
        uniqueKeysWithValues: acceptedHits.map { ($0.id, $0.score) }
      )
      semanticSearchResultKey = key
      semanticSearchStatus = isFinal
        ? .ready(
          query: request.query,
          resultCount: semanticSearchResultIDs.count,
          indexedCount: result.indexedDocumentCount
        )
        : .refining(
          query: request.query,
          indexedCount: result.indexedDocumentCount,
          totalCount: totalDocumentCount,
          resultCount: semanticSearchResultIDs.count
        )
    case .invalidQuery:
      semanticSearchResultIDs.removeAll(keepingCapacity: true)
      semanticSearchResultScores.removeAll(keepingCapacity: true)
      semanticSearchResultKey = nil
      semanticSearchStatus = .invalidQuery
    case .modelUnavailable:
      semanticSearchResultIDs.removeAll(keepingCapacity: true)
      semanticSearchResultScores.removeAll(keepingCapacity: true)
      semanticSearchResultKey = nil
      semanticSearchStatus = .modelUnavailable
    }
    semanticSearchRevision &+= 1
    normalizeSelection()
  }

  func useLiteralSearch() {
    guard currentSearchInterpretation != nil else { return }
    searchAsLiteral = true
    normalizeSelection()
  }

  func useNaturalLanguageSearch() {
    guard currentSearchInterpretation != nil else { return }
    searchAsLiteral = false
    normalizeSelection()
  }

  private var allSourceApplicationFacets: [SourceApplicationFacet] {
    if let sourceApplicationFacetsCache { return sourceApplicationFacetsCache }
    typealias FacetAccumulator = (
      name: String, bundleIdentifier: String?, count: Int, firstIndex: Int
    )
    var accumulated: [String: FacetAccumulator] = [:]
    for (index, item) in items.enumerated() {
      let name = item.sourceApplication.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { continue }
      let key = item.sourceBundleIdentifier.map { "bundle:\($0.lowercased())" }
        ?? "name:\(SearchMatcher.normalize(name))"
      if var existing = accumulated[key] {
        existing.count += 1
        accumulated[key] = existing
      } else {
        accumulated[key] = (name, item.sourceBundleIdentifier, 1, index)
      }
    }
    let facets = accumulated.values.sorted { left, right in
      if left.count != right.count { return left.count > right.count }
      if left.firstIndex != right.firstIndex { return left.firstIndex < right.firstIndex }
      return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }.map {
      SourceApplicationFacet(
        name: $0.name,
        bundleIdentifier: $0.bundleIdentifier,
        count: $0.count
      )
    }
    sourceApplicationFacetsCache = facets
    return facets
  }

  var sourceApplicationFacets: [SourceApplicationFacet] {
    Array(allSourceApplicationFacets.prefix(8))
  }

  func sourceApplicationFacet(bundleIdentifier: String) -> SourceApplicationFacet? {
    allSourceApplicationFacets.first {
      $0.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }
  }

  private var knownSourceApplications: [String] {
    allSourceApplicationFacets.map(\.name)
  }

  func quickPickerItems(
    query: String,
    interpretNaturalLanguage: Bool = true,
    limit: Int? = nil,
    excludingSemanticItemID: UUID? = nil,
    preferredBoardID: UUID? = nil
  ) -> [ClipItem] {
    // Preserve regex escapes such as \D and \S. SearchMatcher normalizes ordinary text and aliases.
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if query.first == "@", !query.contains(where: \.isWhitespace) {
      let fragment = String(query.dropFirst())
      let matcher = SearchMatcher(fragment)
      let matches = items.filter { item in
        let index = searchIndex(for: item)
        guard !index.alias.isEmpty else { return false }
        return fragment.isEmpty
          || matcher.matches(
            normalizedText: index.alias,
            tokens: index.aliasTokens
          )
      }
      var scoredMatches: [(item: ClipItem, score: Double)] = []
      scoredMatches.reserveCapacity(matches.count)
      for item in matches {
        let score = aliasSearchScore(
          for: item,
          normalizedAlias: searchIndex(for: item).alias,
          aliasTokens: searchIndex(for: item).aliasTokens,
          fragment: fragment,
          matcher: matcher
        )
        scoredMatches.append((item, score))
      }
      return rankedItems(scoredMatches, limit: limit)
    }
    if !query.isEmpty {
      return searchItems(
        query: query,
        interpretNaturalLanguage: interpretNaturalLanguage,
        limit: limit,
        excludingSemanticItemID: excludingSemanticItemID
      )
    }
    let now = Date()
    if let limit,
      let cached = quickPickerRecommendationCache[
        RecommendationCacheKey(limit: limit, preferredBoardID: preferredBoardID)
      ],
      cached.expiresAt > now
    {
      return cached.items
    }
    let scoredItems = items.map { item in
      let contextBoost = preferredBoardID.map { item.boardIDs.contains($0) } == true
        ? 1_000_000.0 : 0
      return (item: item, score: recommendationScore(for: item, now: now) + contextBoost)
    }
    let ranked = rankedItems(scoredItems, limit: limit)
    if let limit, limit > 0 {
      quickPickerRecommendationCache[
        RecommendationCacheKey(limit: limit, preferredBoardID: preferredBoardID)
      ] = RecommendationCacheEntry(
        expiresAt: now.addingTimeInterval(30),
        items: ranked
      )
    }
    return ranked
  }

  func quickPickerSearchInterpretation(for query: String) -> NaturalLanguageSearch? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.hasPrefix("@"), SemanticSearchRequest(trimmed) == nil else { return nil }
    let interpretation = NaturalLanguageSearch.interpret(
      trimmed,
      knownApplications: knownSourceApplications
    )
    return interpretation.isActive ? interpretation : nil
  }

  func quickPickerRegexSearchStatus(for query: String) -> RegexSearchStatus {
    guard SemanticSearchRequest(query) == nil else { return .inactive }
    return ClipSearchQuery(query, interpretNaturalLanguage: false).regexStatus
  }

  func semanticSearchStatus(for query: String) -> SemanticSearchStatus {
    guard let request = SemanticSearchRequest(query) else { return .inactive }
    switch semanticSearchStatus {
    case .preparing(let activeQuery), .refining(let activeQuery, _, _, _),
      .ready(let activeQuery, _, _):
      return SearchMatcher.normalize(activeQuery) == request.cacheKey
        ? semanticSearchStatus : .inactive
    case .invalidQuery, .modelUnavailable:
      return semanticSearchTaskKey?.query == request.cacheKey ? semanticSearchStatus : .inactive
    case .inactive:
      return .inactive
    }
  }

  func semanticMatchConfidence(
    for item: ClipItem,
    query: String
  ) -> SemanticMatchConfidence? {
    guard let request = SemanticSearchRequest(query),
      semanticSearchTaskKey?.query == request.cacheKey,
      let score = semanticSearchResultScores[item.id]
    else { return nil }
    return SemanticMatchConfidence(score: score)
  }

  func semanticCollectionCandidates(
    from candidates: [ClipItem],
    query: String
  ) -> [ClipItem] {
    guard let request = SemanticSearchRequest(query),
      semanticSearchResultKey?.query == request.cacheKey,
      case .ready = semanticSearchStatus
    else { return [] }
    return candidates.filter {
      (semanticSearchResultScores[$0.id] ?? -.infinity)
        >= SemanticMatchConfidence.minimumCollectionScore
    }
  }

  @discardableResult
  func findSimilar(to item: ClipItem) -> Bool {
    guard let query = SemanticSearchRequest.suggestedQuery(for: item),
      let request = SemanticSearchRequest("~ \(query)")
    else { return false }
    filter = .all
    selectedTag = nil
    selectedBoardID = nil
    semanticSearchOrigin = SemanticSearchOrigin(queryKey: request.cacheKey, itemID: item.id)
    searchText = "~ \(query)"
    return true
  }

  func quickPasteActions(for item: ClipItem) -> [QuickPasteAction] {
    guard isSessionActive, !item.isConcealed else { return [] }
    if let cached = quickPasteActionCache[item.id], cached.item == item {
      return cached.actions
    }
    if quickPasteActionSourceByteCount(item) > Self.maximumSynchronousQuickActionBytes {
      scheduleQuickPasteActions(for: item)
      return []
    }
    let actions = QuickPasteActionBuilder.actions(for: item)
    cacheQuickPasteActions(actions, for: item)
    return actions
  }

  func isPreparingQuickPasteActions(for item: ClipItem) -> Bool {
    guard isSessionActive, !item.isConcealed,
      quickPasteActionSourceByteCount(item) > Self.maximumSynchronousQuickActionBytes,
      quickPasteActionCache[item.id]?.item != item
    else { return false }
    if quickPasteActionTasks[item.id] == nil {
      scheduleQuickPasteActions(for: item)
    }
    return quickPasteActionTasks[item.id] != nil
  }

  private func quickPasteActionSourceByteCount(_ item: ClipItem) -> Int {
    switch item.kind {
    case .text: item.text.utf8.count
    case .image: item.ocrText.utf8.count
    case .files: 0
    }
  }

  private func scheduleQuickPasteActions(for item: ClipItem) {
    guard quickPasteActionTasks[item.id] == nil else { return }
    let generation = UUID()
    let gate = quickPasteActionGate
    quickPasteActionGenerations[item.id] = generation
    quickPasteActionTasks[item.id] = Task.detached(priority: .userInitiated) { [weak self] in
      guard let actions: [QuickPasteAction] = await gate.run({
        guard !Task.isCancelled else { return [] }
        return QuickPasteActionBuilder.actions(for: item)
      }) else {
        await self?.cancelQuickPasteActionPreparation(for: item.id, generation: generation)
        return
      }
      guard !Task.isCancelled else {
        await self?.cancelQuickPasteActionPreparation(for: item.id, generation: generation)
        return
      }
      await self?.commitQuickPasteActions(actions, for: item, generation: generation)
    }
  }

  private func cancelQuickPasteActionPreparation(for id: UUID, generation: UUID) {
    guard quickPasteActionGenerations[id] == generation else { return }
    quickPasteActionTasks[id] = nil
    quickPasteActionGenerations[id] = nil
  }

  private func commitQuickPasteActions(
    _ actions: [QuickPasteAction],
    for item: ClipItem,
    generation: UUID
  ) {
    guard quickPasteActionGenerations[item.id] == generation else { return }
    defer {
      quickPasteActionTasks[item.id] = nil
      quickPasteActionGenerations[item.id] = nil
    }
    guard isSessionActive, !Task.isCancelled else { return }
    cacheQuickPasteActions(actions, for: item)
    quickPasteActionRevision &+= 1
  }

  private func cacheQuickPasteActions(_ actions: [QuickPasteAction], for item: ClipItem) {
    if quickPasteActionCache.count >= 64,
      quickPasteActionCache[item.id] == nil,
      let evictedID = quickPasteActionCache.keys.first
    {
      quickPasteActionCache.removeValue(forKey: evictedID)
    }
    quickPasteActionCache[item.id] = QuickPasteActionCacheEntry(item: item, actions: actions)
  }

  func warmSearchIndex() async {
    for (index, item) in items.enumerated() {
      guard !Task.isCancelled, isSessionActive else { return }
      _ = searchIndex(for: item)
      if index.isMultiple(of: 100) { await Task.yield() }
    }
  }

  func updateMetadata(_ item: ClipItem, title: String, alias rawAlias: String) -> String? {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else {
      return L10n.text("rename_clip.missing", fallback: "This clip is no longer available.")
    }
    let metadata = normalizedMetadata(title: title, alias: rawAlias, excluding: item.id)
    if let error = metadata.error { return error }
    let normalizedTitle = metadata.title
    let normalizedAlias = metadata.alias
    guard items[index].customTitle != normalizedTitle || items[index].alias != normalizedAlias
    else {
      return nil
    }
    items[index].customTitle = normalizedTitle
    items[index].alias = normalizedAlias
    persist()
    showNotice(
      L10n.text("notice.clip_details_updated", fallback: "Clip details updated"),
      systemImage: "checkmark.circle.fill")
    return nil
  }

  func createSnippet(
    text: String,
    title: String,
    alias: String,
    conceal: Bool = false,
    tags: [String] = [],
    boardID: UUID? = nil,
    sourceApplication: String? = nil,
    sourceBundleIdentifier: String? = nil,
    richTextData: Data? = nil
  ) -> SnippetCreationResult {
    guard !isUnlockingStorage else {
      return .invalid(
        L10n.text(
          "storage.unlocking_action_blocked",
          fallback: "Wait for local history to finish unlocking before creating a snippet."
        )
      )
    }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
    guard text.utf8.count <= Self.maximumEditedTextBytes else { return .tooLarge }

    let fingerprint = digest(Data(text.utf8))
    let existingID = items.first(where: { $0.fingerprint == fingerprint })?.id
    if let error = snippetDraftValidationError(
      title: title,
      alias: alias,
      tags: tags,
      boardID: boardID,
      excluding: existingID
    ) {
      return .invalid(error)
    }
    let metadata = normalizedMetadata(title: title, alias: alias, excluding: existingID)
    if let error = metadata.error { return .invalid(error) }
    let shouldConceal = conceal || (preferences.protectSecrets && Self.looksSensitive(text))
    let trimmedSource = sourceApplication?.trimmingCharacters(in: .whitespacesAndNewlines)
    let source = trimmedSource.flatMap { $0.isEmpty ? nil : String($0.prefix(120)) }

    addText(
      text,
      source: source ?? "Created in Clipskein",
      sourceBundleIdentifier: sourceBundleIdentifier,
      isConcealed: shouldConceal,
      customTitle: metadata.title,
      tags: tags,
      boardIDs: boardID.map { [$0] } ?? [],
      richTextData: richTextData
    )
    guard let index = items.firstIndex(where: { $0.fingerprint == fingerprint }) else {
      return .invalid(
        L10n.text("new_snippet.error_save", fallback: "Clipskein could not save this snippet.")
      )
    }

    items[index].customTitle = metadata.title
    items[index].alias = metadata.alias
    items[index].isPinned = true
    items[index].expiresAt = nil
    let snippetIsConcealed = items[index].isConcealed
    let id = items[index].id
    sortItems()
    searchText = ""
    filter = .all
    selectedTag = nil
    selectedBoardID = nil
    selectedID = id
    persist()
    showNotice(
      snippetIsConcealed
        ? L10n.text(
          "notice.snippet_created_concealed",
          fallback: "Snippet created, pinned, and concealed"
        )
        : existingID == nil
          ? L10n.text("notice.snippet_created", fallback: "Snippet created and pinned")
          : L10n.text("notice.snippet_reused", fallback: "Matching clip saved as a snippet"),
      systemImage: snippetIsConcealed
        ? "eye.slash.fill" : existingID == nil
          ? "text.badge.plus" : "arrow.triangle.2.circlepath"
    )
    return existingID == nil ? .created(id) : .reused(id)
  }

  func validateNewSnippetDraft(_ draft: NewSnippetDraft) -> String? {
    let normalizedAlias = ClipAlias.normalized(draft.alias)
    let aliasOwner = normalizedAlias.flatMap { candidate in
      items.first { SearchMatcher.normalize($0.alias ?? "") == candidate }
    }
    let existingID = aliasOwner.flatMap { owner -> UUID? in
      guard !draft.text.isEmpty else { return nil }
      return owner.fingerprint == digest(Data(draft.text.utf8)) ? owner.id : nil
    }
    return snippetDraftValidationError(
      title: draft.title,
      alias: draft.alias,
      tags: draft.tags,
      boardID: draft.boardID,
      excluding: existingID
    )
  }

  private func snippetDraftValidationError(
    title: String,
    alias: String,
    tags: [String],
    boardID: UUID?,
    excluding existingID: UUID?
  ) -> String? {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedTitle.count > Self.maximumCustomTitleLength {
      return L10n.format(
        "rename_clip.title_limit",
        fallback: "Keep the title under %d characters.",
        Self.maximumCustomTitleLength)
    }

    let meaningfulTags = tags.compactMap { rawTag -> String? in
      var tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
      while tag.hasPrefix("#") { tag.removeFirst() }
      tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
      return tag.isEmpty ? nil : tag
    }
    if meaningfulTags.count > Self.maximumTagCount {
      return L10n.format(
        "tag_editor.limit",
        fallback: "A clip can have up to %d tags.",
        Self.maximumTagCount)
    }
    if meaningfulTags.contains(where: { $0.count > Self.maximumTagLength }) {
      return L10n.format(
        "tag_editor.length",
        fallback: "Keep tags under %d characters.",
        Self.maximumTagLength)
    }
    if let boardID, !boards.contains(where: { $0.id == boardID }) {
      return L10n.text(
        "new_snippet.pinboard_unavailable",
        fallback: "That Pinboard is no longer available. Choose another one.")
    }
    return normalizedMetadata(title: title, alias: alias, excluding: existingID).error
  }

  private func normalizedMetadata(
    title: String,
    alias rawAlias: String,
    excluding itemID: UUID?
  ) -> (title: String?, alias: String?, error: String?) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedTitle =
      trimmedTitle.isEmpty ? nil : String(trimmedTitle.prefix(Self.maximumCustomTitleLength))
    let trimmedAlias = rawAlias.trimmingCharacters(in: .whitespacesAndNewlines)
    if ClipAlias.exceedsMaximumLength(trimmedAlias) {
      return (
        normalizedTitle,
        nil,
        L10n.format(
          "rename_clip.alias_limit",
          fallback: "Keep the alias under %d characters.",
          ClipAlias.maximumLength)
      )
    }
    let normalizedAlias = ClipAlias.normalized(trimmedAlias)
    if !trimmedAlias.isEmpty, normalizedAlias == nil {
      return (
        normalizedTitle,
        nil,
        L10n.text(
          "rename_clip.alias_invalid_full",
          fallback: "Use letters, numbers, hyphens, or underscores for the alias.")
      )
    }
    if let normalizedAlias,
      items.contains(where: {
        $0.id != itemID && SearchMatcher.normalize($0.alias ?? "") == normalizedAlias
      })
    {
      return (
        normalizedTitle,
        normalizedAlias,
        L10n.format(
          "rename_clip.alias_duplicate",
          fallback: "@%@ is already assigned to another clip.",
          normalizedAlias)
      )
    }
    return (normalizedTitle, normalizedAlias, nil)
  }

  func startMonitoring() {
    resumeTask?.cancel()
    resumeTask = nil
    pauseUntil = nil
    timer?.invalidate()
    timer = nil
    isMonitoring = true
    scheduleMonitoringTimerIfNeeded()
  }

  private func scheduleMonitoringTimerIfNeeded() {
    guard isMonitoring, isSessionActive, timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.pollPasteboard() }
    }
  }

  func stopMonitoring() {
    resumeTask?.cancel()
    resumeTask = nil
    pauseUntil = nil
    stopMonitoringTimer()
  }

  func pause(for duration: TimeInterval) {
    resumeTask?.cancel()
    stopMonitoringTimer()
    let resumeDate = Date().addingTimeInterval(duration)
    pauseUntil = resumeDate
    resumeTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(duration))
      guard !Task.isCancelled else { return }
      self?.startMonitoring()
    }
  }

  private func stopMonitoringTimer() {
    isMonitoring = false
    timer?.invalidate()
    timer = nil
  }

  func suspendForInactiveSession() {
    guard isSessionActive else { return }
    isSessionActive = false
    timer?.invalidate()
    timer = nil
    screenshotTimer?.invalidate()
    screenshotTimer = nil
    screenshotPollingTask?.cancel()
    screenshotPollingTask = nil
    fileReferenceCheckTask?.cancel()
    fileReferenceCheckTask = nil
    imageLoadTasks.values.forEach { $0.cancel() }
    imageLoadTasks.removeAll(keepingCapacity: true)
    cancelImageCopyPreparation()
    cancelImageExport()
    htmlRichTextConversionTasks.values.forEach { $0.cancel() }
    htmlRichTextConversionTasks.removeAll(keepingCapacity: true)
    clipboardImageCaptureTask?.cancel()
    clipboardImageCaptureTask = nil
    clipboardImageCaptureGeneration = nil
    pendingClipboardImages.removeAll(keepingCapacity: true)
    isWatchingScreenshots = false
    isRetryingScreenshotWatch = false
    regionCaptureProcess?.terminate()
    regionCaptureIngestionTask?.cancel()
    regionCaptureIngestionTask = nil
    imageAnalysisTasks.values.forEach { $0.cancel() }
    imageAnalysisTasks.removeAll(keepingCapacity: true)
    imageAnalysisGenerations.removeAll(keepingCapacity: true)
    scheduledImageAnalysisIDs.removeAll(keepingCapacity: true)
    imageAnalysisCallbacks.removeAll(keepingCapacity: true)
    pendingRecoveryImageIDs.removeAll(keepingCapacity: true)
    activeRecoveryImageIDs.removeAll(keepingCapacity: true)
    recoveryImageLoadTasks.values.forEach { $0.cancel() }
    recoveryImageLoadTasks.removeAll(keepingCapacity: true)
    recoveryImageLoadGenerations.removeAll(keepingCapacity: true)
    if imageImportProgress != nil { cancelImageImport() }
    recoverableImageImportURLs.removeAll(keepingCapacity: false)
    discardSensitiveDerivedContentCaches()
    discardCachedImages()

    if let expectedChangeCount = secureCopyExpectedChangeCount,
      Self.shouldClearSecureClipboard(
        expectedChangeCount: expectedChangeCount,
        currentChangeCount: pasteboard.changeCount
      )
    {
      pasteboard.clearContents()
      lastChangeCount = pasteboard.changeCount
    }
    cancelSecureClipboardClear()
  }

  func resumeAfterInactiveSession() {
    guard !isSessionActive else { return }
    isSessionActive = true
    // Never ingest clipboard changes made while this user session was unavailable.
    lastChangeCount = pasteboard.changeCount
    scheduleMonitoringTimerIfNeeded()
    configureScreenshotWatching()
    resumePendingImageAnalysis()
  }

  func toggleMonitoring() {
    isMonitoring ? stopMonitoring() : startMonitoring()
  }

  func setScreenshotWatching(_ enabled: Bool) {
    preferences.watchScreenshots = enabled
  }

  func pollScreenshotFolder(now: Date = .now) async {
    guard isSessionActive, isWatchingScreenshots else { return }
    if let screenshotPollingTask { await screenshotPollingTask.value }
    let directory = screenshotDirectoryOverride ?? ScreenshotInbox.configuredDirectory()
    let isBaseline =
      watchedScreenshotDirectory?.standardizedFileURL != directory.standardizedFileURL
    if isBaseline { prepareScreenshotDirectory(directory, startedAt: now) }
    await loadAndApplyScreenshotSnapshots(from: directory, now: now, isBaseline: isBaseline)
  }

  func retryScreenshotWatching() async {
    guard isWatchingScreenshots, !isRetryingScreenshotWatch else { return }
    let wasUnavailable = screenshotWatchIssue != nil
    isRetryingScreenshotWatch = true
    defer { isRetryingScreenshotWatch = false }
    await pollScreenshotFolder()
    if wasUnavailable, screenshotWatchIssue == nil {
      showNotice(
        L10n.text(
          "screenshot_watch.restored",
          fallback: "Screenshot folder access restored"
        ),
        systemImage: "checkmark.circle.fill"
      )
    }
  }

  private func loadAndApplyScreenshotSnapshots(
    from directory: URL,
    now: Date,
    isBaseline: Bool
  ) async {
    let loader = screenshotSnapshotLoader
    let result = await Task.detached(priority: .utility) {
      loader(directory)
    }.value
    guard isSessionActive, !Task.isCancelled,
      watchedScreenshotDirectory?.standardizedFileURL == directory.standardizedFileURL
    else { return }
    guard case .success(let snapshots) = result else {
      screenshotWatchIssue = L10n.text(
        "screenshot_watch.read_failed",
        fallback: "Clipskein cannot read the screenshot folder. Check folder access and try again.")
      return
    }
    screenshotWatchIssue = nil
    seenScreenshotIdentities.formIntersection(Set(snapshots.map(\.identity)))
    if isBaseline {
      seenScreenshotIdentities = Set(
        snapshots.lazy
          .filter { $0.modifiedAt < self.screenshotWatchingStartedAt }
          .map(\.identity)
      )
    }

    let candidates = ScreenshotInbox.readyCandidates(
      from: snapshots,
      excluding: seenScreenshotIdentities,
      startedAt: screenshotWatchingStartedAt,
      now: now
    )
    let imageLoader = screenshotImageDataLoader
    let prepared = await Task.detached(priority: .utility) {
      candidates.map { candidate in
        (candidate, imageLoader(candidate.url))
      }
    }.value
    guard isSessionActive, !Task.isCancelled,
      watchedScreenshotDirectory?.standardizedFileURL == directory.standardizedFileURL
    else { return }
    var importedCount = 0
    for (candidate, data) in prepared {
      seenScreenshotIdentities.insert(candidate.identity)
      guard let data else {
        seenScreenshotIdentities.remove(candidate.identity)
        continue
      }
      let result = await addImageInBackground(
        data: data,
        source: "Screenshot",
        refreshesDuplicates: false
      )
      switch result {
      case .added:
        importedCount += 1
      case .duplicate:
        break
      case .failed:
        seenScreenshotIdentities.remove(candidate.identity)
      }
    }
    guard importedCount > 0 else { return }
    showNotice(
      importedCount == 1
        ? L10n.text("screenshot_watch.imported_one", fallback: "New screenshot is searchable")
        : L10n.format(
          "screenshot_watch.imported_many",
          fallback: "%d screenshots are searchable",
          importedCount),
      systemImage: "text.viewfinder"
    )
  }

  private func configureScreenshotWatching() {
    screenshotTimer?.invalidate()
    screenshotTimer = nil
    screenshotPollingTask?.cancel()
    screenshotPollingTask = nil
    screenshotWatchIssue = nil
    isRetryingScreenshotWatch = false
    guard isSessionActive, preferences.watchScreenshots, canWatchSystemScreenshots else {
      isWatchingScreenshots = false
      return
    }

    isWatchingScreenshots = true
    let directory = screenshotDirectoryOverride ?? ScreenshotInbox.configuredDirectory()
    prepareScreenshotDirectory(directory, startedAt: .now)
    scheduleScreenshotPoll(directory: directory, now: .now, isBaseline: true)
    let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.screenshotPollingTask == nil else { return }
        let directory = self.screenshotDirectoryOverride ?? ScreenshotInbox.configuredDirectory()
        if self.watchedScreenshotDirectory?.standardizedFileURL != directory.standardizedFileURL {
          self.prepareScreenshotDirectory(directory, startedAt: .now)
          self.scheduleScreenshotPoll(directory: directory, now: .now, isBaseline: true)
        } else {
          self.scheduleScreenshotPoll(directory: directory, now: .now, isBaseline: false)
        }
      }
    }
    timer.tolerance = 0.35
    screenshotTimer = timer
  }

  private func prepareScreenshotDirectory(_ directory: URL, startedAt: Date) {
    watchedScreenshotDirectory = directory
    screenshotWatchingStartedAt = startedAt
    seenScreenshotIdentities = []
  }

  private func scheduleScreenshotPoll(directory: URL, now: Date, isBaseline: Bool) {
    screenshotPollingTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.loadAndApplyScreenshotSnapshots(
        from: directory,
        now: now,
        isBaseline: isBaseline
      )
      self.screenshotPollingTask = nil
    }
  }

  func ignoreNextCopy() {
    oneShotCaptureGuard.arm()
    isIgnoringNextCopy = true
    showNotice(
      L10n.text(
        "notice.ignore_next_enabled", fallback: "The next captured item will be ignored"),
      systemImage: "eye.slash.fill")
  }

  func cancelIgnoringNextCopy() {
    oneShotCaptureGuard.cancel()
    isIgnoringNextCopy = false
    showNotice(
      L10n.text("notice.ignore_next_cancelled", fallback: "Next-copy protection cancelled"),
      systemImage: "eye")
  }

  @discardableResult
  func setSourceApplicationExcluded(_ excluded: Bool, for item: ClipItem) -> Bool {
    guard let bundleIdentifier = item.sourceBundleIdentifier else { return false }
    preferences.setExcluded(excluded, bundleIdentifier: bundleIdentifier)
    let applicationName = item.localizedSourceApplication()
    showNotice(
      excluded
        ? L10n.format(
          "notice.source_excluded",
          fallback: "Future copies from %@ will not be captured",
          applicationName
        )
        : L10n.format(
          "notice.source_included",
          fallback: "Future copies from %@ can be captured again",
          applicationName
        ),
      systemImage: excluded ? "hand.raised.fill" : "checkmark.shield.fill"
    )
    return true
  }

  func pollPasteboard() {
    guard !isUnlockingStorage, isSessionActive, isMonitoring, !isCapturingSelectedText,
      pasteboard.changeCount != lastChangeCount
    else {
      return
    }
    cancelSecureClipboardClear()
    lastChangeCount = pasteboard.changeCount

    let sourceType = NSPasteboard.PasteboardType(ClipboardCapturePolicy.sourceType)
    let ownSourceIdentifier = Bundle.main.bundleIdentifier ?? "app.clipnest.ClipNest"
    if pasteboard.string(forType: sourceType) == ownSourceIdentifier {
      return
    }

    let captureDecision = ClipboardCapturePolicy.decision(
      for: (pasteboard.types ?? []).map(\.rawValue)
    )
    switch captureDecision {
    case .capture:
      break
    case .ignoreConfidential:
      showNotice(
        L10n.text(
          "notice.protected_concealed", fallback: "Protected a concealed clipboard item"),
        systemImage: "hand.raised.fill")
      return
    case .ignoreTransient, .ignoreGenerated:
      return
    }

    let source = sourceApplication()
    if preferences.isExcluded(bundleIdentifier: source.bundleIdentifier) {
      showNotice(
        L10n.format("notice.ignored_source", fallback: "Ignored a copy from %@", source.name),
        systemImage: "hand.raised.fill")
      return
    }

    let copiedFileURLs = fileURLs(from: pasteboard)
    if !copiedFileURLs.isEmpty {
      guard preferences.captureFiles else { return }
      if consumeIgnoreNextCopy() { return }
      if addFiles(
        copiedFileURLs,
        source: source.name,
        sourceBundleIdentifier: source.bundleIdentifier
      ) != nil {
        playCaptureFeedbackIfEnabled()
      }
      return
    }

    // Prefer the original GIF payload before PNG/TIFF compatibility representations so
    // animated images never collapse to a single frame during capture.
    let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
    if preferences.captureImages, let imageData = pasteboard.data(forType: gifType),
      Self.hasGIFSignature(imageData)
    {
      if consumeIgnoreNextCopy() { return }
      let fallbackPNG = pasteboard.data(forType: .png)
      enqueueClipboardImage(
        data: imageData,
        source: source.name,
        sourceBundleIdentifier: source.bundleIdentifier,
        capturedAt: .now,
        requiresNormalization: false,
        validatesGIF: true,
        fallbackImageData: fallbackPNG ?? pasteboard.data(forType: .tiff),
        fallbackImageRequiresNormalization: fallbackPNG == nil,
        fallbackText: pasteboard.string(forType: .string),
        fallbackRichTextData: pasteboard.data(forType: .rtf)
      )
      return
    }

    if preferences.captureImages, let imageData = pasteboard.data(forType: .png) {
      if consumeIgnoreNextCopy() { return }
      enqueueClipboardImage(
        data: imageData,
        source: source.name,
        sourceBundleIdentifier: source.bundleIdentifier,
        capturedAt: .now,
        requiresNormalization: false,
        fallbackText: nil,
        fallbackRichTextData: nil
      )
      return
    }

    if preferences.captureImages, let imageData = pasteboard.data(forType: .tiff) {
      if consumeIgnoreNextCopy() { return }
      let fallbackText = pasteboard.string(forType: .string)
      enqueueClipboardImage(
        data: imageData,
        source: source.name,
        sourceBundleIdentifier: source.bundleIdentifier,
        capturedAt: .now,
        requiresNormalization: true,
        fallbackText: fallbackText,
        fallbackRichTextData: pasteboard.data(forType: .rtf)
      )
      return
    }

    if let string = pasteboard.string(forType: .string)?
      .trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty
    {
      if captureTextIfAllowed(
        string,
        source: source.name,
        sourceBundleIdentifier: source.bundleIdentifier,
        richTextData: pasteboard.data(forType: .rtf),
        htmlData: pasteboard.data(forType: .html)
      ) {
        playCaptureFeedbackIfEnabled()
      }
    }
  }

  @discardableResult
  func captureTextIfAllowed(
    _ rawText: String,
    source: String,
    sourceBundleIdentifier: String? = nil,
    richTextData: Data? = nil,
    htmlData: Data? = nil,
    createdAt: Date? = nil
  ) -> Bool {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return false }
    if let matchedRule = matchingPrivacyRule(for: text) {
      recordPrivacyRuleMatch(id: matchedRule.id)
      showNotice(
        L10n.text(
          "notice.ignored_privacy_rule",
          fallback: "Ignored copied text matching a privacy rule"
        ),
        systemImage: "hand.raised.fill"
      )
      return false
    }
    if preferences.protectSecrets, Self.looksSensitive(text) {
      showNotice(
        L10n.text(
          "notice.protected_secret", fallback: "Protected a likely password or secret"),
        systemImage: "hand.raised.fill")
      return false
    }
    if consumeIgnoreNextCopy() { return false }
    let validatedRichText = RichTextPayload.validated(richTextData, matching: text)
    addText(
      text,
      source: source,
      sourceBundleIdentifier: sourceBundleIdentifier,
      richTextData: validatedRichText,
      createdAt: createdAt
    )
    if validatedRichText == nil, let htmlData,
      let itemID = items.first(where: { $0.fingerprint == digest(Data(text.utf8)) })?.id
    {
      scheduleHTMLRichTextConversion(htmlData, matching: text, for: itemID)
    }
    return true
  }

  private func scheduleHTMLRichTextConversion(
    _ htmlData: Data,
    matching text: String,
    for itemID: UUID
  ) {
    guard isSessionActive, !htmlData.isEmpty,
      htmlData.count <= RichTextPayload.maximumHTMLBytes
    else { return }
    htmlRichTextConversionTasks[itemID]?.cancel()
    htmlRichTextConversionTasks[itemID] = Task { @MainActor [weak self] in
      let converted = await RichTextPayload.resolveHTMLInBackground(htmlData, matching: text)
      guard let self else { return }
      defer { self.htmlRichTextConversionTasks.removeValue(forKey: itemID) }
      guard !Task.isCancelled, self.isSessionActive, let converted,
        let index = self.items.firstIndex(where: { $0.id == itemID }),
        self.items[index].text == text,
        !self.items[index].hasRichText
      else { return }
      do {
        self.items[index].richTextFileName = try self.writeRichTextData(converted, for: itemID)
        self.items[index].richTextData = nil
        self.persist()
      } catch {
        self.setPersistenceIssue(error)
      }
    }
  }

  @discardableResult
  func addFiles(
    _ urls: [URL],
    source: String? = nil,
    sourceBundleIdentifier: String? = nil
  ) -> UUID? {
    guard !isUnlockingStorage else { return nil }
    var seen = Set<String>()
    let paths = urls.compactMap { url -> String? in
      guard url.isFileURL else { return nil }
      let path = url.standardizedFileURL.path
      guard !path.isEmpty, fileManager.fileExists(atPath: path), seen.insert(path).inserted else {
        return nil
      }
      return path
    }.prefix(Self.maximumFilesPerClip)
    let storedPaths = Array(paths)
    guard !storedPaths.isEmpty else { return nil }

    let fingerprint = fileFingerprint(storedPaths)
    let frontmost = source == nil ? frontmostApplication() : nil
    let sourceName = source ?? frontmost?.name ?? "Unknown app"
    let sourceBundleID = sourceBundleIdentifier ?? frontmost?.bundleIdentifier
    if let duplicateIndex = items.firstIndex(where: { $0.fingerprint == fingerprint }) {
      let existingID = items[duplicateIndex].id
      refreshDuplicate(
        at: duplicateIndex,
        source: sourceName,
        sourceBundleIdentifier: sourceBundleID
      )
      cacheAvailableFileReferences(
        itemID: existingID,
        fingerprint: fingerprint,
        paths: storedPaths
      )
      return existingID
    }
    let item = ClipItem(
      kind: .files,
      filePaths: storedPaths,
      boardIDs: automaticContextBoardIDs(for: sourceBundleID),
      sourceApplication: sourceName,
      sourceBundleIdentifier: sourceBundleID,
      fingerprint: fingerprint
    )
    insert(item)
    cacheAvailableFileReferences(itemID: item.id, fingerprint: fingerprint, paths: storedPaths)
    return items.first(where: { $0.fingerprint == fingerprint })?.id
  }

  func addText(
    _ text: String,
    source: String? = nil,
    sourceBundleIdentifier: String? = nil,
    isConcealed: Bool = false,
    customTitle: String? = nil,
    tags: [String] = [],
    boardIDs: [UUID] = [],
    richTextData: Data? = nil,
    createdAt: Date? = nil
  ) {
    guard !isUnlockingStorage else { return }
    let data = Data(text.utf8)
    let fingerprint = digest(data)
    let frontmost = source == nil ? frontmostApplication() : nil
    let sourceName = source ?? frontmost?.name ?? "Unknown app"
    let sourceBundleID = sourceBundleIdentifier ?? frontmost?.bundleIdentifier
    let capturedBoardIDs = normalizedBoardIDs(
      boardIDs + automaticContextBoardIDs(for: sourceBundleID)
    )
    let validatedRichText = RichTextPayload.validated(richTextData, matching: text)
    let automaticExpiration = TemporaryCodeDetector.expiration(
      for: text,
      enabled: preferences.expireLikelyCodes
    )
    if let duplicateIndex = items.firstIndex(where: { $0.fingerprint == fingerprint }) {
      if items[duplicateIndex].customTitle == nil {
        items[duplicateIndex].customTitle = customTitle
      }
      if let validatedRichText {
        do {
          items[duplicateIndex].richTextFileName = try writeRichTextData(
            validatedRichText,
            for: items[duplicateIndex].id
          )
          items[duplicateIndex].richTextData = nil
        } catch {
          setPersistenceIssue(error)
        }
      }
      items[duplicateIndex].tags = Self.normalizedTags(items[duplicateIndex].tags + tags)
      items[duplicateIndex].boardIDs = normalizedBoardIDs(
        items[duplicateIndex].boardIDs + capturedBoardIDs)
      items[duplicateIndex].isConcealed =
        items[duplicateIndex].isConcealed || isConcealed
      let extendsAutomaticExpiration =
        automaticExpiration != nil && items[duplicateIndex].expiresAt != nil
      if extendsAutomaticExpiration {
        items[duplicateIndex].expiresAt = latest(
          items[duplicateIndex].expiresAt,
          automaticExpiration
        )
      }
      refreshDuplicate(
        at: duplicateIndex,
        source: sourceName,
        sourceBundleIdentifier: sourceBundleID,
        createdAt: createdAt ?? .now
      )
      if extendsAutomaticExpiration { reportAutomaticCodeExpiration() }
      return
    }
    var item = ClipItem(
      kind: .text,
      text: text,
      customTitle: customTitle,
      tags: Self.normalizedTags(tags),
      boardIDs: capturedBoardIDs,
      isConcealed: isConcealed,
      sourceApplication: sourceName,
      sourceBundleIdentifier: sourceBundleID,
      createdAt: createdAt ?? .now,
      expiresAt: automaticExpiration,
      fingerprint: fingerprint
    )
    if let validatedRichText {
      do {
        item.richTextFileName = try writeRichTextData(validatedRichText, for: item.id)
      } catch {
        setPersistenceIssue(error)
      }
    }
    insert(item, preserveChronology: createdAt != nil)
    if automaticExpiration != nil { reportAutomaticCodeExpiration() }
  }

  func createEditedCopy(of item: ClipItem, text: String) -> EditedClipResult {
    guard let stored = items.first(where: { $0.id == item.id }) else { return .unchanged }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
    guard text.utf8.count <= Self.maximumEditedTextBytes else { return .tooLarge }
    let original = stored.kind == .text ? stored.text : stored.ocrText
    guard text != original else { return .unchanged }

    let fingerprint = digest(Data(text.utf8))
    let existingID = items.first(where: { $0.fingerprint == fingerprint })?.id
    let editedTitle = stored.customTitle.map {
      String("\($0) — edited".prefix(Self.maximumCustomTitleLength))
    }
    addText(
      text,
      source: "Edited in Clipskein",
      isConcealed: stored.isConcealed,
      customTitle: editedTitle,
      tags: stored.tags,
      boardIDs: stored.boardIDs
    )
    guard let editedIndex = items.firstIndex(where: { $0.fingerprint == fingerprint }) else {
      return .unchanged
    }
    let editedID = items[editedIndex].id
    if stored.isPinned, !items[editedIndex].isPinned {
      items[editedIndex].isPinned = true
      sortItems()
      persist()
    }
    searchText = ""
    filter = .all
    selectedTag = nil
    selectedBoardID = nil
    selectedID = editedID
    showNotice(
      existingID == nil
        ? L10n.text("notice.edited_copy_created", fallback: "Edited copy created")
        : L10n.text(
          "notice.edited_copy_reused", fallback: "Matching clip already existed"),
      systemImage: existingID == nil ? "square.and.pencil" : "arrow.triangle.2.circlepath"
    )
    return existingID == nil ? .created(editedID) : .reused(editedID)
  }

  @discardableResult
  func addImage(
    data: Data,
    source: String? = nil,
    sourceBundleIdentifier: String? = nil,
    createdAt: Date? = nil,
    onRecognition: ((OCRResult) -> Void)? = nil,
    onAnalysis: ((ImageAnalysisResult) -> Void)? = nil
  ) -> UUID? {
    guard !isUnlockingStorage else { return nil }
    if Self.hasGIFSignature(data), !ImageMetadata.isValidGIF(data) { return nil }
    let fingerprint = digest(data)
    let metadata = ImageMetadata.storedMetadata(for: data)
    let frontmost = source == nil ? frontmostApplication() : nil
    let sourceName = source ?? frontmost?.name ?? "Unknown app"
    let sourceBundleID = sourceBundleIdentifier ?? frontmost?.bundleIdentifier
    if let duplicateIndex = items.firstIndex(where: { $0.fingerprint == fingerprint }) {
      if items[duplicateIndex].imageMetadata == nil {
        items[duplicateIndex].imageMetadata = metadata
      }
      let existingID = items[duplicateIndex].id
      if let fileName = items[duplicateIndex].imageFileName {
        cacheImageData(data, fileName: fileName)
      }
      let existingOCRText = items[duplicateIndex].ocrText
      let existingOCRState = items[duplicateIndex].ocrState
      let existingOCRConfidence = items[duplicateIndex].ocrConfidence
      let existingBarcodes = items[duplicateIndex].detectedBarcodes
      refreshDuplicate(
        at: duplicateIndex,
        source: sourceName,
        sourceBundleIdentifier: sourceBundleID,
        createdAt: createdAt ?? .now
      )
      let existingResult: OCRResult?
      switch existingOCRState {
      case .complete:
        existingResult = .recognized(existingOCRText)
      case .noText:
        existingResult = .noText
      case .failed:
        existingResult = .failed
      case .pending, .notApplicable:
        existingResult = nil
      }
      if let existingResult {
        let analysis = ImageAnalysisResult(
          ocr: existingResult,
          barcodes: existingBarcodes,
          ocrConfidence: existingOCRConfidence
        )
        onAnalysis?(analysis)
        onRecognition?(existingResult)
      } else if onAnalysis != nil {
        deliverImageAnalysis(
          for: items[duplicateIndex],
          data: data,
          onAnalysis: onAnalysis
        )
      }
      return existingID
    }
    let id = UUID()
    let fileName = "\(id.uuidString).\(Self.imageFileExtension(for: data))"
    let destination = imagesURL.appendingPathComponent(fileName)
    do {
      try prepareStorage()
      try writeProtectedData(data, to: destination)
    } catch {
      try? fileManager.removeItem(at: destination)
      setPersistenceIssue(error)
      return nil
    }
    cacheImageData(data, fileName: fileName)

    let item = ClipItem(
      id: id,
      kind: .image,
      imageFileName: fileName,
      imageMetadata: metadata,
      boardIDs: automaticContextBoardIDs(for: sourceBundleID),
      isConcealed: preferences.protectSecrets,
      sourceApplication: sourceName,
      sourceBundleIdentifier: sourceBundleID,
      createdAt: createdAt ?? .now,
      fingerprint: fingerprint
    )
    insert(item, preserveChronology: createdAt != nil)

    recognizeImage(
      id: id,
      data: data,
      onRecognition: onRecognition,
      onAnalysis: onAnalysis
    )
    return id
  }

  private func addImageInBackground(
    data: Data,
    source: String,
    sourceBundleIdentifier: String? = nil,
    createdAt: Date = .now,
    refreshesDuplicates: Bool = true,
    onAnalysis: ((ImageAnalysisResult) -> Void)? = nil
  ) async -> BackgroundImageIngestResult {
    let prepared = await Task.detached(priority: .userInitiated) {
      PreparedClipboardImageData(
        data: data,
        fingerprint: SHA256.hash(data: data)
          .map { String(format: "%02x", $0) }
          .joined(),
        metadata: ImageMetadata.storedMetadata(for: data)
      )
    }.value
    guard !Task.isCancelled, isSessionActive else { return .failed }

    if let duplicateIndex = items.firstIndex(where: {
      $0.fingerprint == prepared.fingerprint
    }) {
      if items[duplicateIndex].imageMetadata == nil {
        items[duplicateIndex].imageMetadata = prepared.metadata
        invalidateDerivedCaches(for: items[duplicateIndex].id)
        if !refreshesDuplicates { persist() }
      }
      let duplicateID = items[duplicateIndex].id
      if refreshesDuplicates {
        refreshDuplicate(
          at: duplicateIndex,
          source: source,
          sourceBundleIdentifier: sourceBundleIdentifier,
          createdAt: createdAt
        )
      }
      if let duplicate = items.first(where: { $0.id == duplicateID }), refreshesDuplicates {
        deliverImageAnalysis(for: duplicate, data: prepared.data, onAnalysis: onAnalysis)
      }
      return .duplicate(duplicateID)
    }

    let id = UUID()
    let fileName = "\(id.uuidString).\(Self.imageFileExtension(for: prepared.data))"
    let destination = imagesURL.appendingPathComponent(fileName)
    let protector = storageProtector
    let requiresProtection = requiresStorageProtection
    let writer = clipboardImageWriter
    let writeError = await Task.detached(priority: .utility) {
      writer(prepared.data, destination, protector, requiresProtection)
    }.value
    guard !Task.isCancelled, isSessionActive else {
      if writeError == nil { try? FileManager.default.removeItem(at: destination) }
      return .failed
    }
    if let writeError {
      setPersistenceIssue(writeError)
      return .failed
    }
    if let duplicateIndex = items.firstIndex(where: {
      $0.fingerprint == prepared.fingerprint
    }) {
      try? FileManager.default.removeItem(at: destination)
      if items[duplicateIndex].imageMetadata == nil {
        items[duplicateIndex].imageMetadata = prepared.metadata
        invalidateDerivedCaches(for: items[duplicateIndex].id)
        if !refreshesDuplicates { persist() }
      }
      let duplicateID = items[duplicateIndex].id
      if refreshesDuplicates {
        refreshDuplicate(
          at: duplicateIndex,
          source: source,
          sourceBundleIdentifier: sourceBundleIdentifier,
          createdAt: createdAt
        )
      }
      if let duplicate = items.first(where: { $0.id == duplicateID }), refreshesDuplicates {
        deliverImageAnalysis(for: duplicate, data: prepared.data, onAnalysis: onAnalysis)
      }
      return .duplicate(duplicateID)
    }

    cacheImageData(prepared.data, fileName: fileName)
    let item = ClipItem(
      id: id,
      kind: .image,
      imageFileName: fileName,
      imageMetadata: prepared.metadata,
      boardIDs: automaticContextBoardIDs(for: sourceBundleIdentifier),
      isConcealed: preferences.protectSecrets,
      sourceApplication: source,
      sourceBundleIdentifier: sourceBundleIdentifier,
      createdAt: createdAt,
      fingerprint: prepared.fingerprint
    )
    insert(item, preserveChronology: true)
    recognizeImage(id: id, data: prepared.data, onAnalysis: onAnalysis)
    return .added(id)
  }

  private func deliverImageAnalysis(
    for item: ClipItem,
    data: Data,
    onAnalysis: ((ImageAnalysisResult) -> Void)?
  ) {
    guard let onAnalysis else { return }
    switch item.ocrState {
    case .pending, .notApplicable:
      recognizeImage(id: item.id, data: data, onAnalysis: onAnalysis)
    case .complete:
      onAnalysis(
        ImageAnalysisResult(
          ocr: .recognized(item.ocrText),
          barcodes: item.detectedBarcodes,
          ocrConfidence: item.ocrConfidence
        )
      )
    case .noText:
      onAnalysis(ImageAnalysisResult(ocr: .noText, barcodes: item.detectedBarcodes))
    case .failed:
      onAnalysis(ImageAnalysisResult(ocr: .failed, barcodes: item.detectedBarcodes))
    }
  }

  @discardableResult
  func retryOCR(_ item: ClipItem) -> Bool {
    guard let index = items.firstIndex(where: { $0.id == item.id }),
      items[index].kind == .image,
      items[index].needsOCRReview
    else { return false }
    guard let fileName = items[index].imageFileName else { return false }
    let cachedData = cachedImageData(for: items[index])
    if cachedData == nil,
      !fileManager.fileExists(atPath: imagesURL.appendingPathComponent(fileName).path)
    {
      showNotice(
        L10n.text(
          "notice.ocr_retry_unavailable",
          fallback: "The original screenshot is missing, so text recognition cannot be retried."
        ),
        systemImage: "exclamationmark.triangle.fill"
      )
      return false
    }
    items[index].ocrText = ""
    items[index].ocrState = .pending
    items[index].ocrConfidence = nil
    items[index].detectedBarcodes = []
    if preferences.protectSecrets { items[index].isConcealed = true }
    invalidateDerivedCaches(for: item.id)
    persist()
    if let cachedData {
      recognizeImage(id: item.id, data: cachedData)
    } else {
      // Cold screenshots may require disk I/O and decryption. Reuse the bounded
      // recovery queue so retrying never performs that work on the main actor.
      resumePendingImageAnalysis()
    }
    return true
  }

  @discardableResult
  func retryAllOCR() -> BulkOCRRetryResult {
    guard isSessionActive, bulkOCRRetryProgress == nil else {
      return BulkOCRRetryResult(scheduled: 0, unavailable: 0)
    }
    var cached: [(id: UUID, data: Data)] = []
    var scheduled = 0
    var unavailable = 0

    for index in items.indices
    where items[index].kind == .image
      && items[index].needsOCRReview
    {
      guard let fileName = items[index].imageFileName else {
        unavailable += 1
        continue
      }
      let cachedData = cachedImageData(for: items[index])
      guard cachedData != nil
        || fileManager.fileExists(atPath: imagesURL.appendingPathComponent(fileName).path)
      else {
        unavailable += 1
        continue
      }
      let id = items[index].id
      bulkOCRRetrySnapshots[id] = BulkOCRRetrySnapshot(
        ocrText: items[index].ocrText,
        ocrState: items[index].ocrState,
        ocrConfidence: items[index].ocrConfidence,
        detectedBarcodes: items[index].detectedBarcodes,
        isConcealed: items[index].isConcealed
      )
      items[index].ocrText = ""
      items[index].ocrState = .pending
      items[index].ocrConfidence = nil
      items[index].detectedBarcodes = []
      if preferences.protectSecrets { items[index].isConcealed = true }
      invalidateDerivedCaches(for: id)
      if let cachedData { cached.append((id, cachedData)) }
      scheduled += 1
    }

    guard scheduled > 0 else {
      if unavailable > 0 {
        showNotice(
          L10n.format(
            "notice.ocr_bulk_missing_only",
            fallback: "%d screenshots could not be retried because their originals are missing.",
            unavailable
          ),
          systemImage: "exclamationmark.triangle.fill"
        )
      }
      return BulkOCRRetryResult(scheduled: 0, unavailable: unavailable)
    }

    bulkOCRRetryProgress = BulkOCRRetryProgress(
      total: scheduled,
      completed: 0,
      recognized: 0,
      noText: 0,
      failed: 0,
      unavailable: unavailable,
      isCancelling: false
    )
    persist()
    cached.forEach { recognizeImage(id: $0.id, data: $0.data) }
    resumePendingImageAnalysis()
    showNotice(
      unavailable == 0
        ? L10n.format(
          "notice.ocr_bulk_started",
          fallback: "Retrying text recognition for %d screenshots.",
          scheduled
        )
        : L10n.format(
          "notice.ocr_bulk_started_with_missing",
          fallback: "%d screenshots queued · %d missing originals skipped.",
          scheduled,
          unavailable
        ),
      systemImage: unavailable == 0 ? "text.viewfinder" : "exclamationmark.triangle.fill"
    )
    return BulkOCRRetryResult(scheduled: scheduled, unavailable: unavailable)
  }

  func cancelBulkOCRRetry() {
    guard var progress = bulkOCRRetryProgress else { return }
    progress.isCancelling = true
    bulkOCRRetryProgress = progress
    let snapshots = bulkOCRRetrySnapshots

    for (id, snapshot) in snapshots {
      imageAnalysisTasks[id]?.cancel()
      imageAnalysisTasks[id] = nil
      imageAnalysisGenerations[id] = nil
      scheduledImageAnalysisIDs.remove(id)
      imageAnalysisCallbacks.removeValue(forKey: id)
      recoveryImageLoadTasks[id]?.cancel()
      recoveryImageLoadTasks[id] = nil
      recoveryImageLoadGenerations[id] = nil
      activeRecoveryImageIDs.remove(id)
      pendingRecoveryImageIDs.removeAll { $0 == id }
      guard let index = items.firstIndex(where: { $0.id == id }),
        items[index].ocrState == .pending
      else { continue }
      items[index].ocrText = snapshot.ocrText
      items[index].ocrState = snapshot.ocrState
      items[index].ocrConfidence = snapshot.ocrConfidence
      items[index].detectedBarcodes = snapshot.detectedBarcodes
      items[index].isConcealed = snapshot.isConcealed
      invalidateDerivedCaches(for: id)
    }

    bulkOCRRetrySnapshots.removeAll(keepingCapacity: false)
    bulkOCRRetryProgress = nil
    persist()
    startRecoveredImageAnalysisIfNeeded()
    showNotice(
      L10n.format(
        "notice.ocr_bulk_cancelled",
        fallback: "Stopped after %d/%d screenshots. Completed results were kept.",
        progress.completed,
        progress.total
      ),
      systemImage: "stop.circle.fill"
    )
  }

  private func recordBulkOCRRetryCompletion(id: UUID, result: OCRResult) {
    guard bulkOCRRetrySnapshots.removeValue(forKey: id) != nil,
      var progress = bulkOCRRetryProgress
    else { return }
    progress.completed += 1
    switch result {
    case .recognized: progress.recognized += 1
    case .noText: progress.noText += 1
    case .failed: progress.failed += 1
    }
    guard progress.completed >= progress.total else {
      bulkOCRRetryProgress = progress
      return
    }
    bulkOCRRetryProgress = nil
    showNotice(
      L10n.format(
        "notice.ocr_bulk_finished",
        fallback: "Recognition finished · %d found text · %d no text · %d failed",
        progress.recognized,
        progress.noText,
        progress.failed
      ),
      systemImage: progress.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    )
  }

  private func recognizeImage(
    id: UUID,
    data: Data,
    onRecognition: ((OCRResult) -> Void)? = nil,
    onAnalysis: ((ImageAnalysisResult) -> Void)? = nil,
    onCompletion: (() -> Void)? = nil
  ) {
    if let onAnalysis {
      imageAnalysisCallbacks[id, default: []].append(onAnalysis)
    }
    guard scheduledImageAnalysisIDs.insert(id).inserted else {
      onCompletion?()
      return
    }
    let analyzer = imageAnalyzer
    let preferredLanguages = preferences.ocrPreferredLanguages
    let customWords = preferences.ocrCustomWords
    let gate = imageAnalysisGate
    let generation = UUID()
    imageAnalysisGenerations[id] = generation
    imageAnalysisTasks[id] = Task { @MainActor [weak self] in
      let analyzed = await gate.run {
        let metadata = ImageMetadata.storedMetadata(for: data)
        let analysis = await analyzer(data, preferredLanguages, customWords)
        return (analysis: analysis, metadata: metadata)
      }
      guard let self else { return }
      var completedNormally = false
      defer {
        if self.imageAnalysisGenerations[id] == generation {
          self.imageAnalysisTasks[id] = nil
          self.imageAnalysisGenerations[id] = nil
          self.scheduledImageAnalysisIDs.remove(id)
          self.imageAnalysisCallbacks.removeValue(forKey: id)
          if completedNormally { onCompletion?() }
        }
      }
      guard let analyzed else { return }
      let analysis = analyzed.analysis
      guard !Task.isCancelled, self.isSessionActive,
        self.imageAnalysisGenerations[id] == generation
      else { return }
      completedNormally = true
      let result = analysis.ocr
      guard let index = items.firstIndex(where: { $0.id == id }) else { return }
      if items[index].imageMetadata?.frameCount == nil {
        items[index].imageMetadata = analyzed.metadata
      }
      items[index].detectedBarcodes = DetectedBarcode.normalized(analysis.barcodes)
      switch result {
      case .recognized(let text):
        items[index].ocrText = text
        items[index].ocrState = .complete
        items[index].ocrConfidence = analysis.ocrConfidence
      case .noText:
        items[index].ocrState = .noText
        items[index].ocrConfidence = nil
      case .failed:
        items[index].ocrState = .failed
        items[index].ocrConfidence = nil
        if preferences.protectSecrets {
          showNotice(
            L10n.text(
              "notice.ocr_unverified_preview",
              fallback: "Screenshot preview concealed because text could not be checked"
            ),
            systemImage: "eye.slash.fill"
          )
        }
      }
      if result != .failed {
        let recognizedContent = ([items[index].ocrText] + items[index].detectedBarcodes.map(\.payload))
          .filter { !$0.isEmpty }
          .joined(separator: "\n")
        // OCR analyzes only the first frame. It cannot clear the privacy check for
        // an animation whose later frames may contain secrets.
        let hasUncheckedFrames = (items[index].imageMetadata?.frameCount ?? 1) > 1
          || (items[index].isGIF && items[index].imageMetadata?.frameCount == nil)
        let shouldConceal = (preferences.protectSecrets && hasUncheckedFrames)
          || Self.shouldConcealRecognizedText(
            recognizedContent,
            protectionEnabled: preferences.protectSecrets
          )
        items[index].isConcealed = shouldConceal
        items[index].expiresAt = TemporaryCodeDetector.expiration(
          for: recognizedContent,
          enabled: preferences.expireLikelyCodes
        )
        if shouldConceal {
          showNotice(
            L10n.text(
              hasUncheckedFrames ? "notice.ocr_unverified_preview" : "notice.ocr_sensitive_preview",
              fallback: hasUncheckedFrames
                ? "Screenshot preview concealed because text could not be checked"
                : "Sensitive text detected; screenshot preview concealed"
            ),
            systemImage: "eye.slash.fill"
          )
        } else if items[index].expiresAt != nil {
          reportAutomaticCodeExpiration()
        }
      }
      invalidateDerivedCaches(for: id)
      persist()
      let callbacks = imageAnalysisCallbacks.removeValue(forKey: id) ?? []
      callbacks.forEach { $0(analysis) }
      onRecognition?(result)
      recordBulkOCRRetryCompletion(id: id, result: result)
    }
  }

  private func resumePendingImageAnalysis() {
    let alreadyQueued = Set(pendingRecoveryImageIDs)
      .union(activeRecoveryImageIDs)
      .union(scheduledImageAnalysisIDs)
    pendingRecoveryImageIDs.append(contentsOf: items.compactMap { item in
      item.kind == .image && item.ocrState == .pending && !alreadyQueued.contains(item.id)
        ? item.id : nil
    })
    startRecoveredImageAnalysisIfNeeded()
  }

  private func startRecoveredImageAnalysisIfNeeded() {
    while activeRecoveryImageIDs.count < imageAnalysisGate.maximumConcurrent,
      !pendingRecoveryImageIDs.isEmpty
    {
      let id = pendingRecoveryImageIDs.removeFirst()
      guard let item = items.first(where: { $0.id == id }),
        let fileName = item.imageFileName
      else { continue }
      activeRecoveryImageIDs.insert(id)
      let generation = UUID()
      recoveryImageLoadGenerations[id] = generation
      let url = imagesURL.appendingPathComponent(fileName)
      let protector = storageProtector
      let requiresProtection = requiresStorageProtection
      let loader = storedImageDataLoader
      recoveryImageLoadTasks[id] = Task { @MainActor [weak self] in
        let result = await Task.detached(priority: .utility) {
          loader(url, protector, requiresProtection)
        }.value
        guard let self else { return }
        var transferredToAnalysis = false
        defer {
          if self.recoveryImageLoadGenerations[id] == generation {
            self.recoveryImageLoadTasks[id] = nil
            self.recoveryImageLoadGenerations[id] = nil
            if !transferredToAnalysis {
              self.activeRecoveryImageIDs.remove(id)
              if self.isSessionActive { self.startRecoveredImageAnalysisIfNeeded() }
            }
          }
        }
        guard !Task.isCancelled, self.isSessionActive,
          self.recoveryImageLoadGenerations[id] == generation,
          let current = self.items.first(where: { $0.id == id }),
          current.ocrState == .pending
        else { return }
        switch result {
        case .success(let data):
          self.cacheImageData(data, fileName: fileName)
          transferredToAnalysis = true
          self.recognizeImage(id: id, data: data, onCompletion: { [weak self] in
            guard let self else { return }
            self.activeRecoveryImageIDs.remove(id)
            self.startRecoveredImageAnalysisIfNeeded()
          })
        case .failure(let error, let secureStorageFailure):
          if secureStorageFailure { self.persistenceBlockedByUnreadableHistory = true }
          self.setPersistenceIssue(error)
          if let index = self.items.firstIndex(where: { $0.id == id }) {
            self.items[index].ocrState = .failed
            self.items[index].ocrConfidence = nil
            self.invalidateDerivedCaches(for: id)
            self.persist()
          }
          self.recordBulkOCRRetryCompletion(id: id, result: .failed)
        }
      }
    }
  }

  private func invalidateDerivedCaches(for id: UUID) {
    contentKindCache.removeValue(forKey: id)
    searchIndexCache.removeValue(forKey: id)
    quickPickerRecommendationCache.removeAll(keepingCapacity: true)
  }

  private func purgeChangedSemanticVectors(
    previousItems: [ClipItem],
    currentItems: [ClipItem]
  ) {
    guard !previousItems.isEmpty else { return }
    let currentByID = Dictionary(uniqueKeysWithValues: currentItems.map { ($0.id, $0) })
    let removedOrChanged = Set(previousItems.compactMap { previous -> UUID? in
      guard let current = currentByID[previous.id] else { return previous.id }
      guard !current.isConcealed else { return previous.id }
      return Self.semanticSourceChanged(from: previous, to: current) ? previous.id : nil
    })
    guard !removedOrChanged.isEmpty else { return }
    let semanticSearchIndex = semanticSearchIndex
    Task { await semanticSearchIndex.remove(ids: removedOrChanged) }
  }

  nonisolated private static func semanticSourceChanged(
    from previous: ClipItem,
    to current: ClipItem
  ) -> Bool {
    previous.kind != current.kind
      || previous.text != current.text
      || previous.ocrText != current.ocrText
      || previous.detectedBarcodes != current.detectedBarcodes
      || previous.filePaths != current.filePaths
      || previous.customTitle != current.customTitle
      || previous.tags != current.tags
      || previous.sourceApplication != current.sourceApplication
      || previous.sourceBundleIdentifier != current.sourceBundleIdentifier
  }

  private func discardSensitiveDerivedContentCaches() {
    semanticSearchTask?.cancel()
    semanticSearchTask = nil
    semanticSearchTaskKey = nil
    semanticSearchResultKey = nil
    semanticSearchResultIDs.removeAll()
    semanticSearchResultScores.removeAll()
    semanticSearchStatus = .inactive
    semanticSearchRevision &+= 1
    let semanticSearchIndex = semanticSearchIndex
    Task { await semanticSearchIndex.removeAll() }
    quickPasteActionTasks.values.forEach { $0.cancel() }
    quickPasteActionTasks.removeAll()
    quickPasteActionGenerations.removeAll()
    quickPasteActionCache.removeAll()
    searchIndexCache.removeAll()
    searchResultsCache = nil
    quickPickerRecommendationCache.removeAll()
    stackItemsCache = nil
  }

  var cachedSensitiveDerivedContentCount: Int {
    quickPasteActionCache.count + searchIndexCache.count
  }

  func importImage() {
    guard imageImportProgress == nil else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
    panel.allowsMultipleSelection = true
    panel.message = L10n.text(
      "capture.import_message", fallback: "Choose screenshots to add to your searchable history.")
    guard panel.runModal() == .OK else { return }
    importImages(panel.urls)
  }

  func discoverExistingScreenshotURLs(
    limit: Int = ScreenshotInbox.maximumExistingImportCount
  ) async -> [URL] {
    guard isSessionActive, imageImportProgress == nil else { return [] }
    let directory = screenshotDirectoryOverride ?? ScreenshotInbox.configuredDirectory()
    let loader = screenshotSnapshotLoader
    let result = await Task.detached(priority: .utility) { loader(directory) }.value
    guard !Task.isCancelled, isSessionActive else { return [] }
    guard case .success(let snapshots) = result else {
      showNotice(
        L10n.text(
          "screenshot_import.discovery_failed",
          fallback: "Clipskein could not read the screenshot folder"
        ),
        systemImage: "folder.badge.questionmark"
      )
      return []
    }
    let candidates = ScreenshotInbox.existingImportCandidates(
      from: snapshots,
      limit: limit
    )
    if candidates.isEmpty {
      showNotice(
        L10n.text(
          "screenshot_import.none_found",
          fallback: "No existing screenshots found in the configured folder"
        ),
        systemImage: "photo.stack"
      )
    }
    return candidates.map(\.url)
  }

  func importImages(_ urls: [URL]) {
    guard imageImportProgress == nil else { return }
    var seen = Set<String>()
    let files = urls.compactMap { url -> URL? in
      let standardized = url.standardizedFileURL
      guard standardized.isFileURL, seen.insert(standardized.path).inserted else { return nil }
      return standardized
    }
    guard !files.isEmpty else { return }

    lastImageImportResult = nil
    recoverableImageImportURLs.removeAll(keepingCapacity: false)
    imageImportProgress = ImageImportProgress(
      total: files.count,
      completed: 0,
      imported: 0,
      duplicates: 0,
      unreadable: 0,
      failed: 0,
      isCancelling: false
    )
    let loader = screenshotImageDataLoader
    let source = "Imported screenshot"
    imageImportTask = Task { @MainActor [weak self] in
      guard let self else { return }
      var problemURLs: [URL] = []
      for url in files {
        if Task.isCancelled { break }
        let data = await Task.detached(priority: .utility) { loader(url) }.value
        if Task.isCancelled { break }
        guard var progress = imageImportProgress else { break }
        guard let data else {
          progress.completed += 1
          progress.unreadable += 1
          problemURLs.append(url)
          imageImportProgress = progress
          continue
        }
        let result = await addImageInBackground(
          data: data,
          source: source,
          refreshesDuplicates: false
        )
        if Task.isCancelled, case .failed = result { break }
        progress.completed += 1
        switch result {
        case .added:
          progress.imported += 1
        case .duplicate:
          progress.duplicates += 1
        case .failed:
          progress.failed += 1
          problemURLs.append(url)
        }
        imageImportProgress = progress
        if Task.isCancelled { break }
      }
      let completed = imageImportProgress?.completed ?? 0
      let remainingURLs = Task.isCancelled ? Array(files.dropFirst(completed)) : []
      finishImageImport(
        cancelled: Task.isCancelled,
        recoverableURLs: problemURLs + remainingURLs
      )
    }
  }

  func cancelImageImport() {
    guard var progress = imageImportProgress else { return }
    progress.isCancelling = true
    imageImportProgress = progress
    imageImportTask?.cancel()
  }

  func dismissImageImportResult() {
    lastImageImportResult = nil
    recoverableImageImportURLs.removeAll(keepingCapacity: false)
  }

  var recoverableImageImportCount: Int { recoverableImageImportURLs.count }

  func retryLastImageImport() {
    guard imageImportProgress == nil, !recoverableImageImportURLs.isEmpty else { return }
    let urls = recoverableImageImportURLs
    recoverableImageImportURLs.removeAll(keepingCapacity: false)
    lastImageImportResult = nil
    importImages(urls)
  }

  private func finishImageImport(cancelled: Bool, recoverableURLs: [URL] = []) {
    guard let progress = imageImportProgress else {
      imageImportTask = nil
      return
    }
    imageImportProgress = nil
    imageImportTask = nil
    if isSessionActive {
      var seen = Set<String>()
      recoverableImageImportURLs = recoverableURLs.filter {
        seen.insert($0.standardizedFileURL.path).inserted
      }
    } else {
      recoverableImageImportURLs.removeAll(keepingCapacity: false)
    }
    lastImageImportResult = ImageImportResult(
      total: progress.total,
      completed: progress.completed,
      imported: progress.imported,
      duplicates: progress.duplicates,
      unreadable: progress.unreadable,
      failed: progress.failed,
      wasCancelled: cancelled
    )
  }

  func captureRegion() {
    guard isSessionActive else { return }
    guard !isCapturingRegion else {
      showNotice(
        L10n.text(
          "capture.already_running", fallback: "Finish or cancel the current Screen OCR selection"),
        systemImage: "viewfinder")
      return
    }
    isCapturingRegion = true
    let captureURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("Clipskein-Capture-\(UUID().uuidString).png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-i", "-o", captureURL.path]
    regionCaptureProcess = process
    process.terminationHandler = { [weak self] process in
      let data = process.terminationStatus == 0 ? try? Data(contentsOf: captureURL) : nil
      try? FileManager.default.removeItem(at: captureURL)
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.regionCaptureProcess = nil
        guard self.isSessionActive else {
          self.isCapturingRegion = false
          return
        }
        guard let data else {
          self.isCapturingRegion = false
          self.showNotice(
            L10n.text("capture.cancelled", fallback: "Screen OCR cancelled"),
            systemImage: "xmark.circle")
          return
        }
        self.regionCaptureIngestionTask = Task { @MainActor [weak self] in
          guard let self else { return }
          _ = await self.addImageInBackground(
            data: data,
            source: "Region capture",
            onAnalysis: { [weak self] analysis in
              self?.handleRegionAnalysis(analysis)
            }
          )
          self.regionCaptureIngestionTask = nil
          self.isCapturingRegion = false
        }
      }
    }
    do {
      try process.run()
    } catch {
      regionCaptureProcess = nil
      isCapturingRegion = false
      showNotice(
        L10n.text(
          "capture.start_failed",
          fallback: "Could not start Screen OCR. Check Screen Recording permission and try again."),
        systemImage: "exclamationmark.triangle.fill")
    }
  }

  func reportScreenOCRShortcutRegistration(_ succeeded: Bool) {
    screenOCRShortcutRegistrationSucceeded = succeeded
  }

  func reportQuickPickerShortcutRegistration(_ succeeded: Bool) {
    quickPickerShortcutRegistrationSucceeded = succeeded
  }

  func reportSnippetShortcutRegistration(_ succeeded: Bool) {
    snippetShortcutRegistrationSucceeded = succeeded
  }

  func reportNewSnippetShortcutRegistration(_ succeeded: Bool) {
    newSnippetShortcutRegistrationSucceeded = succeeded
  }

  func reportTextActionShortcutRegistration(_ succeeded: Bool) {
    textActionShortcutRegistrationSucceeded = succeeded
  }

  func captureSelectedText(
    from application: NSRunningApplication?,
    maximumCharacters: Int? = TextTransformer.maximumInputLength,
    maximumUTF8Bytes: Int? = nil
  ) async -> SelectedTextCaptureResult {
    guard isSessionActive else { return .noSelection }
    guard let application, !application.isTerminated else { return .noSelection }
    guard !preferences.isExcluded(bundleIdentifier: application.bundleIdentifier) else {
      return .protectedApplication
    }
    guard AXIsProcessTrusted() else { return .permissionRequired }
    guard let snapshot = PasteboardSnapshot.capture(from: pasteboard) else {
      return .clipboardPreservationUnavailable
    }

    let beforeChangeCount = pasteboard.changeCount
    isCapturingSelectedText = true
    defer { isCapturingSelectedText = false }
    guard SelectedTextCapture.postCopyShortcut() else { return .noSelection }

    for _ in 0..<8 {
      try? await Task.sleep(for: .milliseconds(25))
      if pasteboard.changeCount != beforeChangeCount { break }
    }
    let afterChangeCount = pasteboard.changeCount
    guard afterChangeCount != beforeChangeCount else { return .noSelection }
    let selectedText = pasteboard.string(forType: .string)
    let selectedRTF = pasteboard.data(forType: .rtf)
    let selectedHTML = pasteboard.data(forType: .html)
    let selectionTooLarge = selectedText.map {
      SelectedTextCapture.exceedsLimit(
        $0,
        maximumCharacters: maximumCharacters,
        maximumUTF8Bytes: maximumUTF8Bytes)
    } ?? false
    var item = SelectedTextCapture.item(
      beforeChangeCount: beforeChangeCount,
      afterChangeCount: afterChangeCount,
      text: selectedText,
      richTextData: selectedRTF,
      sourceName: application.localizedName ?? "Selected text",
      sourceBundleIdentifier: application.bundleIdentifier,
      maximumCharacters: maximumCharacters,
      maximumUTF8Bytes: maximumUTF8Bytes
    )
    let restored = snapshot.restore(to: pasteboard, ifUnchangedFrom: afterChangeCount)
    if restored {
      lastChangeCount = pasteboard.changeCount
    } else if pasteboard.changeCount == afterChangeCount {
      lastChangeCount = afterChangeCount
    }
    guard item != nil else { return selectionTooLarge ? .selectionTooLarge : .noSelection }
    if item?.richTextData == nil, let selectedHTML, let selectedText {
      let converted = await RichTextPayload.resolveHTMLInBackground(
        selectedHTML,
        matching: selectedText
      )
      guard !Task.isCancelled, isSessionActive else { return .noSelection }
      item?.richTextData = converted
    }
    guard let item else { return .noSelection }
    return .captured(item)
  }

  @discardableResult
  func copy(
    _ item: ClipItem,
    fileWriteOperation: (([URL]) -> Bool)? = nil
  ) -> Bool {
    cancelSecureClipboardClear()
    let didCopy: Bool
    switch item.kind {
    case .text:
      return copyText(item.text, richTextData: richTextData(for: item), recording: item)
    case .image:
      guard let image = decodedImage(for: item) else { return false }
      didCopy = writeImageToPasteboard(
        image,
        originalData: cachedImageData(for: item)
      )
    case .files:
      let urls = existingFileURLs(for: item)
      guard urls.count == item.filePaths.count else {
        showNotice(
          L10n.text(
            "notice.file_reference_missing",
            fallback: "A referenced file is no longer available"
          ),
          systemImage: "doc.badge.exclamationmark")
        return false
      }
      if let fileWriteOperation {
        didCopy = fileWriteOperation(urls)
      } else {
        didCopy = writeFileURLsToPasteboard(urls)
      }
    }
    guard didCopy else { return false }
    annotatePasteboardWrite()
    lastChangeCount = pasteboard.changeCount
    recordUse(for: item)
    return true
  }

  /// Copies any clip without making a cold encrypted image read block the main actor.
  /// Privacy suspension invalidates the pending result before it can reach the pasteboard.
  func copyForUse(_ item: ClipItem, securely: Bool = false) async -> Bool {
    guard item.kind == .image else {
      return securely ? secureCopy(item) : copy(item)
    }
    guard isSessionActive,
      let stored = items.first(where: { $0.id == item.id }),
      stored.kind == .image,
      let fileName = stored.imageFileName
    else { return false }

    if cachedDecodedImage(for: stored) != nil {
      return securely ? secureCopy(stored) : copy(stored)
    }
    guard imageCopyTask == nil else { return false }

    let generation = UUID()
    let loader = storedImageDataLoader
    let source = imagesURL.appendingPathComponent(fileName)
    let protector = storageProtector
    let requiresProtection = requiresStorageProtection
    let task = Task.detached(priority: .userInitiated) {
      loader(source, protector, requiresProtection)
    }
    imageCopyGeneration = generation
    imageCopyTask = task
    preparingImageCopyID = stored.id
    let result = await task.value
    guard imageCopyGeneration == generation else { return false }
    imageCopyTask = nil
    imageCopyGeneration = nil
    preparingImageCopyID = nil

    guard isSessionActive,
      let current = items.first(where: { $0.id == stored.id }),
      current.kind == .image,
      current.imageFileName == fileName
    else { return false }

    let data: Data
    switch result {
    case .success(let loaded):
      data = loaded
    case .failure(let error, let secureStorageFailure):
      if secureStorageFailure { persistenceBlockedByUnreadableHistory = true }
      setPersistenceIssue(error)
      return false
    }
    guard let image = NSImage(data: data) else {
      failedImageLoads.insert(fileName)
      imageCacheRevision &+= 1
      return false
    }
    cacheImageData(data, fileName: fileName)
    decodedImageCache.setObject(
      image,
      forKey: fileName as NSString,
      cost: decodedImageCost(image)
    )
    imageCacheRevision &+= 1
    return securely ? secureCopy(current) : copy(current)
  }

  func cancelImageCopyPreparation() {
    imageCopyTask?.cancel()
    imageCopyTask = nil
    imageCopyGeneration = nil
    preparingImageCopyID = nil
  }

  func existingFileURLs(for item: ClipItem) -> [URL] {
    guard item.kind == .files else { return [] }
    return item.filePaths.compactMap { path in
      guard fileManager.fileExists(atPath: path) else { return nil }
      return URL(fileURLWithPath: path)
    }
  }

  func fileReferenceStatus(for path: String, in item: ClipItem) -> FileReferenceStatus {
    guard item.kind == .files, item.filePaths.contains(path),
      let availability = fileReferenceAvailability,
      availability.itemID == item.id,
      availability.fingerprint == item.fingerprint,
      let existingPaths = availability.existingPaths
    else { return .checking }
    return existingPaths.contains(path) ? .available : .missing
  }

  func refreshFileReferenceAvailability(for item: ClipItem, force: Bool = false) {
    guard item.kind == .files,
      let stored = items.first(where: { $0.id == item.id }),
      stored.fingerprint == item.fingerprint
    else { return }
    if !force,
      let availability = fileReferenceAvailability,
      availability.itemID == stored.id,
      availability.fingerprint == stored.fingerprint
    {
      if availability.existingPaths == nil {
        return
      }
      if let checkedAt = availability.checkedAt,
        Date().timeIntervalSince(checkedAt) < 5
      {
        return
      }
    }
    fileReferenceCheckTask?.cancel()
    fileReferenceAvailability = FileReferenceAvailability(
      itemID: stored.id,
      fingerprint: stored.fingerprint,
      existingPaths: nil,
      checkedAt: nil
    )
    let itemID = stored.id
    let fingerprint = stored.fingerprint
    let paths = stored.filePaths
    let checker = fileReferenceChecker
    fileReferenceCheckTask = Task { @MainActor [weak self] in
      let existingPaths = await Task.detached(priority: .utility) {
        checker(paths)
      }.value
      guard let self, !Task.isCancelled,
        let current = self.items.first(where: { $0.id == itemID }),
        current.fingerprint == fingerprint
      else { return }
      self.fileReferenceAvailability = FileReferenceAvailability(
        itemID: itemID,
        fingerprint: fingerprint,
        existingPaths: existingPaths,
        checkedAt: .now
      )
      self.fileReferenceRevision &+= 1
      self.fileReferenceCheckTask = nil
    }
  }

  private func cacheAvailableFileReferences(
    itemID: UUID,
    fingerprint: String,
    paths: [String]
  ) {
    fileReferenceAvailability = FileReferenceAvailability(
      itemID: itemID,
      fingerprint: fingerprint,
      existingPaths: Set(paths),
      checkedAt: .now
    )
  }

  @discardableResult
  func copyText(
    _ text: String,
    richTextData: Data? = nil,
    recording item: ClipItem
  ) -> Bool {
    cancelSecureClipboardClear()
    guard let pasteboardItem = textPasteboardItem(text, richTextData: richTextData) else {
      return false
    }
    pasteboard.clearContents()
    guard pasteboard.writeObjects([pasteboardItem]) else { return false }
    annotatePasteboardWrite()
    lastChangeCount = pasteboard.changeCount
    recordUse(for: item)
    return true
  }

  @discardableResult
  func copyAutomationLink(_ link: ClipNestDeepLink) -> Bool {
    guard let url = link.url else { return false }
    cancelSecureClipboardClear()
    pasteboard.clearContents()
    guard pasteboard.setString(url.absoluteString, forType: .string) else { return false }
    annotatePasteboardWrite()
    lastChangeCount = pasteboard.changeCount
    return true
  }

  @discardableResult
  func copyGeneratedText(_ text: String) -> Bool {
    guard isSessionActive, text.utf8.count <= 2_000_000,
      let pasteboardItem = textPasteboardItem(text, richTextData: nil)
    else { return false }
    cancelSecureClipboardClear()
    pasteboard.clearContents()
    guard pasteboard.writeObjects([pasteboardItem]) else { return false }
    annotatePasteboardWrite()
    lastChangeCount = pasteboard.changeCount
    return true
  }

  @discardableResult
  func secureCopy(_ item: ClipItem, clearAfter seconds: TimeInterval = 60) -> Bool {
    guard copy(item) else { return false }
    scheduleSecureClipboardClear(after: seconds)
    return true
  }

  @discardableResult
  func secureCopyText(
    _ text: String,
    recording item: ClipItem,
    clearAfter seconds: TimeInterval = 60
  ) -> Bool {
    guard copyText(text, recording: item) else { return false }
    scheduleSecureClipboardClear(after: seconds)
    return true
  }

  func keepSecureCopyOnClipboard() {
    guard secureCopyExpiration != nil else { return }
    cancelSecureClipboardClear()
    showNotice(
      L10n.text("notice.secure_copy_cancelled", fallback: "Clipboard auto-clear cancelled"),
      systemImage: "clipboard.fill")
  }

  func canAddToStack(_ item: ClipItem) -> Bool {
    !ClipStackComposer.content(for: item).isEmpty
  }

  func isInStack(_ item: ClipItem) -> Bool {
    stackIDs.contains(item.id)
  }

  func toggleStackMembership(_ item: ClipItem) {
    if let index = stackIDs.firstIndex(of: item.id) {
      stackIDs.remove(at: index)
      persistStack()
      showNotice(
        L10n.text("notice.stack_removed", fallback: "Removed from Stack"),
        systemImage: "minus.circle.fill")
      return
    }
    guard canAddToStack(item) else {
      showNotice(
        L10n.text("notice.stack_no_text", fallback: "This clip has no text to add"),
        systemImage: "text.badge.xmark")
      return
    }
    guard stackIDs.count < Self.maximumStackCount else {
      showNotice(
        L10n.format(
          "notice.stack_limit", fallback: "Stack can hold up to %d clips", Self.maximumStackCount),
        systemImage: "tray.full")
      return
    }
    stackIDs.append(item.id)
    persistStack()
    showNotice(
      L10n.text("notice.stack_added", fallback: "Added to Stack"),
      systemImage: "square.stack.3d.up.fill")
  }

  @discardableResult
  func addItemsToStack(_ candidates: [ClipItem]) -> Int {
    let availableSlots = max(0, Self.maximumStackCount - stackIDs.count)
    guard availableSlots > 0 else {
      showNotice(
        L10n.format(
          "notice.stack_limit", fallback: "Stack can hold up to %d clips", Self.maximumStackCount),
        systemImage: "tray.full")
      return 0
    }

    let liveItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    var seenIDs = Set(stackIDs)
    var additions: [UUID] = []
    additions.reserveCapacity(min(availableSlots, candidates.count))
    for candidate in candidates {
      guard additions.count < availableSlots,
        seenIDs.insert(candidate.id).inserted,
        let current = liveItems[candidate.id],
        canAddToStack(current)
      else { continue }
      additions.append(current.id)
    }

    guard !additions.isEmpty else {
      showNotice(
        L10n.text(
          "notice.stack_batch_unchanged", fallback: "No new results to add to Stack"),
        systemImage: "checkmark.circle")
      return 0
    }
    let previousIDs = stackIDs
    stackIDs.append(contentsOf: additions)
    persistStack()
    showNotice(
      L10n.format(
        "notice.stack_batch_added", fallback: "Added %d results to Stack", additions.count),
      systemImage: "square.stack.3d.up.fill",
      action: .undoStackCollection(previousIDs: previousIDs))
    return additions.count
  }

  func clearStack() {
    guard !stackIDs.isEmpty else { return }
    stackIDs = []
    persistStack()
    showNotice(
      L10n.text("notice.stack_cleared", fallback: "Stack cleared; history unchanged"),
      systemImage: "trash")
  }

  @discardableResult
  func copyNextStackItem(
    copyOperation: ((String, ClipItem) -> Bool)? = nil
  ) -> Bool {
    guard let id = stackIDs.first,
      let item = items.first(where: { $0.id == id })
    else {
      pruneStack()
      showNotice(L10n.text("notice.stack_empty", fallback: "Stack is empty"), systemImage: "tray")
      return false
    }
    let text = ClipStackComposer.content(for: item)
    guard !text.isEmpty else {
      showNotice(
        L10n.text(
          "notice.stack_next_no_text", fallback: "Next Stack item has no available text"),
        systemImage: "text.badge.xmark")
      return false
    }

    let didCopy = copyOperation?(text, item) ?? copyText(text, recording: item)
    guard didCopy else {
      showNotice(
        L10n.text(
          "notice.stack_copy_failed", fallback: "Next Stack item could not be copied; try again"),
        systemImage: "exclamationmark.triangle.fill")
      return false
    }
    if item.isConcealed { scheduleSecureClipboardClear(after: 60) }

    lastConsumedStackEntry = (id, 0)
    stackIDs.removeFirst()
    persistStack()
    let remaining = stackIDs.count
    showNotice(
      remaining == 0
        ? L10n.text("notice.stack_final_copied", fallback: "Copied final Stack item")
        : L10n.format(
          "notice.stack_next_copied", fallback: "Copied next — %d remaining", remaining),
      systemImage: item.isConcealed ? "timer" : "arrow.right.circle.fill",
      action: .undoStackAdvance
    )
    return true
  }

  func undoLastStackAdvance() {
    guard let entry = lastConsumedStackEntry,
      items.contains(where: { $0.id == entry.id }),
      !stackIDs.contains(entry.id)
    else { return }
    stackIDs.insert(entry.id, at: min(entry.index, stackIDs.count))
    lastConsumedStackEntry = nil
    persistStack()
    showNotice(
      L10n.text("notice.stack_restored", fallback: "Restored item to Stack"),
      systemImage: "arrow.uturn.backward.circle.fill")
  }

  func moveStackItem(_ item: ClipItem, by offset: Int) {
    guard offset != 0, let sourceIndex = stackIDs.firstIndex(of: item.id) else { return }
    let destinationIndex = sourceIndex + offset
    guard stackIDs.indices.contains(destinationIndex) else { return }
    let id = stackIDs.remove(at: sourceIndex)
    stackIDs.insert(id, at: destinationIndex)
    persistStack()
  }

  @discardableResult
  func saveCurrentView(named rawName: String) -> Bool {
    guard canSaveCurrentView else {
      showNotice(
        L10n.text("notice.view_requires_filter", fallback: "Choose a search or filter first"),
        systemImage: "bookmark.slash")
      return false
    }
    let name = Self.normalizedSavedViewName(rawName)
    guard !name.isEmpty else { return false }
    let query = String(
      searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        .prefix(SavedClipView.maximumQueryLength)
    )

    if let index = savedViews.firstIndex(where: {
      $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
    }) {
      let existing = savedViews[index]
      savedViews[index] = SavedClipView(
        id: existing.id,
        name: name,
        query: query,
        filter: filter,
        tag: selectedTag,
        boardID: selectedBoardID,
        interpretsNaturalLanguage: !searchAsLiteral
      )
      persistSavedViews()
      showNotice(
        L10n.text("notice.view_updated", fallback: "Saved view updated"),
        systemImage: "bookmark.fill")
      return true
    }

    guard savedViews.count < SavedClipView.maximumCount else {
      showNotice(
        L10n.format(
          "notice.view_limit", fallback: "Keep up to %d saved views", SavedClipView.maximumCount),
        systemImage: "bookmark.slash"
      )
      return false
    }
    savedViews.append(
      SavedClipView(
        name: name,
        query: query,
        filter: filter,
        tag: selectedTag,
        boardID: selectedBoardID,
        interpretsNaturalLanguage: !searchAsLiteral
      )
    )
    persistSavedViews()
    showNotice(L10n.text("notice.view_saved", fallback: "View saved"), systemImage: "bookmark.fill")
    return true
  }

  func applySavedView(_ view: SavedClipView) {
    guard savedViews.contains(where: { $0.id == view.id }) else { return }
    searchText = view.query
    filter = view.filter
    selectedTag = view.tag
    selectedBoardID = view.boardID.flatMap { id in
      boards.contains(where: { $0.id == id }) ? id : nil
    }
    searchAsLiteral = !view.interpretsNaturalLanguage
    normalizeSelection()
  }

  func deleteSavedView(_ view: SavedClipView) {
    guard savedViews.contains(where: { $0.id == view.id }) else { return }
    savedViews.removeAll { $0.id == view.id }
    persistSavedViews()
    showNotice(
      L10n.text("notice.view_removed", fallback: "Saved view removed"),
      systemImage: "bookmark.slash")
  }

  nonisolated static func normalizedSavedViewName(_ rawName: String) -> String {
    let collapsed = rawName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return String(collapsed.prefix(SavedClipView.maximumNameLength))
  }

  @discardableResult
  func copyStack(format: ClipStackFormat) -> Bool {
    let includedItems = stackItems.filter(canAddToStack)
    let text = ClipStackComposer.compose(includedItems, format: format)
    guard !text.isEmpty else {
      showNotice(
        L10n.text("notice.stack_copy_no_text", fallback: "Stack has no text to copy"),
        systemImage: "text.badge.xmark")
      return false
    }

    cancelSecureClipboardClear()
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      showNotice(
        L10n.text("notice.stack_copy_failed", fallback: "Stack could not be copied; try again"),
        systemImage: "exclamationmark.triangle.fill")
      return false
    }
    annotatePasteboardWrite()
    lastChangeCount = pasteboard.changeCount
    let includedIDs = Set(includedItems.map(\.id))
    for index in items.indices where includedIDs.contains(items[index].id) {
      items[index].useCount += 1
      items[index].lastUsedAt = .now
    }
    persist()

    let containsConcealedContent = stackRequiresSecureCopy
    if containsConcealedContent { scheduleSecureClipboardClear(after: 60) }
    showNotice(
      containsConcealedContent
        ? L10n.text("notice.stack_copied_securely", fallback: "Stack copied securely")
        : L10n.text("notice.stack_copied", fallback: "Stack copied"),
      systemImage: containsConcealedContent ? "timer" : "checkmark.circle.fill"
    )
    return true
  }

  nonisolated static func shouldClearSecureClipboard(
    expectedChangeCount: Int,
    currentChangeCount: Int
  ) -> Bool {
    expectedChangeCount == currentChangeCount
  }

  static func performSecureClipboardClear(
    after seconds: TimeInterval,
    expectedChangeCount: Int,
    currentChangeCount: @escaping @MainActor () -> Int,
    clear: @escaping @MainActor () -> Void
  ) async -> Bool {
    do {
      try await Task.sleep(for: .seconds(max(0.01, seconds)))
    } catch {
      return false
    }
    guard
      shouldClearSecureClipboard(
        expectedChangeCount: expectedChangeCount,
        currentChangeCount: currentChangeCount()
      )
    else { return false }
    clear()
    return true
  }

  func recordUse(for item: ClipItem) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    items[index].useCount += 1
    items[index].lastUsedAt = .now
    persist()
  }

  func togglePin(_ item: ClipItem) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    items[index].isPinned.toggle()
    sortItems()
    normalizeSelection()
    persist()
  }

  func rename(_ item: ClipItem, title: String) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maximumCustomTitleLength))
    guard items[index].customTitle != normalized else { return }
    items[index].customTitle = normalized
    persist()
    showNotice(
      normalized == nil
        ? L10n.text("notice.clip_title_removed", fallback: "Custom title removed")
        : L10n.text("notice.clip_title_updated", fallback: "Clip title updated"),
      systemImage: normalized == nil ? "text.badge.minus" : "checkmark.circle.fill"
    )
  }

  func updateTags(_ item: ClipItem, tags: [String]) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    let normalized = Self.normalizedTags(tags)
    guard items[index].tags != normalized else { return }
    items[index].tags = normalized
    persist()
    showNotice(
      normalized.isEmpty
        ? L10n.text("notice.clip_tags_removed", fallback: "Tags removed")
        : L10n.text("notice.clip_tags_updated", fallback: "Clip tags updated"),
      systemImage: normalized.isEmpty ? "tag.slash" : "tag.fill"
    )
  }

  @discardableResult
  func createBoard(named rawName: String) -> ClipBoard? {
    let name = Self.normalizedBoardName(rawName)
    guard !name.isEmpty else { return nil }
    if let existing = boards.first(where: {
      $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
    }) {
      selectedBoardID = existing.id
      showNotice(
        L10n.text("notice.board_exists", fallback: "Pinboard already exists"),
        systemImage: "rectangle.stack.fill")
      return existing
    }
    guard boards.count < ClipBoard.maximumCount else {
      showNotice(
        L10n.format(
          "notice.board_limit", fallback: "Keep up to %d Pinboards", ClipBoard.maximumCount),
        systemImage: "rectangle.stack.badge.minus"
      )
      return nil
    }
    let board = ClipBoard(name: name)
    boards.append(board)
    persistBoards()
    selectedBoardID = board.id
    showNotice(
      L10n.text("notice.board_created", fallback: "Pinboard created"),
      systemImage: "rectangle.stack.badge.plus")
    return board
  }

  @discardableResult
  func renameBoard(_ board: ClipBoard, to rawName: String) -> Bool {
    guard let index = boards.firstIndex(where: { $0.id == board.id }) else { return false }
    let name = Self.normalizedBoardName(rawName)
    guard !name.isEmpty else { return false }
    guard
      !boards.contains(where: {
        $0.id != board.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
      })
    else {
      showNotice(
        L10n.text("notice.board_name_exists", fallback: "A Pinboard already uses that name"),
        systemImage: "exclamationmark.circle")
      return false
    }
    guard boards[index].name != name else { return true }
    boards[index] = ClipBoard(id: board.id, name: name)
    persistBoards()
    showNotice(
      L10n.text("notice.board_renamed", fallback: "Pinboard renamed"),
      systemImage: "checkmark.circle.fill")
    return true
  }

  func deleteBoard(_ board: ClipBoard) {
    guard boards.contains(where: { $0.id == board.id }) else { return }
    boards.removeAll { $0.id == board.id }
    for index in items.indices {
      items[index].boardIDs.removeAll { $0 == board.id }
    }
    if selectedBoardID == board.id { selectedBoardID = nil }
    preferences.removeAppContextBoard(board.id)
    savedViews = savedViews.map { view in
      guard view.boardID == board.id else { return view }
      return SavedClipView(
        id: view.id,
        name: view.name,
        query: view.query,
        filter: view.filter,
        tag: view.tag,
        interpretsNaturalLanguage: view.interpretsNaturalLanguage
      )
    }
    persist()
    persistBoards()
    persistSavedViews()
    showNotice(
      L10n.text("notice.board_removed", fallback: "Pinboard removed; clips kept"),
      systemImage: "rectangle.stack.badge.minus")
  }

  func toggleBoardMembership(_ board: ClipBoard, for item: ClipItem) {
    guard boards.contains(where: { $0.id == board.id }),
      let index = items.firstIndex(where: { $0.id == item.id })
    else { return }
    if items[index].boardIDs.contains(board.id) {
      items[index].boardIDs.removeAll { $0 == board.id }
      showNotice(
        L10n.format("notice.board_item_removed", fallback: "Removed from %@", board.name),
        systemImage: "rectangle.stack.badge.minus")
    } else {
      items[index].boardIDs.append(board.id)
      showNotice(
        L10n.format("notice.board_item_added", fallback: "Added to %@", board.name),
        systemImage: "rectangle.stack.badge.plus")
    }
    normalizeSelection()
    persist()
  }

  @discardableResult
  func addItemsToBoard(_ candidates: [ClipItem], board: ClipBoard) -> Int {
    guard boards.contains(where: { $0.id == board.id }) else { return 0 }
    let candidateIDs = Set(candidates.map(\.id))
    guard !candidateIDs.isEmpty else { return 0 }
    var updatedItems = items
    var addedItemIDs: [UUID] = []
    for index in updatedItems.indices
    where candidateIDs.contains(updatedItems[index].id)
      && !updatedItems[index].boardIDs.contains(board.id)
    {
      updatedItems[index].boardIDs.append(board.id)
      addedItemIDs.append(updatedItems[index].id)
    }
    guard !addedItemIDs.isEmpty else {
      showNotice(
        L10n.format(
          "notice.board_batch_unchanged", fallback: "These results are already in %@", board.name),
        systemImage: "checkmark.circle")
      return 0
    }
    items = updatedItems
    selectedBoardID = board.id
    normalizeSelection()
    persist()
    showNotice(
      L10n.format(
        "notice.board_batch_added", fallback: "Saved %d results to %@", addedItemIDs.count,
        board.name),
      systemImage: "rectangle.stack.badge.plus",
      action: .undoBoardCollection(boardID: board.id, addedItemIDs: addedItemIDs))
    return addedItemIDs.count
  }

  func boards(for item: ClipItem) -> [ClipBoard] {
    let membership = Set(item.boardIDs)
    return boards.filter { membership.contains($0.id) }
  }

  func itemCount(in board: ClipBoard) -> Int {
    items.count { $0.boardIDs.contains(board.id) }
  }

  nonisolated static func normalizedBoardName(_ rawName: String) -> String {
    let collapsed = rawName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return String(collapsed.prefix(ClipBoard.maximumNameLength))
  }

  func privacyRuleValidationError(
    pattern rawPattern: String,
    mode: ClipboardPrivacyRuleMode,
    excludingID: UUID? = nil
  ) -> ClipboardPrivacyRuleValidationError? {
    let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pattern.isEmpty else { return .empty }
    guard pattern.count <= ClipboardPrivacyRule.maximumPatternLength else { return .tooLong }
    if excludingID == nil, privacyRules.count >= ClipboardPrivacyRule.maximumCount {
      return .limitReached
    }
    let duplicateKey = SearchMatcher.normalize(pattern)
    if privacyRules.contains(where: {
      $0.id != excludingID && $0.mode == mode
        && SearchMatcher.normalize($0.pattern) == duplicateKey
    }) {
      return .duplicate
    }
    if mode == .regularExpression {
      do {
        _ = try SafeRegexSearch(pattern)
      } catch let error as RegexSearchValidationError {
        return .invalidRegex(error)
      } catch {
        return .invalidRegex(.invalid)
      }
    }
    return nil
  }

  @discardableResult
  func savePrivacyRule(
    id: UUID? = nil,
    pattern rawPattern: String,
    mode: ClipboardPrivacyRuleMode
  ) -> Bool {
    guard !persistenceBlockedByUnreadableHistory else { return false }
    guard privacyRuleValidationError(pattern: rawPattern, mode: mode, excludingID: id) == nil
    else { return false }
    let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
    if let id, let index = privacyRules.firstIndex(where: { $0.id == id }) {
      privacyRules[index].pattern = pattern
      privacyRules[index].mode = mode
      privacyRegexCache.removeValue(forKey: id)
    } else {
      privacyRules.insert(ClipboardPrivacyRule(pattern: pattern, mode: mode), at: 0)
    }
    persistPrivacyRules()
    return true
  }

  func setPrivacyRuleEnabled(_ enabled: Bool, id: UUID) {
    guard !persistenceBlockedByUnreadableHistory else { return }
    guard let index = privacyRules.firstIndex(where: { $0.id == id }) else { return }
    guard privacyRules[index].isEnabled != enabled else { return }
    privacyRules[index].isEnabled = enabled
    persistPrivacyRules()
  }

  func deletePrivacyRule(id: UUID) {
    guard !persistenceBlockedByUnreadableHistory else { return }
    guard privacyRules.contains(where: { $0.id == id }) else { return }
    privacyRules.removeAll { $0.id == id }
    privacyRegexCache.removeValue(forKey: id)
    persistPrivacyRules()
  }

  func matchingPrivacyRule(for text: String) -> ClipboardPrivacyRule? {
    var normalizedText: String?
    for rule in privacyRules where rule.isEnabled {
      switch rule.mode {
      case .contains:
        if normalizedText == nil { normalizedText = SearchMatcher.normalize(text) }
        if normalizedText?.contains(SearchMatcher.normalize(rule.pattern)) == true { return rule }
      case .regularExpression:
        let regex: SafeRegexSearch?
        if let cached = privacyRegexCache[rule.id] {
          regex = cached
        } else if let compiled = try? SafeRegexSearch(rule.pattern) {
          privacyRegexCache[rule.id] = compiled
          regex = compiled
        } else {
          regex = nil
        }
        if regex?.matches(
          text,
          maximumCharacters: ClipboardPrivacyRule.maximumInspectedCharacters
        ) == true {
          return rule
        }
      }
    }
    return nil
  }

  private func recordPrivacyRuleMatch(id: UUID, at date: Date = .now) {
    guard let index = privacyRules.firstIndex(where: { $0.id == id }) else { return }
    if privacyRules[index].matchCount < Int.max { privacyRules[index].matchCount += 1 }
    privacyRules[index].lastMatchedAt = date
    persistPrivacyRules()
  }

  func toggleConcealment(_ item: ClipItem) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    items[index].isConcealed.toggle()
    persist()
    showNotice(
      items[index].isConcealed
        ? L10n.text("notice.clip_concealed", fallback: "Clip preview concealed")
        : L10n.text("notice.clip_visible", fallback: "Clip preview visible normally"),
      systemImage: items[index].isConcealed ? "eye.slash.fill" : "eye.fill"
    )
  }

  func setExpiration(_ item: ClipItem, at expiration: Date?) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    guard items[index].expiresAt != expiration else { return }
    items[index].expiresAt = expiration
    persist()
    if let expiration {
      if expiration <= .now {
        purgeExpired()
        return
      }
      showNotice(
        L10n.format(
          "notice.clip_expires", fallback: "Clip expires %@",
          expiration.formatted(date: .abbreviated, time: .shortened)),
        systemImage: "timer"
      )
    } else {
      showNotice(
        L10n.text("notice.clip_permanent", fallback: "Clip now stays until normal retention"),
        systemImage: "infinity")
    }
  }

  @discardableResult
  func purgeExpired(now: Date = .now) -> Int {
    let expired = items.filter { item in
      item.expiresAt.map { $0 <= now } ?? false
    }
    guard !expired.isEmpty else { return 0 }

    for item in expired { removeStoredFile(for: item) }
    let expiredIDs = Set(expired.map(\.id))
    items.removeAll { expiredIDs.contains($0.id) }
    stackIDs.removeAll { expiredIDs.contains($0) }
    for id in expiredIDs { contentKindCache.removeValue(forKey: id) }
    for id in expiredIDs { searchIndexCache.removeValue(forKey: id) }
    normalizeSelection()
    persist()
    persistStack()
    showNotice(
      L10n.format(
        "notice.expired_clips", fallback: "Expired %d temporary clips", expired.count),
      systemImage: "timer")
    return expired.count
  }

  static func normalizedTags(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for rawTag in tags {
      var tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
      while tag.hasPrefix("#") {
        tag.removeFirst()
      }
      tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !tag.isEmpty else { continue }
      tag = String(tag.prefix(maximumTagLength))
      let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      guard seen.insert(key).inserted else { continue }
      result.append(tag)
      if result.count == maximumTagCount { break }
    }
    return result
  }

  func delete(_ item: ClipItem) {
    guard let storedItem = items.first(where: { $0.id == item.id }) else { return }
    let deleted = DeletedClip(
      item: storedItem,
      imageData: imageData(for: storedItem),
      richTextData: richTextData(for: storedItem),
      stackIndex: stackIDs.firstIndex(of: storedItem.id)
    )
    removeStoredFile(for: storedItem)
    items.removeAll { $0.id == storedItem.id }
    contentKindCache.removeValue(forKey: storedItem.id)
    searchIndexCache.removeValue(forKey: storedItem.id)
    stackIDs.removeAll { $0 == storedItem.id }
    normalizeSelection()
    persist()
    persistStack()
    offerUndo(
      for: [deleted],
      message: L10n.text("notice.clip_deleted", fallback: "Deleted clip — undo available"))
  }

  func clearUnpinned() {
    let removed = items.filter { !$0.isPinned }
    guard !removed.isEmpty else {
      showNotice(
        L10n.text(
          "notice.no_unpinned", fallback: "There is no unpinned history to clear"),
        systemImage: "checkmark.circle")
      return
    }
    let deleted = removed.map { item in
      DeletedClip(
        item: item,
        imageData: imageData(for: item),
        richTextData: richTextData(for: item),
        stackIndex: stackIDs.firstIndex(of: item.id)
      )
    }
    removed.forEach(removeStoredFile)
    items.removeAll { !$0.isPinned }
    let removedIDs = Set(removed.map(\.id))
    for id in removedIDs { contentKindCache.removeValue(forKey: id) }
    for id in removedIDs { searchIndexCache.removeValue(forKey: id) }
    stackIDs.removeAll { removedIDs.contains($0) }
    normalizeSelection()
    persist()
    persistStack()
    offerUndo(
      for: deleted,
      message: L10n.format(
        "notice.cleared_clips", fallback: "Cleared %d clips — undo available", removed.count))
  }

  func undoLastDeletion(now restorationDate: Date = .now) {
    guard canUndoDeletion, !deletedClips.isEmpty else { return }
    let pending = deletedClips
    deletedClips = []
    canUndoDeletion = false

    var restored = 0
    var restoredIDs = Set<UUID>()
    for deleted in pending {
      guard deleted.item.expiresAt.map({ $0 > restorationDate }) ?? true,
        !items.contains(where: { $0.fingerprint == deleted.item.fingerprint })
      else { continue }
      var restoredItem = deleted.item
      if let fileName = restoredItem.imageFileName {
        guard let data = deleted.imageData else { continue }
        let destination = imagesURL.appendingPathComponent(fileName)
        do {
          try writeProtectedData(data, to: destination)
          cacheImageData(data, fileName: fileName)
        } catch {
          try? fileManager.removeItem(at: destination)
          setPersistenceIssue(error)
          continue
        }
      }
      if restoredItem.richTextFileName != nil {
        if let data = deleted.richTextData {
          do {
            restoredItem.richTextFileName = try writeRichTextData(data, for: restoredItem.id)
          } catch {
            restoredItem.richTextFileName = nil
            setPersistenceIssue(error)
          }
        } else {
          restoredItem.richTextFileName = nil
        }
      }
      restoredItem.richTextData = nil
      items.append(restoredItem)
      restoredIDs.insert(restoredItem.id)
      restored += 1
    }

    for deleted in pending
    where restoredIDs.contains(deleted.item.id) && deleted.stackIndex != nil {
      let index = min(deleted.stackIndex ?? stackIDs.count, stackIDs.count)
      stackIDs.insert(deleted.item.id, at: index)
    }

    sortItems()
    trimIfNeeded()
    selectedID = pending.first.flatMap { deleted in
      filteredItems.first(where: { $0.id == deleted.item.id })?.id
    }
    normalizeSelection()
    persist()
    persistStack()
    showNotice(
      L10n.format("notice.restored_clips", fallback: "Restored %d clips", restored),
      systemImage: "arrow.uturn.backward.circle.fill")
  }

  func performNoticeAction(_ action: StoreNoticeAction) {
    switch action {
    case .undoDeletion:
      undoLastDeletion()
    case .undoStackAdvance:
      undoLastStackAdvance()
    case .undoStackCollection(let previousIDs):
      let liveIDs = Set(items.map(\.id))
      stackIDs = previousIDs.filter(liveIDs.contains)
      persistStack()
      showNotice(
        L10n.text(
          "notice.stack_collection_undone", fallback: "Restored the previous Stack"),
        systemImage: "arrow.uturn.backward.circle.fill")
    case .undoBoardCollection(let boardID, let addedItemIDs):
      guard let board = boards.first(where: { $0.id == boardID }) else { return }
      let addedIDs = Set(addedItemIDs)
      var updatedItems = items
      var removed = 0
      for index in updatedItems.indices where addedIDs.contains(updatedItems[index].id) {
        let previousCount = updatedItems[index].boardIDs.count
        updatedItems[index].boardIDs.removeAll { $0 == boardID }
        if updatedItems[index].boardIDs.count != previousCount { removed += 1 }
      }
      guard removed > 0 else { return }
      items = updatedItems
      normalizeSelection()
      persist()
      showNotice(
        L10n.format(
          "notice.board_batch_undone", fallback: "Removed %d added results from %@", removed,
          board.name),
        systemImage: "arrow.uturn.backward.circle.fill")
    }
  }

  func normalizeSelection() {
    let visibleItems = filteredItems
    if let selectedID, visibleItems.contains(where: { $0.id == selectedID }) { return }
    selectedID = visibleItems.first?.id
  }

  func selectAdjacentVisibleItem(by offset: Int) {
    let visibleItems = filteredItems
    guard !visibleItems.isEmpty else {
      selectedID = nil
      return
    }
    guard offset != 0 else {
      normalizeSelection()
      return
    }
    guard let selectedID,
      let currentIndex = visibleItems.firstIndex(where: { $0.id == selectedID })
    else {
      self.selectedID = visibleItems.first?.id
      return
    }
    let nextIndex = min(max(currentIndex + offset, 0), visibleItems.count - 1)
    self.selectedID = visibleItems[nextIndex].id
  }

  func retryStorage() {
    if requiresStorageProtection && storageProtector == nil {
      beginStorageUnlock(startMonitoringWhenReady: isMonitoring)
      return
    }
    if persistenceBlockedByUnreadableHistory {
      load()
      resumePendingImageAnalysis()
    }
    persist()
    persistStack()
    persistSavedViews()
    persistBoards()
    persistPrivacyRules()
    if storageIssue == nil || storageIssue?.kind == .recoveredHistory {
      showNotice(
        L10n.text("notice.storage_ready", fallback: "Local storage is ready"),
        systemImage: "checkmark.circle.fill")
    }
  }

  private func beginStorageUnlock(startMonitoringWhenReady: Bool) {
    guard storageProtector == nil, storageUnlockTask == nil else { return }
    isUnlockingStorage = true
    isStorageUnlockTakingLong = false
    storageUnlockWatchdogTask?.cancel()
    persistenceBlockedByUnreadableHistory = true
    storageIssue = StorageIssue(
      kind: .persistence,
      message: L10n.text("storage.unlocking", fallback: "Unlocking local history…"),
      detail: L10n.text(
        "storage.unlocking_detail",
        fallback: "Clipskein is waiting for macOS Keychain. History stays locked and unchanged."
      ),
      recoveryFileName: nil
    )
    let longWaitDuration = storageUnlockLongWaitDuration
    storageUnlockWatchdogTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: longWaitDuration)
      guard !Task.isCancelled, let self, self.isUnlockingStorage else { return }
      self.isStorageUnlockTakingLong = true
      self.storageIssue = StorageIssue(
        kind: .persistence,
        message: L10n.text("storage.keychain_waiting", fallback: "Waiting for macOS Keychain"),
        detail: L10n.text(
          "storage.keychain_waiting_detail",
          fallback:
            "Unlock your login keychain or approve any Clipskein access prompt. Encrypted history remains unchanged."
        ),
        recoveryFileName: nil
      )
    }
    let loader = storageProtectorLoader
    storageUnlockTask = Task { @MainActor [weak self] in
      let result = await Task.detached(priority: .userInitiated) {
        do {
          return Result<SecureLocalStorage, PersistenceWriteError>.success(try loader())
        } catch {
          return .failure(PersistenceWriteError(message: error.localizedDescription))
        }
      }.value
      guard let self else { return }
      self.storageUnlockTask = nil
      self.storageUnlockWatchdogTask?.cancel()
      self.storageUnlockWatchdogTask = nil
      self.isUnlockingStorage = false
      self.isStorageUnlockTakingLong = false
      switch result {
      case .success(let protector):
        self.storageProtector = protector
        self.persistenceBlockedByUnreadableHistory = false
        self.storageIssue = nil
        self.load()
        self.loadStack()
        self.loadSavedViews()
        self.loadBoards()
        self.loadPrivacyRules()
        self.loadNewSnippetDraft()
        self.migrateStoredPayloadsIfNeeded()
        self.pruneBoardReferences()
        self.purgeExpired()
        self.resumePendingImageAnalysis()
        self.configureScreenshotWatching()
        if startMonitoringWhenReady { self.startMonitoring() }
      case .failure(let error):
        self.persistenceBlockedByUnreadableHistory = true
        self.setPersistenceIssue(error)
      }
    }
  }

  func openKeychainAccess() {
    let workspace = NSWorkspace.shared
    let fallbackURL = URL(
      fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app",
      isDirectory: true
    )
    guard
      let applicationURL = workspace.urlForApplication(
        withBundleIdentifier: "com.apple.keychainaccess"
      ) ?? (fileManager.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil),
      workspace.open(applicationURL)
    else {
      showNotice(
        L10n.text(
          "notice.keychain_access_unavailable",
          fallback: "Open Keychain Access from Applications > Utilities"
        ),
        systemImage: "key.fill"
      )
      return
    }
  }

  func revealStorage() {
    let target =
      fileManager.fileExists(atPath: rootURL.path) ? rootURL : rootURL.deletingLastPathComponent()
    NSWorkspace.shared.activateFileViewerSelecting([target])
  }

  func refreshStorageInventory() {
    storageInventoryTask?.cancel()
    isInspectingStorage = true
    let rootURL = rootURL
    let imageNames = Set(items.compactMap(\.imageFileName)).union(archiveRetainedImageNames)
    let richTextNames = Set(items.compactMap(\.richTextFileName)).union(archiveRetainedRichTextNames)
    storageInventoryTask = Task { [weak self] in
      let inventory = await Task.detached(priority: .utility) {
        StorageInventoryScanner.scan(
          rootURL: rootURL,
          referencedImageFileNames: imageNames,
          referencedRichTextFileNames: richTextNames
        )
      }.value
      guard !Task.isCancelled, let self else { return }
      storageInventory = inventory
      isInspectingStorage = false
    }
  }

  func cleanUnusedStorage() {
    guard !persistenceBlockedByUnreadableHistory, !isCleaningStorage else { return }
    storageInventoryTask?.cancel()
    isInspectingStorage = false
    isCleaningStorage = true
    let rootURL = rootURL
    let imageNames = Set(items.compactMap(\.imageFileName)).union(archiveRetainedImageNames)
    let richTextNames = Set(items.compactMap(\.richTextFileName)).union(archiveRetainedRichTextNames)
    storageInventoryTask = Task { [weak self] in
      let result = await Task.detached(priority: .utility) {
        StorageInventoryScanner.removeUnusedFiles(
          rootURL: rootURL,
          referencedImageFileNames: imageNames,
          referencedRichTextFileNames: richTextNames
        )
      }.value
      guard !Task.isCancelled, let self else { return }
      isCleaningStorage = false
      if result.failedFileCount > 0 {
        showNotice(
          L10n.format(
            "notice.storage_cleanup_partial",
            fallback: "Reclaimed %@, but %d files could not be removed",
            Self.formattedByteCount(result.removedBytes),
            result.failedFileCount
          ),
          systemImage: "exclamationmark.triangle.fill"
        )
      } else if result.removedFileCount > 0 {
        showNotice(
          L10n.format(
            "notice.storage_cleanup_complete",
            fallback: "Reclaimed %@ from unused local files",
            Self.formattedByteCount(result.removedBytes)
          ),
          systemImage: "checkmark.circle.fill"
        )
      } else {
        showNotice(
          L10n.text("notice.storage_already_clean", fallback: "Local storage is already clean"),
          systemImage: "checkmark.circle"
        )
      }
      refreshStorageInventory()
    }
  }

  nonisolated static func formattedByteCount(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  func dismissRecoveredHistoryNotice() {
    guard storageIssue?.kind == .recoveredHistory else { return }
    storageIssue = nil
  }

  func exportImage(_ item: ClipItem, to destinationURL: URL) async -> ImageExportResult {
    let destination = destinationURL.standardizedFileURL
    let protectedRoot = rootURL.standardizedFileURL.path
    guard isSessionActive, !isExportingImage, item.kind == .image,
      let fileName = item.imageFileName, destination.isFileURL,
      destination.path != protectedRoot,
      !destination.path.hasPrefix(protectedRoot + "/")
    else {
      return .failed(
        L10n.text(
          "notice.image_export_unavailable",
          fallback: "This screenshot cannot be exported to that location."
        )
      )
    }

    let source = imagesURL.appendingPathComponent(fileName)
    let protector = storageProtector
    let requiresProtection = requiresStorageProtection
    let loader = storedImageDataLoader
    let cancellation = ImageExportCancellationFlag()
    let generation = UUID()
    let task = Task.detached(priority: .userInitiated) {
      Self.performImageExport(
        source: source,
        destination: destination,
        protector: protector,
        requiresProtection: requiresProtection,
        loader: loader,
        cancellation: cancellation
      )
    }
    imageExportCancellation = cancellation
    imageExportGeneration = generation
    imageExportTask = task
    isExportingImage = true
    let work = await task.value
    guard imageExportGeneration == generation else { return .cancelled }
    imageExportTask = nil
    imageExportCancellation = nil
    imageExportGeneration = nil
    isExportingImage = false

    if work.secureStorageFailure {
      persistenceBlockedByUnreadableHistory = true
      if case .failed(let message) = work.result {
        setPersistenceIssue(PersistenceWriteError(message: message))
      }
    }
    guard isSessionActive else { return .cancelled }
    switch work.result {
    case .exported:
      recordUse(for: item)
      showNotice(
        L10n.format(
          "notice.image_exported",
          fallback: "Exported %@",
          destination.lastPathComponent
        ),
        systemImage: "square.and.arrow.down.fill"
      )
    case .cancelled:
      break
    case .failed(let message):
      showNotice(message, systemImage: "exclamationmark.triangle.fill")
    }
    return work.result
  }

  func cancelImageExport() {
    imageExportCancellation?.cancel()
    imageExportTask?.cancel()
    imageExportTask = nil
    imageExportCancellation = nil
    imageExportGeneration = nil
    isExportingImage = false
  }

  nonisolated private static func performImageExport(
    source: URL,
    destination: URL,
    protector: SecureLocalStorage?,
    requiresProtection: Bool,
    loader: @escaping @Sendable (
      URL, SecureLocalStorage?, Bool
    ) -> StoredImageDataLoadResult,
    cancellation: ImageExportCancellationFlag
  ) -> ImageExportWorkResult {
    guard !cancellation.isCancelled, !Task.isCancelled else {
      return ImageExportWorkResult(result: .cancelled, secureStorageFailure: false)
    }
    let data: Data
    switch loader(source, protector, requiresProtection) {
    case .success(let loaded):
      data = loaded
    case .failure(let error, let secureStorageFailure):
      return ImageExportWorkResult(
        result: .failed(
          L10n.format(
            "notice.image_export_read_failed",
            fallback: "Could not read the stored screenshot. %@",
            error.localizedDescription
          )
        ),
        secureStorageFailure: secureStorageFailure
      )
    }
    guard !cancellation.isCancelled, !Task.isCancelled else {
      return ImageExportWorkResult(result: .cancelled, secureStorageFailure: false)
    }

    let fileManager = FileManager.default
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".Clipskein-export-\(UUID().uuidString).tmp"
    )
    defer { try? fileManager.removeItem(at: temporary) }
    do {
      try data.write(to: temporary)
      try fileManager.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: temporary.path
      )
      guard !cancellation.isCancelled, !Task.isCancelled else {
        return ImageExportWorkResult(result: .cancelled, secureStorageFailure: false)
      }
      if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
      } else {
        try fileManager.moveItem(at: temporary, to: destination)
      }
      return ImageExportWorkResult(result: .exported, secureStorageFailure: false)
    } catch {
      return ImageExportWorkResult(
        result: .failed(
          L10n.format(
            "notice.image_export_write_failed",
            fallback: "Could not save the screenshot. %@",
            error.localizedDescription
          )
        ),
        secureStorageFailure: false
      )
    }
  }

  func imageData(for item: ClipItem) -> Data? {
    guard let fileName = item.imageFileName else { return nil }
    let cacheKey = fileName as NSString
    if let cached = imageDataCache.object(forKey: cacheKey) {
      return cached as Data
    }
    switch storedImageDataLoader(
      imagesURL.appendingPathComponent(fileName),
      storageProtector,
      requiresStorageProtection
    ) {
    case .success(let data):
      cacheImageData(data, fileName: fileName)
      return data
    case .failure(let error, let secureStorageFailure):
      if secureStorageFailure { persistenceBlockedByUnreadableHistory = true }
      setPersistenceIssue(error)
      return nil
    }
  }

  func cachedDecodedImage(for item: ClipItem) -> NSImage? {
    guard let fileName = item.imageFileName else { return nil }
    return decodedImageCache.object(forKey: fileName as NSString)
  }

  func sourceApplicationIcon(for item: ClipItem) -> NSImage? {
    sourceApplicationIcon(bundleIdentifier: item.sourceBundleIdentifier)
  }

  func sourceApplicationIcon(bundleIdentifier: String?) -> NSImage? {
    guard let bundleIdentifier else { return nil }
    let key = bundleIdentifier as NSString
    if let cached = sourceApplicationIconCache.object(forKey: key) { return cached }
    guard !missingSourceApplicationIcons.contains(bundleIdentifier) else { return nil }
    guard
      let applicationURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleIdentifier
      )
    else {
      missingSourceApplicationIcons.insert(bundleIdentifier)
      return nil
    }
    let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
    guard icon.isValid else {
      missingSourceApplicationIcons.insert(bundleIdentifier)
      return nil
    }
    sourceApplicationIconCache.setObject(icon, forKey: key)
    return icon
  }

  func cachedImageData(for item: ClipItem) -> Data? {
    guard let fileName = item.imageFileName,
      let cached = imageDataCache.object(forKey: fileName as NSString)
    else { return nil }
    return cached as Data
  }

  func cachedImageStatus(for item: ClipItem) -> CachedImageStatus {
    guard let fileName = item.imageFileName else { return .unavailable }
    if decodedImageCache.object(forKey: fileName as NSString) != nil,
      imageDataCache.object(forKey: fileName as NSString) != nil
    {
      return .available
    }
    if imageLoadTasks[fileName] != nil { return .loading }
    if failedImageLoads.contains(fileName) { return .failed }
    return .unavailable
  }

  func requestDecodedImage(for item: ClipItem) {
    guard isSessionActive, item.kind == .image, let fileName = item.imageFileName,
      cachedDecodedImage(for: item) == nil, imageLoadTasks[fileName] == nil,
      !failedImageLoads.contains(fileName)
    else { return }

    let url = imagesURL.appendingPathComponent(fileName)
    let protector = storageProtector
    let requiresProtection = requiresStorageProtection
    let loader = storedImageDataLoader
    let cachedData = cachedImageData(for: item)
    imageLoadTasks[fileName] = Task { @MainActor [weak self] in
      let prepared = await Task.detached(priority: .userInitiated) {
        let result = cachedData.map(StoredImageDataLoadResult.success)
          ?? loader(url, protector, requiresProtection)
        let metadata: StoredImageMetadata?
        switch result {
        case .success(let data):
          metadata = ImageMetadata.storedMetadata(for: data)
        case .failure:
          metadata = nil
        }
        return PreparedStoredImageLoad(result: result, metadata: metadata)
      }.value
      guard let self else { return }
      self.imageLoadTasks[fileName] = nil
      guard !Task.isCancelled, self.isSessionActive else { return }
      switch prepared.result {
      case .success(let data):
        guard let image = NSImage(data: data) else {
          self.failedImageLoads.insert(fileName)
          self.imageCacheRevision &+= 1
          return
        }
        self.failedImageLoads.remove(fileName)
        self.cacheImageData(data, fileName: fileName)
        self.decodedImageCache.setObject(
          image,
          forKey: fileName as NSString,
          cost: self.decodedImageCost(image)
        )
        if let metadata = prepared.metadata,
          let index = self.items.firstIndex(where: { $0.id == item.id }),
          self.items[index].imageMetadata?.frameCount == nil
        {
          self.items[index].imageMetadata = metadata
          if self.preferences.protectSecrets, (metadata.frameCount ?? 1) > 1 {
            self.items[index].isConcealed = true
          }
          self.invalidateDerivedCaches(for: item.id)
          self.persist()
        }
        self.imageCacheRevision &+= 1
      case .failure(let error, let secureStorageFailure):
        self.failedImageLoads.insert(fileName)
        if secureStorageFailure { self.persistenceBlockedByUnreadableHistory = true }
        self.setPersistenceIssue(error)
        self.imageCacheRevision &+= 1
      }
    }
  }

  func decodedImage(for item: ClipItem) -> NSImage? {
    guard let fileName = item.imageFileName else { return nil }
    let cacheKey = fileName as NSString
    if let cached = decodedImageCache.object(forKey: cacheKey) { return cached }
    guard let data = imageData(for: item), let image = NSImage(data: data) else { return nil }
    decodedImageCache.setObject(image, forKey: cacheKey, cost: decodedImageCost(image))
    return image
  }

  @discardableResult
  func relinkFileReference(
    in item: ClipItem,
    missingPath: String,
    to replacementURL: URL
  ) -> FileReferenceRelinkResult {
    guard let index = items.firstIndex(where: { $0.id == item.id }),
      items[index].kind == .files,
      let pathIndex = items[index].filePaths.firstIndex(of: missingPath)
    else { return reportRelinkResult(.itemUnavailable) }
    guard !fileManager.fileExists(atPath: missingPath) else {
      return reportRelinkResult(.originalAvailable)
    }
    guard replacementURL.isFileURL else {
      return reportRelinkResult(.replacementUnavailable)
    }
    let replacementPath = replacementURL.standardizedFileURL.path
    guard !replacementPath.isEmpty,
      fileManager.fileExists(atPath: replacementPath)
    else { return reportRelinkResult(.replacementUnavailable) }

    var paths = items[index].filePaths
    guard !paths.contains(replacementPath) else {
      return reportRelinkResult(.duplicatePath)
    }
    paths[pathIndex] = replacementPath
    guard normalizedFilePaths(paths) == paths else {
      return reportRelinkResult(.replacementUnavailable)
    }
    let fingerprint = fileFingerprint(paths)
    guard !items.contains(where: { $0.id != item.id && $0.fingerprint == fingerprint }) else {
      return reportRelinkResult(.duplicateGroup)
    }

    let stored = items[index]
    items[index] = ClipItem(
      id: stored.id,
      kind: .files,
      filePaths: paths,
      customTitle: stored.customTitle,
      alias: stored.alias,
      tags: stored.tags,
      boardIDs: stored.boardIDs,
      isConcealed: stored.isConcealed,
      sourceApplication: stored.sourceApplication,
      sourceBundleIdentifier: stored.sourceBundleIdentifier,
      createdAt: stored.createdAt,
      isPinned: stored.isPinned,
      useCount: stored.useCount,
      lastUsedAt: stored.lastUsedAt,
      expiresAt: stored.expiresAt,
      fingerprint: fingerprint
    )
    invalidateDerivedCaches(for: stored.id)
    persist()
    refreshFileReferenceAvailability(for: items[index], force: true)
    return reportRelinkResult(.relinked)
  }

  private func reportRelinkResult(_ result: FileReferenceRelinkResult)
    -> FileReferenceRelinkResult
  {
    showNotice(
      result.message,
      systemImage: result == .relinked ? "link.badge.plus" : "exclamationmark.triangle.fill"
    )
    return result
  }

  func dragAvailability(for item: ClipItem) -> ClipDragAvailability {
    guard let stored = items.first(where: { $0.id == item.id }) else { return .unavailable }
    guard !stored.isConcealed else { return .concealed }
    switch stored.kind {
    case .text:
      return stored.text.isEmpty ? .unavailable : .ready(itemCount: 1)
    case .image:
      if cachedDecodedImage(for: stored) != nil, cachedImageData(for: stored) != nil {
        return .ready(itemCount: 1)
      }
      switch cachedImageStatus(for: stored) {
      case .loading:
        return .preparingImage
      case .failed:
        return .imageUnavailable
      case .available:
        return .ready(itemCount: 1)
      case .unavailable:
        requestDecodedImage(for: stored)
        return .preparingImage
      }
    case .files:
      guard let availability = fileReferenceAvailability,
        availability.itemID == stored.id,
        availability.fingerprint == stored.fingerprint,
        let existingPaths = availability.existingPaths
      else {
        refreshFileReferenceAvailability(for: stored)
        return .checkingReference
      }
      guard !existingPaths.isEmpty, existingPaths.count == stored.filePaths.count else {
        return .missingReference
      }
      return .ready(itemCount: existingPaths.count)
    }
  }

  func dragPasteboardWriters(for item: ClipItem) -> [NSPasteboardWriting] {
    guard dragAvailability(for: item).isEnabled,
      let stored = items.first(where: { $0.id == item.id })
    else { return [] }

    switch stored.kind {
    case .text:
      guard
        let pasteboardItem = textPasteboardItem(
          stored.text,
          richTextData: richTextData(for: stored)
        )
      else { return [] }
      return [pasteboardItem]
    case .image:
      guard let image = decodedImage(for: stored) else { return [] }
      guard
        let pasteboardItem = imagePasteboardItem(
          image,
          originalData: cachedImageData(for: stored)
        )
      else { return [] }
      return [pasteboardItem]
    case .files:
      let urls = existingFileURLs(for: stored)
      guard urls.count == stored.filePaths.count else {
        refreshFileReferenceAvailability(for: stored, force: true)
        return []
      }
      return urls.map { $0 as NSURL }
    }
  }

  func dragPreviewImage(for item: ClipItem) -> NSImage {
    let source: NSImage
    switch item.kind {
    case .text:
      source =
        NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil) ?? NSImage()
    case .image:
      source = decodedImage(for: item) ?? NSImage()
    case .files:
      source = item.filePaths.first.map(NSWorkspace.shared.icon(forFile:)) ?? NSImage()
    }
    return dragThumbnail(source, maximumDimension: 64)
  }

  func exportURL() -> URL { rootURL }

  var canPerformArchiveOperations: Bool {
    isSessionActive && !isUnlockingStorage && !persistenceBlockedByUnreadableHistory
      && (!requiresStorageProtection || storageProtector != nil)
  }

  func requireArchiveStorageAccess() throws {
    guard canPerformArchiveOperations else {
      throw PersistenceWriteError(
        message: isUnlockingStorage
          ? L10n.text("storage.unlocking_detail", fallback: "Local history is still unlocking.")
          : (storageIssue?.detail
            ?? L10n.text("storage.history_blocked", fallback: "History cannot be opened safely"))
      )
    }
  }

  func makeEncryptedArchive(
    password: String,
    keyIterations: Int = ClipArchive.productionKeyIterations
  ) throws -> Data {
    try requireArchiveStorageAccess()
    purgeExpired()
    return try Self.makeEncryptedArchive(
      from: archiveExportSnapshot(),
      password: password,
      keyIterations: keyIterations
    )
  }

  func makeEncryptedArchiveInBackground(
    password: String,
    keyIterations: Int = ClipArchive.productionKeyIterations
  ) async throws -> Data {
    try requireArchiveStorageAccess()
    purgeExpired()
    let snapshot = archiveExportSnapshot()
    return try await Self.performCancellableBackgroundWork {
      try Self.makeEncryptedArchive(
        from: snapshot,
        password: password,
        keyIterations: keyIterations
      )
    }
  }

  private func archiveExportSnapshot() -> ArchiveExportSnapshot {
    ArchiveExportSnapshot(
      exportedAt: .now,
      items: items,
      imagesURL: imagesURL,
      richTextURL: richTextURL,
      stackFingerprints: stackItems.map(\.fingerprint),
      savedViews: savedViews,
      boards: boards,
      storageProtector: storageProtector,
      requiresStorageProtection: requiresStorageProtection
    )
  }

  private nonisolated static func makeEncryptedArchive(
    from snapshot: ArchiveExportSnapshot,
    password: String,
    keyIterations: Int
  ) throws -> Data {
    var images: [String: Data] = [:]
    var richText: [String: Data] = [:]
    var archivedItems = snapshot.items
    for item in snapshot.items where item.kind == .image {
      try Task.checkCancellation()
      guard let fileName = item.imageFileName,
        fileName == URL(fileURLWithPath: fileName).lastPathComponent
      else {
        throw ClipArchiveError.missingLocalImage(item.imageFileName ?? "unknown image")
      }
      let data: Data
      do {
        data = try readArchivedData(
          from: snapshot.imagesURL.appendingPathComponent(fileName),
          storageProtector: snapshot.storageProtector,
          requiresStorageProtection: snapshot.requiresStorageProtection
        )
      } catch let error as SecureLocalStorageError {
        throw error
      } catch {
        throw ClipArchiveError.missingLocalImage(fileName)
      }
      images[fileName] = data
    }
    for index in archivedItems.indices where archivedItems[index].hasRichText {
      try Task.checkCancellation()
      let fileName =
        archivedItems[index].richTextFileName ?? "\(archivedItems[index].id.uuidString).rtf"
      let data: Data?
      if let storedName = archivedItems[index].richTextFileName,
        storedName == URL(fileURLWithPath: storedName).lastPathComponent
      {
        do {
          let stored = try readArchivedData(
            from: snapshot.richTextURL.appendingPathComponent(storedName),
            storageProtector: snapshot.storageProtector,
            requiresStorageProtection: snapshot.requiresStorageProtection
          )
          data = RichTextPayload.validated(stored, matching: archivedItems[index].text)
        } catch let error as SecureLocalStorageError {
          throw error
        } catch {
          data = nil
        }
      } else {
        data = RichTextPayload.validated(
          archivedItems[index].richTextData,
          matching: archivedItems[index].text
        )
      }
      guard let data else {
        throw ClipArchiveError.missingLocalRichText(fileName)
      }
      richText[fileName] = data
      archivedItems[index].richTextFileName = fileName
      archivedItems[index].richTextData = nil
    }
    let payload = ClipArchivePayload(
      exportedAt: snapshot.exportedAt,
      items: archivedItems,
      images: images,
      richText: richText,
      stackFingerprints: snapshot.stackFingerprints,
      savedViews: snapshot.savedViews,
      boards: snapshot.boards
    )
    return try ClipArchive.seal(
      payload: payload,
      password: password,
      keyIterations: keyIterations
    )
  }

  private nonisolated static func readArchivedData(
    from url: URL,
    storageProtector: SecureLocalStorage?,
    requiresStorageProtection: Bool
  ) throws -> Data {
    let storedData = try Data(contentsOf: url, options: .mappedIfSafe)
    if let storageProtector {
      return try storageProtector.open(storedData).data
    }
    if requiresStorageProtection { throw SecureLocalStorageError.invalidKey }
    return storedData
  }

  private nonisolated static func performCancellableBackgroundWork<T: Sendable>(
    _ operation: @escaping @Sendable () throws -> T
  ) async throws -> T {
    let worker = Task.detached(priority: .userInitiated, operation: operation)
    return try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
  }

  func importEncryptedArchive(_ data: Data, password: String) throws -> ArchiveImportSummary {
    try requireArchiveStorageAccess()
    // The synchronous API cannot wait for another snapshot without blocking its
    // main-actor completion. The UI uses the asynchronous API below.
    guard !hasPendingHistoryPersistence else {
      throw PersistenceWriteError(message: L10n.text(
        "archive.progress.busy_detail", fallback: "Finish the current save before importing."
      ))
    }
    let payload = try ClipArchive.open(data: data, password: password)
    let summary = try importArchivePayload(payload)
    do {
      try persistArchiveHistorySynchronously()
      try persistArchiveCollections()
      resumePendingImageAnalysis()
      return summary
    } catch {
      setPersistenceIssue(error)
      throw error
    }
  }

  func importEncryptedArchiveInBackground(_ data: Data, password: String) async throws
    -> ArchiveImportSummary
  {
    try requireArchiveStorageAccess()
    let payload = try await Self.performCancellableBackgroundWork {
      try ClipArchive.open(data: data, password: password)
    }
    try Task.checkCancellation()
    await flushPendingHistoryPersistence()
    try Task.checkCancellation()
    try requireArchiveStorageAccess()
    let summary = try importArchivePayload(payload)
    persist()
    await flushPendingHistoryPersistence()
    do {
      try requireArchiveStorageAccess()
      if let message = historyPersistenceErrorMessage {
        throw PersistenceWriteError(message: message)
      }
      try persistArchiveCollections()
      resumePendingImageAnalysis()
      return summary
    } catch {
      // Keep the merged in-memory state so Retry Saving can recover it. Reverting
      // here could overwrite captures made while the background writer was busy.
      setPersistenceIssue(error)
      throw error
    }
  }

  private func importArchivePayload(_ payload: ClipArchivePayload) throws -> ArchiveImportSummary {
    try requireArchiveStorageAccess()
    archiveRetainedImageNames.formUnion(items.compactMap(\.imageFileName))
    archiveRetainedRichTextNames.formUnion(items.compactMap(\.richTextFileName))
    isApplyingArchiveImport = true
    defer { isApplyingArchiveImport = false }
    let importDate = Date()
    purgeExpired(now: importDate)
    var added = 0
    var merged = 0
    var skipped = 0
    let boardMerge = mergeArchivedBoards(payload.boards)

    for archived in payload.items {
      guard archived.expiresAt.map({ $0 > importDate }) ?? true else {
        skipped += 1
        continue
      }
      let archivedImage: Data?
      let archivedRichText: Data? =
        archived.richTextFileName.flatMap { payload.richText[$0] }
        ?? RichTextPayload.validated(archived.richTextData, matching: archived.text)
      switch archived.kind {
      case .text:
        guard digest(Data(archived.text.utf8)) == archived.fingerprint else {
          skipped += 1
          continue
        }
        archivedImage = nil
      case .image:
        guard let archivedName = archived.imageFileName,
          archivedName == URL(fileURLWithPath: archivedName).lastPathComponent,
          let image = payload.images[archivedName],
          digest(image) == archived.fingerprint,
          !Self.hasGIFSignature(image) || ImageMetadata.isValidGIF(image)
        else {
          skipped += 1
          continue
        }
        archivedImage = image
      case .files:
        guard !archived.filePaths.isEmpty,
          archived.filePaths == normalizedFilePaths(archived.filePaths),
          fileFingerprint(archived.filePaths) == archived.fingerprint
        else {
          skipped += 1
          continue
        }
        archivedImage = nil
      }

      if let existingIndex = items.firstIndex(where: { $0.fingerprint == archived.fingerprint }) {
        items[existingIndex].isPinned = items[existingIndex].isPinned || archived.isPinned
        if items[existingIndex].customTitle == nil {
          items[existingIndex].customTitle = archived.customTitle
        }
        if items[existingIndex].alias == nil,
          let alias = archived.alias,
          aliasIsAvailable(alias, excluding: items[existingIndex].id)
        {
          items[existingIndex].alias = alias
        }
        if items[existingIndex].richTextData == nil {
          if items[existingIndex].richTextFileName == nil, let archivedRichText {
            do {
              items[existingIndex].richTextFileName = try writeRichTextData(
                archivedRichText,
                for: items[existingIndex].id
              )
            } catch {
              setPersistenceIssue(error)
              throw error
            }
          }
          items[existingIndex].richTextData = nil
        }
        items[existingIndex].tags = Self.normalizedTags(
          items[existingIndex].tags + archived.tags)
        items[existingIndex].boardIDs = normalizedBoardIDs(
          items[existingIndex].boardIDs
            + archived.boardIDs.compactMap { boardMerge.idMap[$0] }
        )
        items[existingIndex].isConcealed =
          items[existingIndex].isConcealed || archived.isConcealed
        items[existingIndex].detectedBarcodes = DetectedBarcode.normalized(
          items[existingIndex].detectedBarcodes + archived.detectedBarcodes
        )
        if items[existingIndex].imageMetadata == nil {
          items[existingIndex].imageMetadata = archivedImage.flatMap {
            ImageMetadata.storedMetadata(for: $0)
          }
        }
        items[existingIndex].useCount = max(items[existingIndex].useCount, archived.useCount)
        items[existingIndex].lastUsedAt = latest(
          items[existingIndex].lastUsedAt, archived.lastUsedAt)
        items[existingIndex].expiresAt = earliestExpiration(
          items[existingIndex].expiresAt,
          archived.expiresAt
        )
        items[existingIndex].createdAt = max(items[existingIndex].createdAt, archived.createdAt)
        merged += 1
        continue
      }

      let newID = items.contains(where: { $0.id == archived.id }) ? UUID() : archived.id
      var imported: ClipItem
      switch archived.kind {
      case .text:
        let importedRichTextFileName: String?
        if let archivedRichText {
          do {
            importedRichTextFileName = try writeRichTextData(archivedRichText, for: newID)
          } catch {
            setPersistenceIssue(error)
            throw error
          }
        } else {
          importedRichTextFileName = nil
        }
        imported = copyOf(
          archived,
          id: newID,
          imageFileName: nil,
          richTextFileName: importedRichTextFileName,
          alias: archived.alias.flatMap { aliasIsAvailable($0) ? $0 : nil },
          boardIDs: archived.boardIDs.compactMap { boardMerge.idMap[$0] }
        )
      case .image:
        guard let image = archivedImage else {
          skipped += 1
          continue
        }
        let newFileName = "\(newID.uuidString).\(Self.imageFileExtension(for: image))"
        let destination = imagesURL.appendingPathComponent(newFileName)
        do {
          try writeProtectedData(image, to: destination)
          cacheImageData(image, fileName: newFileName)
        } catch {
          try? fileManager.removeItem(at: destination)
          setPersistenceIssue(error)
          throw error
        }
        imported = copyOf(
          archived,
          id: newID,
          imageFileName: newFileName,
          richTextFileName: nil,
          alias: archived.alias.flatMap { aliasIsAvailable($0) ? $0 : nil },
          boardIDs: archived.boardIDs.compactMap { boardMerge.idMap[$0] }
        )
        imported.imageMetadata = ImageMetadata.storedMetadata(for: image)
        if preferences.protectSecrets, (imported.imageMetadata?.frameCount ?? 1) > 1 {
          imported.isConcealed = true
        }
      case .files:
        imported = copyOf(
          archived,
          id: newID,
          imageFileName: nil,
          richTextFileName: nil,
          alias: archived.alias.flatMap { aliasIsAvailable($0) ? $0 : nil },
          boardIDs: archived.boardIDs.compactMap { boardMerge.idMap[$0] }
        )
      }

      items.append(imported)
      added += 1
    }

    sortItems()
    trimIfNeeded()
    let previousStackCount = stackIDs.count
    for fingerprint in payload.stackFingerprints {
      guard stackIDs.count < Self.maximumStackCount,
        let item = items.first(where: { $0.fingerprint == fingerprint }),
        canAddToStack(item),
        !stackIDs.contains(item.id)
      else { continue }
      stackIDs.append(item.id)
    }
    let importedSavedViewCount = mergeArchivedSavedViews(
      payload.savedViews,
      boardIDMap: boardMerge.idMap
    )
    selectedID = items.first?.id
    return ArchiveImportSummary(
      added: added,
      merged: merged,
      skipped: skipped,
      stacked: stackIDs.count - previousStackCount,
      savedViews: importedSavedViewCount,
      boards: boardMerge.importedCount
    )
  }

  private func persistArchiveHistorySynchronously() throws {
    try requireArchiveStorageAccess()
    try prepareStorage()
    let stagingURL = rootURL.appendingPathComponent(".clips-\(UUID().uuidString).pending")
    defer { try? fileManager.removeItem(at: stagingURL) }
    if let error = historyMetadataWriter(items, stagingURL, storageProtector, requiresStorageProtection) {
      historyPersistenceErrorMessage = error.message
      throw error
    }
    if fileManager.fileExists(atPath: metadataURL.path) {
      _ = try fileManager.replaceItemAt(metadataURL, withItemAt: stagingURL)
    } else {
      try fileManager.moveItem(at: stagingURL, to: metadataURL)
    }
    historyPersistenceErrorMessage = nil
    releaseArchiveAttachments(afterSaving: items)
  }

  private func persistArchiveCollections() throws {
    try requireArchiveStorageAccess()
    try prepareStorage()
    try writeProtectedData(JSONEncoder().encode(stackIDs), to: stackURL)
    try writeProtectedData(JSONEncoder().encode(savedViews), to: savedViewsURL)
    try writeProtectedData(JSONEncoder().encode(boards), to: boardsURL)
  }

  private func mergeArchivedBoards(_ archivedBoards: [ClipBoard]) -> (
    idMap: [UUID: UUID], importedCount: Int
  ) {
    var idMap: [UUID: UUID] = [:]
    var imported = 0
    for archived in archivedBoards {
      if let sameName = boards.first(where: {
        $0.name.localizedCaseInsensitiveCompare(archived.name) == .orderedSame
      }) {
        idMap[archived.id] = sameName.id
        continue
      }
      guard boards.count < ClipBoard.maximumCount else { continue }
      let id = boards.contains(where: { $0.id == archived.id }) ? UUID() : archived.id
      boards.append(ClipBoard(id: id, name: archived.name))
      idMap[archived.id] = id
      imported += 1
    }
    return (idMap, imported)
  }

  private func mergeArchivedSavedViews(
    _ archivedViews: [SavedClipView],
    boardIDMap: [UUID: UUID]
  ) -> Int {
    var imported = 0
    for archived in archivedViews where savedViews.count < SavedClipView.maximumCount {
      if savedViews.contains(where: {
        ($0.id == archived.id
          || $0.name.localizedCaseInsensitiveCompare(archived.name) == .orderedSame)
          && $0.matches(
            query: archived.query,
            filter: archived.filter,
            tag: archived.tag,
            boardID: archived.boardID.flatMap { boardIDMap[$0] },
            interpretsNaturalLanguage: archived.interpretsNaturalLanguage
          )
      }) {
        continue
      }

      let usedNames = Set(savedViews.map { SearchMatcher.normalize($0.name) })
      var name = archived.name
      if usedNames.contains(SearchMatcher.normalize(name)) {
        name = uniqueImportedSavedViewName(base: archived.name, usedNames: usedNames)
      }
      let id = savedViews.contains(where: { $0.id == archived.id }) ? UUID() : archived.id
      savedViews.append(
        SavedClipView(
          id: id,
          name: name,
          query: archived.query,
          filter: archived.filter,
          tag: archived.tag,
          boardID: archived.boardID.flatMap { boardIDMap[$0] },
          interpretsNaturalLanguage: archived.interpretsNaturalLanguage
        )
      )
      imported += 1
    }
    return imported
  }

  private func uniqueImportedSavedViewName(base: String, usedNames: Set<String>) -> String {
    var number = 1
    while true {
      let suffix = number == 1 ? " (Imported)" : " (Imported \(number))"
      let availableLength = max(0, SavedClipView.maximumNameLength - suffix.count)
      let candidate = String(base.prefix(availableLength)) + suffix
      if !usedNames.contains(SearchMatcher.normalize(candidate)) { return candidate }
      number += 1
    }
  }

  private func insert(_ item: ClipItem, preserveChronology: Bool = false) {
    if let duplicateIndex = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
      let duplicate = items.remove(at: duplicateIndex)
      if duplicate.imageFileName != item.imageFileName { removeStoredFile(for: duplicate) }
      var refreshedItem = item
      refreshedItem.customTitle = duplicate.customTitle
      refreshedItem.alias = duplicate.alias
      refreshedItem.tags = duplicate.tags
      refreshedItem.boardIDs = duplicate.boardIDs
      refreshedItem.isConcealed = duplicate.isConcealed
      refreshedItem.useCount = duplicate.useCount
      refreshedItem.lastUsedAt = duplicate.lastUsedAt
      if duplicate.isPinned {
        var pinnedItem = refreshedItem
        pinnedItem.isPinned = true
        items.insert(pinnedItem, at: 0)
      } else {
        items.insert(refreshedItem, at: 0)
      }
    } else {
      items.insert(item, at: 0)
    }
    if preserveChronology { sortItems() }
    trimIfNeeded()
    let showsAllHistory =
      searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && filter == .all
      && selectedTag == nil
      && selectedBoardID == nil
    if showsAllHistory {
      if !preserveChronology || items.first?.id == item.id { selectedID = item.id }
      if selectedID.map({ selected in items.contains { $0.id == selected } }) != true {
        selectedID = items.first?.id
      }
    } else {
      let visibleItems = filteredItems
      if !preserveChronology || visibleItems.first?.id == item.id {
        selectedID = visibleItems.first(where: { $0.id == item.id })?.id
      }
      if selectedID.map({ selected in visibleItems.contains { $0.id == selected } }) != true {
        selectedID = visibleItems.first?.id
      }
    }
    persist()
  }

  private func refreshDuplicate(
    at index: Int,
    source: String,
    sourceBundleIdentifier: String? = nil,
    createdAt: Date = .now
  ) {
    let id = items[index].id
    items[index].createdAt = createdAt
    items[index].sourceApplication = source
    items[index].sourceBundleIdentifier = ClipItem.normalizedSourceBundleIdentifier(
      sourceBundleIdentifier
    )
    items[index].boardIDs = normalizedBoardIDs(
      items[index].boardIDs + automaticContextBoardIDs(for: sourceBundleIdentifier)
    )
    sortItems()
    selectedID = id
    normalizeSelection()
    persist()
  }

  private func trimIfNeeded() {
    var removedIDs = Set<UUID>()
    defer {
      if !removedIDs.isEmpty {
        let previousStack = stackIDs
        stackIDs.removeAll { removedIDs.contains($0) }
        if stackIDs != previousStack { persistStack() }
        for id in removedIDs {
          contentKindCache.removeValue(forKey: id)
          searchIndexCache.removeValue(forKey: id)
        }
      }
    }
    if preferences.retentionDays > 0 {
      let cutoff =
        Calendar.current.date(
          byAdding: .day,
          value: -preferences.retentionDays,
          to: Date()
        ) ?? .distantPast
      let expired = items.filter { !$0.isPinned && $0.createdAt < cutoff }
      expired.forEach(removeStoredFile)
      let expiredIDs = Set(expired.map(\.id))
      removedIDs.formUnion(expiredIDs)
      items.removeAll { expiredIDs.contains($0.id) }
    }

    let maximumItems = preferences.itemLimit
    guard items.count > maximumItems else { return }
    let removable = items.indices.reversed().filter { !items[$0].isPinned }
    for index in removable.prefix(items.count - maximumItems) {
      let item = items[index]
      removeStoredFile(for: item)
      removedIDs.insert(item.id)
      items.remove(at: index)
    }
  }

  private func observePreferences() {
    preferences.objectWillChange
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in self?.objectWillChange.send() }
      }
      .store(in: &preferenceCancellables)

    preferences.$retentionDays
      .dropFirst()
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in self?.enforceRetentionPolicy() }
      }
      .store(in: &preferenceCancellables)

    preferences.$itemLimit
      .dropFirst()
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in self?.enforceRetentionPolicy() }
      }
      .store(in: &preferenceCancellables)

    preferences.$watchScreenshots
      .dropFirst()
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in self?.configureScreenshotWatching() }
      }
      .store(in: &preferenceCancellables)
  }

  private func startExpirationTimer() {
    expirationTimer?.invalidate()
    let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.purgeExpired() }
    }
    timer.tolerance = 3
    expirationTimer = timer
  }

  private func enforceRetentionPolicy() {
    trimIfNeeded()
    if selectedID.flatMap({ id in items.first { $0.id == id } }) == nil {
      selectedID = items.first?.id
    }
    persist()
  }

  private func sortItems() {
    items.sort {
      if $0.isPinned != $1.isPinned { return $0.isPinned }
      return $0.createdAt > $1.createdAt
    }
  }

  private func searchScore(
    for item: ClipItem,
    index: SearchIndexEntry,
    matcher: SearchMatcher
  ) -> Double {
    let query = matcher.query
    let aliasQuery = query.first == "@" ? String(query.dropFirst()) : query
    var score = recommendationScore(for: item) * 0.2

    if !index.alias.isEmpty, index.alias == aliasQuery { score += 5_000 }
    if index.text == query || index.ocr == query { score += 2_000 }
    if index.barcodes == query { score += 2_000 }
    if index.source == query { score += 1_200 }
    if index.tags.contains(query) { score += 1_500 }
    if index.title.hasPrefix(query) { score += 900 }
    if index.text.contains(query) { score += 650 }
    if index.ocr.contains(query) { score += 600 }
    if index.barcodes.contains(query) { score += 650 }
    if index.files.contains(query) { score += 650 }
    if index.source.hasPrefix(query) { score += 500 }
    if index.source.contains(query) { score += 300 }

    score += matcher.tokenBonus(
      normalizedText: index.searchableText,
      tokens: index.searchableTokens
    )
    return score
  }

  private func aliasSearchScore(
    for item: ClipItem,
    normalizedAlias: String,
    aliasTokens: [String],
    fragment: String,
    matcher: SearchMatcher
  ) -> Double {
    guard !normalizedAlias.isEmpty else { return -.infinity }
    let normalizedFragment = SearchMatcher.normalize(fragment)
    var score = recommendationScore(for: item) * 0.1
    if normalizedFragment.isEmpty { return score }
    if normalizedAlias == normalizedFragment { score += 5_000 }
    if normalizedAlias.hasPrefix(normalizedFragment) { score += 2_000 }
    if normalizedAlias.contains(normalizedFragment) { score += 800 }
    score += matcher.tokenBonus(
      normalizedText: normalizedAlias,
      tokens: aliasTokens
    )
    return score
  }

  private func contentKind(for item: ClipItem) -> ClipContentKind {
    guard !item.isConcealed else { return item.privacySafeContentKind }
    if let cached = contentKindCache[item.id] { return cached }
    let kind = item.contentAnalysis.kind
    contentKindCache[item.id] = kind
    return kind
  }

  private func pruneContentKindCache() {
    let availableIDs = Set(items.map(\.id))
    contentKindCache = contentKindCache.filter { availableIDs.contains($0.key) }
    searchIndexCache = searchIndexCache.filter { availableIDs.contains($0.key) }
  }

  private struct SearchIndexKey: Equatable {
    let text: String
    let ocrText: String
    let detectedBarcodes: [DetectedBarcode]
    let filePaths: [String]
    let customTitle: String?
    let alias: String?
    let tags: [String]
    let isConcealed: Bool
    let sourceApplication: String
    let sourceBundleIdentifier: String?

    init(item: ClipItem) {
      text = item.text
      ocrText = item.ocrText
      detectedBarcodes = item.detectedBarcodes
      filePaths = item.filePaths
      customTitle = item.customTitle
      alias = item.alias
      tags = item.tags
      isConcealed = item.isConcealed
      sourceApplication = item.sourceApplication
      sourceBundleIdentifier = item.sourceBundleIdentifier
    }
  }

  private struct SearchIndexEntry {
    static let maximumCachedTextBytes = 16_384

    let key: SearchIndexKey
    let searchableText: String
    let searchableTokens: [String]
    let text: String
    let ocr: String
    let barcodes: String
    let files: String
    let source: String
    let title: String
    let tags: [String]
    let alias: String
    let aliasTokens: [String]

    init(item: ClipItem, key: SearchIndexKey) {
      self.key = key
      let localizedSource = item.localizedSourceApplication()
      let searchableSource = [
        item.sourceApplication, localizedSource, item.sourceBundleIdentifier ?? "",
      ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
      searchableText = SearchMatcher.normalize(item.searchableText + " " + searchableSource)
      searchableTokens = SearchMatcher.tokens(in: searchableText)
      text = item.isConcealed ? "" : SearchMatcher.normalize(item.text)
      ocr = item.isConcealed ? "" : SearchMatcher.normalize(item.ocrText)
      barcodes =
        item.isConcealed ? "" : SearchMatcher.normalize(
          item.detectedBarcodes.map(\.payload).joined(separator: " "))
      files =
        item.isConcealed ? "" : SearchMatcher.normalize(item.filePaths.joined(separator: " "))
      source = SearchMatcher.normalize(searchableSource)
      title = SearchMatcher.normalize(item.localizedDisplayTitle())
      tags = item.tags.map(SearchMatcher.normalize)
      alias = SearchMatcher.normalize(item.alias ?? "")
      aliasTokens = SearchMatcher.tokens(in: alias)
    }

    var isSmallEnoughToCache: Bool {
      searchableText.utf8.count <= Self.maximumCachedTextBytes
    }
  }

  private func searchIndex(for item: ClipItem) -> SearchIndexEntry {
    let key = SearchIndexKey(item: item)
    if let cached = searchIndexCache[item.id], cached.key == key { return cached }
    let index = SearchIndexEntry(item: item, key: key)
    if isSessionActive, index.isSmallEnoughToCache {
      searchIndexCache[item.id] = index
    } else {
      searchIndexCache.removeValue(forKey: item.id)
    }
    return index
  }

  private func rankedItems(
    _ candidates: [(item: ClipItem, score: Double)],
    limit: Int?
  ) -> [ClipItem] {
    let precedes: ((item: ClipItem, score: Double), (item: ClipItem, score: Double)) -> Bool = {
      left, right in
      left.score == right.score
        ? left.item.createdAt > right.item.createdAt
        : left.score > right.score
    }
    if let limit, limit <= 0 { return [] }
    let sorted = candidates.sorted(by: precedes)
    guard let limit else { return sorted.map(\.item) }
    return sorted.prefix(limit).map(\.item)
  }

  private func recommendationScore(for item: ClipItem, now: Date = .now) -> Double {
    var score: Double = item.isPinned ? 300 : 0
    score += log2(Double(item.useCount) + 1) * 55

    let creationAgeHours = max(0, now.timeIntervalSince(item.createdAt) / 3_600)
    score += max(0, 96 - creationAgeHours)
    if let lastUsedAt = item.lastUsedAt {
      let useAgeHours = max(0, now.timeIntervalSince(lastUsedAt) / 3_600)
      score += max(0, 180 - useAgeHours * 2)
    }
    return score
  }

  private func prepareStorage() throws {
    try fileManager.createDirectory(
      at: imagesURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try fileManager.createDirectory(
      at: richTextURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: imagesURL.path)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: richTextURL.path)
  }

  private func load() {
    guard fileManager.fileExists(atPath: metadataURL.path) else {
      persistenceBlockedByUnreadableHistory = false
      return
    }
    do {
      let requiresProtectionMigration = try storedFileRequiresProtection(at: metadataURL)
      let data = try readProtectedData(from: metadataURL)
      let decodedItems = try JSONDecoder().decode([ClipItem].self, from: data)
      // Publish the intact decoded snapshot first. If a referenced encrypted sidecar fails
      // authentication below, the in-memory history retains that reference and remains blocked
      // from overwriting the only recoverable metadata copy.
      items = decodedItems
      var normalizedItems = decodedItems
      var seenAliases = Set<String>()
      for index in normalizedItems.indices {
        if normalizedItems[index].kind != .files { normalizedItems[index].filePaths = [] }
        normalizedItems[index].tags = Self.normalizedTags(normalizedItems[index].tags)
        if let normalizedAlias = ClipAlias.normalized(normalizedItems[index].alias ?? ""),
          seenAliases.insert(normalizedAlias).inserted
        {
          normalizedItems[index].alias = normalizedAlias
        } else {
          normalizedItems[index].alias = nil
        }
        if normalizedItems[index].kind == .text,
          let validatedRichText = try validatedRichTextData(for: normalizedItems[index])
        {
          if normalizedItems[index].richTextFileName == nil
            || normalizedItems[index].richTextData != nil
          {
            do {
              normalizedItems[index].richTextFileName = try writeRichTextData(
                validatedRichText,
                for: normalizedItems[index].id
              )
              normalizedItems[index].richTextData = nil
            } catch {
              setPersistenceIssue(error)
            }
          } else {
            normalizedItems[index].richTextData = nil
          }
        } else {
          normalizedItems[index].richTextFileName = nil
          normalizedItems[index].richTextData = nil
        }
      }
      items = normalizedItems
      pruneRichTextFiles()
      persistenceBlockedByUnreadableHistory = false
      sortItems()
      trimIfNeeded()
      selectedID = items.first?.id
      if requiresProtectionMigration || items != decodedItems { persist() }
    } catch let error as SecureLocalStorageError {
      persistenceBlockedByUnreadableHistory = true
      setPersistenceIssue(error)
    } catch {
      preserveUnreadableHistory(originalError: error)
    }
  }

  private func loadStack() {
    guard fileManager.fileExists(atPath: stackURL.path) else { return }
    do {
      let requiresProtectionMigration = try storedFileRequiresProtection(at: stackURL)
      let data = try readProtectedData(from: stackURL)
      let storedIDs = try JSONDecoder().decode([UUID].self, from: data)
      let availableIDs = Set(items.map(\.id))
      var seen = Set<UUID>()
      stackIDs = storedIDs.filter {
        availableIDs.contains($0) && seen.insert($0).inserted
      }.prefix(Self.maximumStackCount).map { $0 }
      if stackIDs != storedIDs || requiresProtectionMigration { persistStack() }
    } catch let error as SecureLocalStorageError {
      persistenceBlockedByUnreadableHistory = true
      setPersistenceIssue(error)
    } catch {
      preserveUnreadableStack(originalError: error)
    }
  }

  private func loadSavedViews() {
    guard fileManager.fileExists(atPath: savedViewsURL.path) else { return }
    do {
      let requiresProtectionMigration = try storedFileRequiresProtection(at: savedViewsURL)
      let data = try readProtectedData(from: savedViewsURL)
      let decoded = try JSONDecoder().decode([SavedClipView].self, from: data)
      var seenIDs = Set<UUID>()
      var seenNames = Set<String>()
      savedViews = decoded.compactMap { view in
        let name = Self.normalizedSavedViewName(view.name)
        let nameKey = SearchMatcher.normalize(name)
        guard !name.isEmpty,
          seenIDs.insert(view.id).inserted,
          seenNames.insert(nameKey).inserted,
          view.query.count <= SavedClipView.maximumQueryLength,
          view.tag.map({ !$0.isEmpty && $0.count <= Self.maximumTagLength }) ?? true
        else { return nil }
        return SavedClipView(
          id: view.id,
          name: name,
          query: view.query.trimmingCharacters(in: .whitespacesAndNewlines),
          filter: view.filter,
          tag: view.tag,
          boardID: view.boardID,
          interpretsNaturalLanguage: view.interpretsNaturalLanguage
        )
      }.prefix(SavedClipView.maximumCount).map { $0 }
      if savedViews != decoded || requiresProtectionMigration { persistSavedViews() }
    } catch let error as SecureLocalStorageError {
      persistenceBlockedByUnreadableHistory = true
      setPersistenceIssue(error)
    } catch {
      preserveUnreadableSavedViews(originalError: error)
    }
  }

  private func loadBoards() {
    guard fileManager.fileExists(atPath: boardsURL.path) else { return }
    do {
      let requiresProtectionMigration = try storedFileRequiresProtection(at: boardsURL)
      let data = try readProtectedData(from: boardsURL)
      let decoded = try JSONDecoder().decode([ClipBoard].self, from: data)
      var seenIDs = Set<UUID>()
      var seenNames = Set<String>()
      boards = decoded.compactMap { board in
        let name = Self.normalizedBoardName(board.name)
        let nameKey = SearchMatcher.normalize(name)
        guard !name.isEmpty,
          seenIDs.insert(board.id).inserted,
          seenNames.insert(nameKey).inserted
        else { return nil }
        return ClipBoard(id: board.id, name: name)
      }.prefix(ClipBoard.maximumCount).map { $0 }
      if boards != decoded || requiresProtectionMigration { persistBoards() }
    } catch let error as SecureLocalStorageError {
      persistenceBlockedByUnreadableHistory = true
      setPersistenceIssue(error)
    } catch {
      preserveUnreadableBoards(originalError: error)
    }
  }

  private func loadPrivacyRules() {
    guard fileManager.fileExists(atPath: privacyRulesURL.path) else { return }
    do {
      let requiresProtectionMigration = try storedFileRequiresProtection(at: privacyRulesURL)
      let data = try readProtectedData(from: privacyRulesURL)
      let decoded = try JSONDecoder().decode([ClipboardPrivacyRule].self, from: data)
      privacyRegexCache.removeAll(keepingCapacity: true)
      var seenIDs = Set<UUID>()
      var seenPatterns = Set<String>()
      privacyRules = decoded.compactMap { rule in
        let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let patternKey = "\(rule.mode.rawValue):\(SearchMatcher.normalize(pattern))"
        guard !pattern.isEmpty,
          pattern.count <= ClipboardPrivacyRule.maximumPatternLength,
          seenIDs.insert(rule.id).inserted,
          seenPatterns.insert(patternKey).inserted
        else { return nil }
        if rule.mode == .regularExpression, (try? SafeRegexSearch(pattern)) == nil {
          return nil
        }
        return ClipboardPrivacyRule(
          id: rule.id,
          pattern: pattern,
          mode: rule.mode,
          isEnabled: rule.isEnabled,
          matchCount: rule.matchCount,
          lastMatchedAt: rule.lastMatchedAt
        )
      }.prefix(ClipboardPrivacyRule.maximumCount).map { $0 }
      if privacyRules != decoded || requiresProtectionMigration { persistPrivacyRules() }
    } catch let error as SecureLocalStorageError {
      persistenceBlockedByUnreadableHistory = true
      setPersistenceIssue(error)
    } catch {
      preserveUnreadablePrivacyRules(originalError: error)
    }
  }

  private func persist() {
    guard !persistenceBlockedByUnreadableHistory, !isApplyingArchiveImport else { return }
    if persistsHistoryInBackground {
      historyPersistenceNeeded = true
      startPendingHistoryPersistence()
      return
    }
    do {
      try prepareStorage()
      let data = try JSONEncoder().encode(items)
      try writeProtectedData(data, to: metadataURL)
      historyPersistenceErrorMessage = nil
      releaseArchiveAttachments(afterSaving: items)
      if storageIssue?.kind == .persistence { storageIssue = nil }
    } catch {
      historyPersistenceErrorMessage = error.localizedDescription
      setPersistenceIssue(error)
    }
  }

  private func startPendingHistoryPersistence() {
    guard historyPersistenceTask == nil, historyPersistenceNeeded else { return }
    historyPersistenceGeneration += 1
    let generation = historyPersistenceGeneration
    historyPersistenceTask = Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, self.historyPersistenceGeneration == generation else { return }
      let snapshot = self.items
      self.historyPersistenceNeeded = false
      let destination = self.metadataURL
      let stagingURL = self.rootURL.appendingPathComponent(
        ".clips-\(UUID().uuidString).pending"
      )
      let protector = self.storageProtector
      let requiresProtection = self.requiresStorageProtection
      let writer = self.historyMetadataWriter
      let error = await Task.detached(priority: .utility) {
        writer(snapshot, stagingURL, protector, requiresProtection)
      }.value
      guard self.historyPersistenceGeneration == generation else {
        try? FileManager.default.removeItem(at: stagingURL)
        return
      }
      self.historyPersistenceTask = nil
      if let error {
        try? self.fileManager.removeItem(at: stagingURL)
        self.historyPersistenceErrorMessage = error.message
        self.setPersistenceIssue(error)
      } else if self.persistenceBlockedByUnreadableHistory {
        try? self.fileManager.removeItem(at: stagingURL)
      } else {
        do {
          if self.fileManager.fileExists(atPath: destination.path) {
            _ = try self.fileManager.replaceItemAt(destination, withItemAt: stagingURL)
          } else {
            try self.fileManager.moveItem(at: stagingURL, to: destination)
          }
          if let previousError = self.historyPersistenceErrorMessage,
            self.storageIssue?.kind == .persistence,
            self.storageIssue?.detail.contains(previousError) == true
          {
            self.storageIssue = nil
          }
          self.historyPersistenceErrorMessage = nil
          self.releaseArchiveAttachments(afterSaving: snapshot)
        } catch {
          try? self.fileManager.removeItem(at: stagingURL)
          let writeError = PersistenceWriteError(message: error.localizedDescription)
          self.historyPersistenceErrorMessage = writeError.message
          self.setPersistenceIssue(writeError)
        }
      }
      self.startPendingHistoryPersistence()
    }
  }

  func flushPendingHistoryPersistence() async {
    guard persistsHistoryInBackground else { return }
    while historyPersistenceNeeded || historyPersistenceTask != nil {
      startPendingHistoryPersistence()
      guard let task = historyPersistenceTask else { continue }
      await task.value
    }
  }

  var hasPendingHistoryPersistence: Bool {
    historyPersistenceNeeded || historyPersistenceTask != nil
  }

  func updatePendingNewSnippetDraft(_ draft: NewSnippetDraft) {
    let normalized = draft.hasContent ? draft : nil
    guard normalized != pendingNewSnippetDraft else { return }
    pendingNewSnippetDraft = normalized
    hasPendingNewSnippetDraft = normalized != nil
    scheduleNewSnippetDraftPersistence()
  }

  func discardPendingNewSnippetDraft() {
    guard pendingNewSnippetDraft != nil
      || fileManager.fileExists(atPath: newSnippetDraftURL.path)
    else { return }
    pendingNewSnippetDraft = nil
    hasPendingNewSnippetDraft = false
    scheduleNewSnippetDraftPersistence()
  }

  func flushPendingNewSnippetDraftPersistence() async {
    guard newSnippetDraftPersistenceNeeded || newSnippetDraftPersistenceTask != nil else { return }
    newSnippetDraftPersistenceGeneration += 1
    newSnippetDraftPersistenceTask?.cancel()
    newSnippetDraftPersistenceTask = nil
    persistNewSnippetDraftNow()
  }

  var hasPendingNewSnippetDraftPersistence: Bool {
    newSnippetDraftPersistenceNeeded || newSnippetDraftPersistenceTask != nil
  }

  private func scheduleNewSnippetDraftPersistence() {
    newSnippetDraftPersistenceNeeded = true
    newSnippetDraftPersistenceGeneration += 1
    let generation = newSnippetDraftPersistenceGeneration
    newSnippetDraftPersistenceTask?.cancel()
    newSnippetDraftPersistenceTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: 350_000_000)
      } catch {
        return
      }
      guard let self, self.newSnippetDraftPersistenceGeneration == generation else { return }
      self.newSnippetDraftPersistenceTask = nil
      self.persistNewSnippetDraftNow()
    }
  }

  private func persistNewSnippetDraftNow() {
    guard newSnippetDraftPersistenceNeeded else { return }
    newSnippetDraftPersistenceNeeded = false
    do {
      if let pendingNewSnippetDraft {
        try prepareStorage()
        let data = try JSONEncoder().encode(pendingNewSnippetDraft)
        guard data.count <= Self.maximumNewSnippetDraftStorageBytes else {
          throw PersistenceWriteError(
            message: L10n.text(
              "new_snippet.draft_too_large",
              fallback: "The draft is too large to save safely."))
        }
        try writeProtectedData(data, to: newSnippetDraftURL)
      } else if fileManager.fileExists(atPath: newSnippetDraftURL.path) {
        try fileManager.removeItem(at: newSnippetDraftURL)
      }
      if storageIssue?.kind == .persistence { storageIssue = nil }
    } catch {
      newSnippetDraftPersistenceNeeded = true
      setPersistenceIssue(error)
    }
  }

  private func loadNewSnippetDraft() {
    guard fileManager.fileExists(atPath: newSnippetDraftURL.path) else { return }
    do {
      let fileSize = try newSnippetDraftURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard fileSize <= Self.maximumNewSnippetDraftStorageBytes + 65_536 else {
        throw PersistenceWriteError(message: "New Snippet draft exceeds its storage limit.")
      }
      let needsEncryption = try storedFileRequiresProtection(at: newSnippetDraftURL)
      let data = try readProtectedData(from: newSnippetDraftURL)
      let draft = try JSONDecoder().decode(NewSnippetDraft.self, from: data)
      pendingNewSnippetDraft = draft.hasContent ? draft : nil
      hasPendingNewSnippetDraft = pendingNewSnippetDraft != nil
      if needsEncryption { try writeProtectedData(data, to: newSnippetDraftURL) }
    } catch {
      preserveUnreadableNewSnippetDraft(originalError: error)
    }
  }

  private func preserveUnreadableNewSnippetDraft(originalError: Error) {
    let recoveryName = "new-snippet-draft-unreadable-\(UUID().uuidString.prefix(8)).json"
    let recoveryURL = rootURL.appendingPathComponent(recoveryName)
    do {
      try fileManager.moveItem(at: newSnippetDraftURL, to: recoveryURL)
      pendingNewSnippetDraft = nil
      hasPendingNewSnippetDraft = false
      storageIssue = StorageIssue(
        kind: .recoveredHistory,
        message: L10n.text(
          "storage.draft_preserved", fallback: "Unreadable snippet draft was preserved"),
        detail: L10n.text(
          "storage.draft_preserved_detail",
          fallback: "The damaged encrypted draft was moved aside for recovery."),
        recoveryFileName: recoveryName
      )
    } catch {
      setPersistenceIssue(originalError)
    }
  }

  private func removeAbandonedHistoryStagingFiles() {
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: []
      )
    else { return }
    for url in files {
      let name = url.lastPathComponent
      guard name.hasPrefix(".clips-"), name.hasSuffix(".pending") else { continue }
      try? fileManager.removeItem(at: url)
    }
  }

  private func persistStack() {
    guard !persistenceBlockedByUnreadableHistory, !isApplyingArchiveImport else { return }
    do {
      try prepareStorage()
      let data = try JSONEncoder().encode(stackIDs)
      try writeProtectedData(data, to: stackURL)
      if storageIssue?.kind == .persistence { storageIssue = nil }
    } catch {
      setPersistenceIssue(error)
    }
  }

  private func persistSavedViews() {
    guard !persistenceBlockedByUnreadableHistory, !isApplyingArchiveImport else { return }
    do {
      try prepareStorage()
      let data = try JSONEncoder().encode(savedViews)
      try writeProtectedData(data, to: savedViewsURL)
      if storageIssue?.kind == .persistence { storageIssue = nil }
    } catch {
      setPersistenceIssue(error)
    }
  }

  private func persistBoards() {
    guard !persistenceBlockedByUnreadableHistory, !isApplyingArchiveImport else { return }
    do {
      try prepareStorage()
      let data = try JSONEncoder().encode(boards)
      try writeProtectedData(data, to: boardsURL)
      if storageIssue?.kind == .persistence { storageIssue = nil }
    } catch {
      setPersistenceIssue(error)
    }
  }

  private func persistPrivacyRules() {
    guard !persistenceBlockedByUnreadableHistory else { return }
    do {
      try prepareStorage()
      let data = try JSONEncoder().encode(privacyRules)
      try writeProtectedData(data, to: privacyRulesURL)
      if storageIssue?.kind == .persistence { storageIssue = nil }
    } catch {
      setPersistenceIssue(error)
    }
  }

  private func pruneBoardReferences() {
    guard boardStorageReadable else { return }
    let validIDs = Set(boards.map(\.id))
    var changed = false
    for index in items.indices {
      let normalized = items[index].boardIDs.filter(validIDs.contains)
      if normalized != items[index].boardIDs {
        items[index].boardIDs = normalized
        changed = true
      }
    }
    if selectedBoardID.map({ !validIDs.contains($0) }) == true { selectedBoardID = nil }
    let repairedViews = savedViews.map { view in
      guard let boardID = view.boardID, !validIDs.contains(boardID) else { return view }
      return SavedClipView(
        id: view.id,
        name: view.name,
        query: view.query,
        filter: view.filter,
        tag: view.tag,
        interpretsNaturalLanguage: view.interpretsNaturalLanguage
      )
    }
    if repairedViews != savedViews {
      savedViews = repairedViews
      persistSavedViews()
    }
    if changed { persist() }
  }

  private func normalizedBoardIDs(_ ids: [UUID]) -> [UUID] {
    let validIDs = Set(boards.map(\.id))
    var seen = Set<UUID>()
    return ids.filter { validIDs.contains($0) && seen.insert($0).inserted }
  }

  private func automaticContextBoardIDs(for bundleIdentifier: String?) -> [UUID] {
    guard preferences.automaticallyCollectsContext(bundleIdentifier: bundleIdentifier),
      let boardID = preferences.appContextBoardID(bundleIdentifier: bundleIdentifier),
      boards.contains(where: { $0.id == boardID })
    else { return [] }
    return [boardID]
  }

  private func pruneStack() {
    let availableIDs = Set(items.map(\.id))
    let pruned = stackIDs.filter(availableIDs.contains)
    guard pruned != stackIDs else { return }
    stackIDs = pruned
    persistStack()
  }

  private func preserveUnreadableStack(originalError: Error) {
    let recoveryName = "stack-unreadable-\(UUID().uuidString.prefix(8)).json"
    let recoveryURL = rootURL.appendingPathComponent(recoveryName)
    do {
      try fileManager.moveItem(at: stackURL, to: recoveryURL)
      stackIDs = []
      storageIssue = StorageIssue(
        kind: .recoveredHistory,
        message: L10n.text(
          "storage.stack_preserved", fallback: "Unreadable Stack was preserved"),
        detail: L10n.text(
          "storage.stack_preserved_detail",
          fallback: "Clip history is safe. The damaged Stack order was moved aside for recovery."),
        recoveryFileName: recoveryName
      )
    } catch {
      setPersistenceIssue(originalError)
    }
  }

  private func preserveUnreadableSavedViews(originalError: Error) {
    let recoveryName = "saved-views-unreadable-\(UUID().uuidString.prefix(8)).json"
    let recoveryURL = rootURL.appendingPathComponent(recoveryName)
    do {
      try fileManager.moveItem(at: savedViewsURL, to: recoveryURL)
      savedViews = []
      storageIssue = StorageIssue(
        kind: .recoveredHistory,
        message: L10n.text(
          "storage.views_preserved", fallback: "Unreadable saved views were preserved"),
        detail: L10n.text(
          "storage.views_preserved_detail",
          fallback:
            "Clip history is safe. The damaged saved-view file was moved aside for recovery."),
        recoveryFileName: recoveryName
      )
    } catch {
      setPersistenceIssue(originalError)
    }
  }

  private func preserveUnreadableBoards(originalError: Error) {
    let recoveryName = "boards-unreadable-\(UUID().uuidString.prefix(8)).json"
    let recoveryURL = rootURL.appendingPathComponent(recoveryName)
    do {
      try fileManager.moveItem(at: boardsURL, to: recoveryURL)
      boards = []
      boardStorageReadable = false
      storageIssue = StorageIssue(
        kind: .recoveredHistory,
        message: L10n.text(
          "storage.boards_preserved", fallback: "Unreadable Pinboards were preserved"),
        detail: L10n.text(
          "storage.boards_preserved_detail",
          fallback: "Clip history is safe. The damaged Pinboard file was moved aside for recovery."),
        recoveryFileName: recoveryName
      )
    } catch {
      setPersistenceIssue(originalError)
    }
  }

  private func preserveUnreadablePrivacyRules(originalError: Error) {
    let recoveryName = "privacy-rules-unreadable-\(UUID().uuidString.prefix(8)).json"
    let recoveryURL = rootURL.appendingPathComponent(recoveryName)
    do {
      try fileManager.moveItem(at: privacyRulesURL, to: recoveryURL)
      privacyRules = []
      storageIssue = StorageIssue(
        kind: .recoveredHistory,
        message: L10n.text(
          "storage.privacy_rules_preserved",
          fallback: "Unreadable privacy rules were preserved"
        ),
        detail: L10n.text(
          "storage.privacy_rules_preserved_detail",
          fallback: "The damaged privacy-rule file was moved aside for recovery."
        ),
        recoveryFileName: recoveryName
      )
    } catch {
      setPersistenceIssue(originalError)
    }
  }

  private func preserveUnreadableHistory(originalError: Error) {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let recoveryName =
      "clips-unreadable-\(formatter.string(from: .now))-\(UUID().uuidString.prefix(8)).json"
    let recoveryURL = rootURL.appendingPathComponent(recoveryName)
    do {
      try fileManager.moveItem(at: metadataURL, to: recoveryURL)
      persistenceBlockedByUnreadableHistory = false
      storageIssue = StorageIssue(
        kind: .recoveredHistory,
        message: L10n.text(
          "storage.history_preserved", fallback: "Unreadable history was preserved"),
        detail: L10n.text(
          "storage.history_preserved_detail",
          fallback:
            "Clipskein started with an empty history. The original file is still available for recovery."
        ),
        recoveryFileName: recoveryName
      )
    } catch {
      persistenceBlockedByUnreadableHistory = true
      storageIssue = StorageIssue(
        kind: .persistence,
        message: L10n.text(
          "storage.history_blocked", fallback: "History cannot be opened safely"),
        detail: L10n.format(
          "storage.history_blocked_detail",
          fallback: "Clipskein will not overwrite the unreadable history file. %@ %@",
          originalError.localizedDescription,
          error.localizedDescription),
        recoveryFileName: nil
      )
    }
  }

  private func setPersistenceIssue(_ error: Error) {
    storageIssue = StorageIssue(
      kind: .persistence,
      message: L10n.text("storage.not_saving", fallback: "History is not being saved"),
      detail: L10n.format(
        "storage.not_saving_detail",
        fallback: "New changes may be lost when Clipskein quits. %@",
        error.localizedDescription),
      recoveryFileName: nil
    )
  }

  private func frontmostApplication() -> (name: String, bundleIdentifier: String?) {
    let application = NSWorkspace.shared.frontmostApplication
    return (application?.localizedName ?? "Unknown app", application?.bundleIdentifier)
  }

  private func sourceApplication() -> (name: String, bundleIdentifier: String?) {
    let sourceType = NSPasteboard.PasteboardType(ClipboardCapturePolicy.sourceType)
    guard
      let identifier = pasteboard.string(forType: sourceType)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !identifier.isEmpty
    else {
      return frontmostApplication()
    }
    let application = NSWorkspace.shared.runningApplications.first {
      $0.bundleIdentifier == identifier
    }
    return (application?.localizedName ?? identifier, identifier)
  }

  private func removeStoredFile(for item: ClipItem) {
    if let fileName = item.imageFileName { removeCachedImage(fileName: fileName) }
    let storedURLs = [
      item.imageFileName.map { imagesURL.appendingPathComponent($0) },
      item.richTextFileName.map { richTextURL.appendingPathComponent($0) },
    ].compactMap { $0 }
    for url in storedURLs where fileManager.fileExists(atPath: url.path) {
      if url.deletingLastPathComponent() == imagesURL,
        archiveRetainedImageNames.contains(url.lastPathComponent) { continue }
      if url.deletingLastPathComponent() == richTextURL,
        archiveRetainedRichTextNames.contains(url.lastPathComponent) { continue }
      do {
        try fileManager.removeItem(at: url)
      } catch {
        setPersistenceIssue(error)
      }
    }
  }

  private func releaseArchiveAttachments(afterSaving snapshot: [ClipItem]) {
    guard !archiveRetainedImageNames.isEmpty || !archiveRetainedRichTextNames.isEmpty else { return }
    // A failed import must not delete files still referenced by the last good
    // history. Only a committed snapshot can make these files disposable.
    let savedImages = Set(snapshot.compactMap(\.imageFileName))
    let currentImages = Set(items.compactMap(\.imageFileName))
    let savedRichText = Set(snapshot.compactMap(\.richTextFileName))
    let currentRichText = Set(items.compactMap(\.richTextFileName))
    let imageReferences = savedImages.union(currentImages)
    let richTextReferences = savedRichText.union(currentRichText)
    let removableImages = archiveRetainedImageNames.subtracting(imageReferences)
    let removableRichText = archiveRetainedRichTextNames.subtracting(richTextReferences)
    for name in removableImages { try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name)) }
    for name in removableRichText { try? fileManager.removeItem(at: richTextURL.appendingPathComponent(name)) }
    archiveRetainedImageNames.subtract(removableImages)
    archiveRetainedRichTextNames.subtract(removableRichText)
    archiveRetainedImageNames.subtract(savedImages.intersection(currentImages))
    archiveRetainedRichTextNames.subtract(savedRichText.intersection(currentRichText))
  }

  private func cacheImageData(_ data: Data, fileName: String) {
    imageDataCache.setObject(data as NSData, forKey: fileName as NSString, cost: data.count)
  }

  private func removeCachedImage(fileName: String) {
    let key = fileName as NSString
    imageLoadTasks[fileName]?.cancel()
    imageLoadTasks[fileName] = nil
    failedImageLoads.remove(fileName)
    imageDataCache.removeObject(forKey: key)
    decodedImageCache.removeObject(forKey: key)
  }

  func discardCachedImages() {
    imageLoadTasks.values.forEach { $0.cancel() }
    imageLoadTasks.removeAll(keepingCapacity: true)
    failedImageLoads.removeAll(keepingCapacity: true)
    imageDataCache.removeAllObjects()
    decodedImageCache.removeAllObjects()
    imageCacheRevision &+= 1
  }

  private func decodedImageCost(_ image: NSImage) -> Int {
    let largestPixels = image.representations.reduce(Int64(0)) { current, representation in
      let width = Int64(max(0, representation.pixelsWide))
      let height = Int64(max(0, representation.pixelsHigh))
      let (pixels, overflowed) = width.multipliedReportingOverflow(by: height)
      return max(current, overflowed ? Int64.max / 4 : pixels)
    }
    let (estimatedBytes, overflowed) = largestPixels.multipliedReportingOverflow(by: 4)
    let bytes = min(overflowed ? Int64.max : estimatedBytes, Int64(Int.max))
    return max(1, Int(bytes))
  }

  func richTextData(for item: ClipItem) -> Data? {
    do {
      return try validatedRichTextData(for: item)
    } catch {
      if error is SecureLocalStorageError {
        persistenceBlockedByUnreadableHistory = true
      }
      setPersistenceIssue(error)
      return nil
    }
  }

  private func validatedRichTextData(for item: ClipItem) throws -> Data? {
    if let fileName = item.richTextFileName,
      fileName == URL(fileURLWithPath: fileName).lastPathComponent
    {
      let url = richTextURL.appendingPathComponent(fileName)
      if fileManager.fileExists(atPath: url.path) {
        let data = try readProtectedData(from: url)
        return RichTextPayload.validated(data, matching: item.text)
      }
    }
    if let data = item.richTextData {
      return RichTextPayload.validated(data, matching: item.text)
    }
    return nil
  }

  private func writeRichTextData(_ data: Data, for id: UUID) throws -> String {
    let fileName = "\(id.uuidString).rtf"
    let destination = richTextURL.appendingPathComponent(fileName)
    try writeProtectedData(data, to: destination)
    return fileName
  }

  private func readProtectedData(from url: URL) throws -> Data {
    let storedData = try Data(contentsOf: url)
    if let storageProtector {
      return try storageProtector.open(storedData).data
    }
    if requiresStorageProtection {
      throw SecureLocalStorageError.invalidKey
    }
    return storedData
  }

  private func storedFileRequiresProtection(at url: URL) throws -> Bool {
    guard storageProtector != nil else { return false }
    return try !SecureLocalStorage.fileHasEncryptedEnvelope(at: url)
  }

  private func writeProtectedData(_ data: Data, to url: URL) throws {
    let storedData: Data
    if let storageProtector {
      storedData = try storageProtector.seal(data)
    } else if requiresStorageProtection {
      throw SecureLocalStorageError.invalidKey
    } else {
      storedData = data
    }
    try storedData.write(to: url, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  private func migrateStoredPayloadsIfNeeded() {
    guard storageProtector != nil else { return }
    let referencedURLs = items.flatMap { item -> [URL] in
      var urls: [URL] = []
      if let fileName = item.imageFileName {
        urls.append(imagesURL.appendingPathComponent(fileName))
      }
      if let fileName = item.richTextFileName {
        urls.append(richTextURL.appendingPathComponent(fileName))
      }
      return urls
    }
    for url in referencedURLs where fileManager.fileExists(atPath: url.path) {
      do {
        guard try !SecureLocalStorage.fileHasEncryptedEnvelope(at: url) else { continue }
        let storedData = try Data(contentsOf: url, options: .mappedIfSafe)
        try writeProtectedData(storedData, to: url)
      } catch {
        if error is SecureLocalStorageError {
          persistenceBlockedByUnreadableHistory = true
        }
        setPersistenceIssue(error)
      }
    }
  }

  private func pruneRichTextFiles() {
    let referenced = Set(items.compactMap(\.richTextFileName))
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: richTextURL,
        includingPropertiesForKeys: nil
      )
    else { return }
    for file in files where !referenced.contains(file.lastPathComponent) {
      try? fileManager.removeItem(at: file)
    }
  }

  private func copyOf(
    _ item: ClipItem,
    id: UUID,
    imageFileName: String?,
    richTextFileName: String?,
    alias: String?,
    boardIDs: [UUID]
  ) -> ClipItem {
    ClipItem(
      id: id,
      kind: item.kind,
      text: item.text,
      ocrText: item.ocrText,
      ocrState: item.ocrState,
      ocrConfidence: item.ocrConfidence,
      detectedBarcodes: item.detectedBarcodes,
      imageFileName: imageFileName,
      imageMetadata: item.imageMetadata,
      filePaths: item.filePaths,
      customTitle: item.customTitle,
      alias: alias,
      richTextFileName: richTextFileName,
      richTextData: nil,
      tags: item.tags,
      boardIDs: normalizedBoardIDs(boardIDs),
      isConcealed: item.isConcealed,
      sourceApplication: item.sourceApplication,
      sourceBundleIdentifier: item.sourceBundleIdentifier,
      createdAt: item.createdAt,
      isPinned: item.isPinned,
      useCount: item.useCount,
      lastUsedAt: item.lastUsedAt,
      expiresAt: item.expiresAt,
      fingerprint: item.fingerprint
    )
  }

  private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
    let fileNamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    let legacy = (pasteboard.propertyList(forType: fileNamesType) as? [String] ?? []).map {
      URL(fileURLWithPath: $0)
    }
    if !legacy.isEmpty { return legacy }
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    return
      (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL] ?? [])
      .map { $0 as URL }
  }

  private func writeFileURLsToPasteboard(_ urls: [URL]) -> Bool {
    pasteboard.clearContents()
    if pasteboard.writeObjects(urls.map { $0 as NSURL }) { return true }

    // Compatibility fallback for older pasteboard consumers. Modern apps use the NSURL objects.
    pasteboard.clearContents()
    let fileNamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    pasteboard.declareTypes([.fileURL, fileNamesType], owner: nil)
    _ = pasteboard.setString(urls[0].absoluteString, forType: .fileURL)
    return pasteboard.setPropertyList(urls.map(\.path), forType: fileNamesType)
  }

  private func normalizedFilePaths(_ paths: [String]) -> [String] {
    guard !paths.isEmpty, paths.count <= Self.maximumFilesPerClip else { return [] }
    var seen = Set<String>()
    return paths.compactMap { path in
      guard !path.isEmpty, path.utf8.count <= 16_384 else { return nil }
      let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
      guard normalized == path, seen.insert(path).inserted else { return nil }
      return path
    }
  }

  private func fileFingerprint(_ paths: [String]) -> String {
    digest(Data((["files"] + paths).joined(separator: "\0").utf8))
  }

  private func aliasIsAvailable(_ alias: String, excluding id: UUID? = nil) -> Bool {
    let key = SearchMatcher.normalize(alias)
    return !items.contains { $0.id != id && SearchMatcher.normalize($0.alias ?? "") == key }
  }

  private func latest(_ left: Date?, _ right: Date?) -> Date? {
    switch (left, right) {
    case (.none, .none): nil
    case (.some(let date), .none), (.none, .some(let date)): date
    case (.some(let left), .some(let right)): max(left, right)
    }
  }

  private func earliestExpiration(_ left: Date?, _ right: Date?) -> Date? {
    switch (left, right) {
    case (.none, .none): nil
    case (.some(let date), .none), (.none, .some(let date)): date
    case (.some(let left), .some(let right)): min(left, right)
    }
  }

  private func handleRegionRecognition(_ result: OCRResult) {
    switch result {
    case .recognized(let text):
      if Self.shouldConcealRecognizedText(
        text,
        protectionEnabled: preferences.protectSecrets
      ) {
        showNotice(
          L10n.text(
            "notice.ocr_sensitive",
            fallback: "Sensitive text detected; screenshot saved but text was not copied"),
          systemImage: "eye.slash.fill"
        )
        return
      }
      pasteboard.clearContents()
      guard pasteboard.setString(text, forType: .string) else {
        showNotice(
          L10n.text(
            "notice.ocr_copy_failed", fallback: "Text was recognized but could not be copied"),
          systemImage: "exclamationmark.triangle.fill")
        return
      }
      annotatePasteboardWrite()
      lastChangeCount = pasteboard.changeCount
      showNotice(
        L10n.text("notice.ocr_copied", fallback: "Recognized text copied to clipboard"),
        systemImage: "checkmark.circle.fill")
    case .noText:
      showNotice(
        L10n.text(
          "notice.ocr_no_text", fallback: "Screenshot saved; no readable text found"),
        systemImage: "text.magnifyingglass")
    case .failed:
      showNotice(
        L10n.text(
          "notice.ocr_failed", fallback: "Screenshot saved; text recognition failed; try again"),
        systemImage: "exclamationmark.triangle.fill")
    }
  }

  private func handleRegionAnalysis(_ analysis: ImageAnalysisResult) {
    if case .noText = analysis.ocr, let barcode = analysis.barcodes.first {
      let combinedPayload = analysis.barcodes.map(\.payload).joined(separator: "\n")
      if Self.shouldConcealRecognizedText(
        combinedPayload,
        protectionEnabled: preferences.protectSecrets
      ) {
        showNotice(
          L10n.text(
            "notice.barcode_sensitive",
            fallback: "Sensitive code detected; screenshot saved but its value was not copied"
          ),
          systemImage: "eye.slash.fill"
        )
        return
      }
      pasteboard.clearContents()
      guard pasteboard.setString(barcode.payload, forType: .string) else {
        showNotice(
          L10n.text(
            "notice.barcode_copy_failed",
            fallback: "A code was detected but could not be copied"
          ),
          systemImage: "exclamationmark.triangle.fill"
        )
        return
      }
      annotatePasteboardWrite()
      lastChangeCount = pasteboard.changeCount
      showNotice(
        L10n.format("notice.barcode_copied", fallback: "%@ copied", barcode.localizedKind),
        systemImage: "checkmark.circle.fill"
      )
      return
    }
    handleRegionRecognition(analysis.ocr)
  }

  private func reportAutomaticCodeExpiration() {
    showNotice(
      L10n.text("notice.code_expiration", fallback: "One-time code expires in 15 minutes"),
      systemImage: "timer")
  }

  private func showNotice(
    _ message: String,
    systemImage: String,
    action: StoreNoticeAction? = nil
  ) {
    let nextNotice = StoreNotice(message: message, systemImage: systemImage, action: action)
    notice = nextNotice
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(action == nil ? 4 : 8))
      guard self?.notice == nextNotice else { return }
      self?.notice = nil
    }
  }

  func reportNotice(_ message: String, systemImage: String) {
    showNotice(message, systemImage: systemImage)
  }

  private func offerUndo(for clips: [DeletedClip], message: String) {
    deletedClips = clips
    canUndoDeletion = !clips.isEmpty
    showNotice(message, systemImage: "trash", action: .undoDeletion)
  }

  static func looksSensitive(_ text: String) -> Bool {
    let patterns = [
      #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
      #"(?i)(password|passwd|pwd|secret|api[_-]?key|access[_-]?token)\s*[:=]\s*\S+"#,
      #"\bsk-[A-Za-z0-9_-]{20,}\b"#,
      #"\bAKIA[A-Z0-9]{16}\b"#,
      #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#,
    ]
    return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
  }

  static func shouldConcealRecognizedText(
    _ text: String,
    protectionEnabled: Bool
  ) -> Bool {
    protectionEnabled && looksSensitive(text)
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func enqueueClipboardImage(
    data: Data,
    source: String,
    sourceBundleIdentifier: String?,
    capturedAt: Date,
    requiresNormalization: Bool,
    validatesGIF: Bool = false,
    fallbackImageData: Data? = nil,
    fallbackImageRequiresNormalization: Bool = false,
    fallbackText: String?,
    fallbackRichTextData: Data?
  ) {
    pendingClipboardImages.append(
      PendingClipboardImage(
        data: data,
        source: source,
        sourceBundleIdentifier: ClipItem.normalizedSourceBundleIdentifier(
          sourceBundleIdentifier
        ),
        capturedAt: capturedAt,
        requiresNormalization: requiresNormalization,
        validatesGIF: validatesGIF,
        fallbackImageData: fallbackImageData,
        fallbackImageRequiresNormalization: fallbackImageRequiresNormalization,
        fallbackText: fallbackText,
        fallbackRichTextData: fallbackRichTextData
      )
    )
    while pendingClipboardImages.count > 4
      || (pendingClipboardImages.count > 1
        && pendingClipboardImages.reduce(0, {
          $0 + $1.data.count + ($1.fallbackImageData?.count ?? 0)
        }) > 64 * 1_024 * 1_024)
    {
      pendingClipboardImages.removeFirst()
    }
    processNextClipboardImage()
  }

  private func processNextClipboardImage() {
    guard clipboardImageCaptureTask == nil, isSessionActive,
      !pendingClipboardImages.isEmpty
    else { return }
    let pending = pendingClipboardImages.removeFirst()
    let normalizer = clipboardImageNormalizer
    let writer = clipboardImageWriter
    let generation = UUID()
    clipboardImageCaptureGeneration = generation
    clipboardImageCaptureTask = Task { @MainActor [weak self] in
      let prepared = await Task.detached(priority: .utility) {
        let primaryData: Data? = pending.validatesGIF && !ImageMetadata.isValidGIF(pending.data)
          ? nil : (pending.requiresNormalization ? normalizer(pending.data) : pending.data)
        let data = primaryData ?? pending.fallbackImageData.flatMap {
          pending.fallbackImageRequiresNormalization ? normalizer($0) : $0
        }
        guard let data else { return nil as PreparedClipboardImageData? }
        let fingerprint = SHA256.hash(data: data)
          .map { String(format: "%02x", $0) }
          .joined()
        return PreparedClipboardImageData(
          data: data,
          fingerprint: fingerprint,
          metadata: ImageMetadata.storedMetadata(for: data)
        )
      }.value
      guard let self, self.clipboardImageCaptureGeneration == generation else { return }
      guard !Task.isCancelled, self.isSessionActive else {
        self.finishClipboardImageCapture(generation: generation)
        return
      }
      guard let prepared else {
        if let fallbackText = pending.fallbackText {
          if self.captureTextIfAllowed(
            fallbackText,
            source: pending.source,
            sourceBundleIdentifier: pending.sourceBundleIdentifier,
            richTextData: pending.fallbackRichTextData,
            createdAt: pending.capturedAt
          ) {
            self.playCaptureFeedbackIfEnabled()
          }
        }
        self.finishClipboardImageCapture(generation: generation)
        return
      }

      if let duplicateIndex = self.items.firstIndex(where: {
        $0.fingerprint == prepared.fingerprint
      }) {
        if self.items[duplicateIndex].imageMetadata == nil {
          self.items[duplicateIndex].imageMetadata = prepared.metadata
        }
        self.refreshDuplicate(
          at: duplicateIndex,
          source: pending.source,
          sourceBundleIdentifier: pending.sourceBundleIdentifier,
          createdAt: pending.capturedAt
        )
        self.playCaptureFeedbackIfEnabled()
        self.finishClipboardImageCapture(generation: generation)
        return
      }

      let id = UUID()
      let fileName = "\(id.uuidString).\(Self.imageFileExtension(for: prepared.data))"
      let destination = self.imagesURL.appendingPathComponent(fileName)
      let protector = self.storageProtector
      let requiresProtection = self.requiresStorageProtection
      let writeError = await Task.detached(priority: .utility) {
        writer(prepared.data, destination, protector, requiresProtection)
      }.value
      guard self.clipboardImageCaptureGeneration == generation,
        !Task.isCancelled, self.isSessionActive
      else {
        if writeError == nil { try? FileManager.default.removeItem(at: destination) }
        return
      }
      if let writeError {
        self.setPersistenceIssue(writeError)
        self.finishClipboardImageCapture(generation: generation)
        return
      }
      if let duplicateIndex = self.items.firstIndex(where: {
        $0.fingerprint == prepared.fingerprint
      }) {
        try? FileManager.default.removeItem(at: destination)
        if self.items[duplicateIndex].imageMetadata == nil {
          self.items[duplicateIndex].imageMetadata = prepared.metadata
        }
        self.refreshDuplicate(
          at: duplicateIndex,
          source: pending.source,
          sourceBundleIdentifier: pending.sourceBundleIdentifier,
          createdAt: pending.capturedAt
        )
        self.playCaptureFeedbackIfEnabled()
        self.finishClipboardImageCapture(generation: generation)
        return
      }

      self.cacheImageData(prepared.data, fileName: fileName)
      let item = ClipItem(
        id: id,
        kind: .image,
        imageFileName: fileName,
        imageMetadata: prepared.metadata,
        boardIDs: self.automaticContextBoardIDs(for: pending.sourceBundleIdentifier),
        isConcealed: self.preferences.protectSecrets,
        sourceApplication: pending.source,
        sourceBundleIdentifier: pending.sourceBundleIdentifier,
        createdAt: pending.capturedAt,
        fingerprint: prepared.fingerprint
      )
      self.insert(item, preserveChronology: true)
      self.recognizeImage(id: id, data: prepared.data)
      self.playCaptureFeedbackIfEnabled()
      self.finishClipboardImageCapture(generation: generation)
    }
  }

  private func finishClipboardImageCapture(generation: UUID) {
    guard clipboardImageCaptureGeneration == generation else { return }
    clipboardImageCaptureTask = nil
    clipboardImageCaptureGeneration = nil
    processNextClipboardImage()
  }

  private func playCaptureFeedbackIfEnabled() {
    guard preferences.captureFeedbackSound, isSessionActive else { return }
    captureFeedbackPlayer()
  }

  private func annotatePasteboardWrite() {
    let generatedType = NSPasteboard.PasteboardType(ClipboardCapturePolicy.autoGeneratedType)
    // An empty value is retained by named test pasteboards but can be dropped by the
    // system pasteboard. A one-byte marker survives real cross-process clipboard use.
    pasteboard.setData(Data([1]), forType: generatedType)
    let sourceType = NSPasteboard.PasteboardType(ClipboardCapturePolicy.sourceType)
    let sourceIdentifier = Bundle.main.bundleIdentifier ?? "app.clipnest.ClipNest"
    pasteboard.setString(sourceIdentifier, forType: sourceType)
  }

  private func consumeIgnoreNextCopy() -> Bool {
    guard oneShotCaptureGuard.consume() else { return false }
    isIgnoringNextCopy = false
    showNotice(
      L10n.text("notice.copy_ignored", fallback: "Ignored one copied item"),
      systemImage: "checkmark.shield.fill")
    return true
  }

  private func scheduleSecureClipboardClear(after seconds: TimeInterval) {
    secureCopyTask?.cancel()
    let delay = max(0.01, seconds)
    let expectedChangeCount = pasteboard.changeCount
    secureCopyExpectedChangeCount = expectedChangeCount
    let generation = UUID()
    secureCopyGeneration = generation
    secureCopyExpiration = Date().addingTimeInterval(delay)
    showNotice(
      L10n.text("notice.secure_copy_scheduled", fallback: "Secure copy will clear automatically"),
      systemImage: "timer"
    )
    secureCopyTask = Task { [weak self] in
      let cleared = await Self.performSecureClipboardClear(
        after: delay,
        expectedChangeCount: expectedChangeCount,
        currentChangeCount: { [weak self] in self?.pasteboard.changeCount ?? -1 },
        clear: { [weak self] in
          guard let self else { return }
          self.pasteboard.clearContents()
          self.lastChangeCount = self.pasteboard.changeCount
        }
      )
      guard let self, self.secureCopyGeneration == generation else { return }
      defer {
        self.secureCopyTask = nil
        self.secureCopyGeneration = nil
        self.secureCopyExpectedChangeCount = nil
        self.secureCopyExpiration = nil
      }
      if cleared {
        self.showNotice(
          L10n.text("notice.secure_copy_cleared", fallback: "Secure clipboard cleared"),
          systemImage: "checkmark.shield.fill")
      }
    }
  }

  private func cancelSecureClipboardClear() {
    secureCopyTask?.cancel()
    secureCopyTask = nil
    secureCopyGeneration = nil
    secureCopyExpectedChangeCount = nil
    secureCopyExpiration = nil
  }

  private func dragThumbnail(_ image: NSImage, maximumDimension: CGFloat) -> NSImage {
    guard image.size.width > 0, image.size.height > 0 else { return image }
    let scale = min(maximumDimension / image.size.width, maximumDimension / image.size.height, 1)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let thumbnail = NSImage(size: size)
    thumbnail.lockFocus()
    image.draw(
      in: NSRect(origin: .zero, size: size),
      from: NSRect(origin: .zero, size: image.size),
      operation: .sourceOver,
      fraction: 1
    )
    thumbnail.unlockFocus()
    return thumbnail
  }

  private func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    return bitmap.representation(using: .png, properties: [:])
  }

  private func writeImageToPasteboard(_ image: NSImage, originalData: Data?) -> Bool {
    guard let pasteboardItem = imagePasteboardItem(image, originalData: originalData) else {
      return false
    }
    pasteboard.clearContents()
    return pasteboard.writeObjects([pasteboardItem])
  }

  private func imagePasteboardItem(_ image: NSImage, originalData: Data?) -> NSPasteboardItem? {
    let pasteboardItem = NSPasteboardItem()
    var hasRepresentation = false
    if let originalData {
      if Self.hasGIFSignature(originalData) {
        let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
        hasRepresentation =
          pasteboardItem.setData(originalData, forType: gifType) || hasRepresentation
        if let png = pngData(from: image) {
          hasRepresentation = pasteboardItem.setData(png, forType: .png) || hasRepresentation
        }
      } else if Self.hasPNGSignature(originalData) {
        hasRepresentation =
          pasteboardItem.setData(originalData, forType: .png) || hasRepresentation
      }
    }
    if let tiff = image.tiffRepresentation {
      hasRepresentation = pasteboardItem.setData(tiff, forType: .tiff) || hasRepresentation
    }
    return hasRepresentation ? pasteboardItem : nil
  }

  private func textPasteboardItem(_ text: String, richTextData: Data?) -> NSPasteboardItem? {
    guard !text.isEmpty else { return nil }
    let pasteboardItem = NSPasteboardItem()
    guard pasteboardItem.setString(text, forType: .string) else { return nil }
    if let url = ContentClassifier.webURL(from: text) {
      _ = pasteboardItem.setString(
        url.absoluteString,
        forType: NSPasteboard.PasteboardType("public.url")
      )
    }
    if let validatedRichText = RichTextPayload.validated(richTextData, matching: text) {
      _ = pasteboardItem.setData(validatedRichText, forType: .rtf)
    }
    return pasteboardItem
  }

  nonisolated static func hasPNGSignature(_ data: Data) -> Bool {
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    return data.count >= signature.count
      && data.prefix(signature.count).elementsEqual(signature)
  }

  nonisolated static func hasGIFSignature(_ data: Data) -> Bool {
    guard data.count >= 6 else { return false }
    let header = String(decoding: data.prefix(6), as: UTF8.self)
    return header == "GIF87a" || header == "GIF89a"
  }

  nonisolated static func imageFileExtension(for data: Data) -> String {
    hasGIFSignature(data) ? "gif" : "png"
  }
}
