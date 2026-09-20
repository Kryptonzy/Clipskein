import CryptoKit
import Foundation
import NaturalLanguage

struct SemanticSearchRequest: Equatable, Sendable {
  static let prefixes = ["meaning:", "semantic:", "意思:", "语义:"]

  let query: String

  init?(_ rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("~") {
      query = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
      return
    }
    let normalized = SearchMatcher.normalize(trimmed)
    guard let prefix = Self.prefixes.first(where: normalized.hasPrefix) else { return nil }
    let boundary = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
    query = String(trimmed[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var isValid: Bool { query.count >= 2 && query.utf8.count <= 1_024 }
  var cacheKey: String { SearchMatcher.normalize(query) }

  static func suggestedQuery(for item: ClipItem) -> String? {
    guard !item.isConcealed else { return nil }
    let content: String
    if let customTitle = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
      !customTitle.isEmpty
    {
      content = customTitle
    } else {
      content = switch item.kind {
      case .text: item.text
      case .image: item.ocrText
      case .files:
        item.filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
          .joined(separator: " ")
      }
    }
    let compact = content.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    let bounded = String(compact.prefix(240)).trimmingCharacters(in: .whitespacesAndNewlines)
    return SemanticSearchRequest("~ \(bounded)")?.isValid == true ? bounded : nil
  }
}

struct SemanticSearchDocument: Equatable, Sendable {
  struct Signature: Equatable, Sendable {
    let hash: Int
    let utf8Count: Int
  }

  static let maximumTextCharacters = 4_096

  let id: UUID
  let text: String
  let signature: Signature

  init?(item: ClipItem) {
    guard !item.isConcealed else { return nil }
    let content: String
    switch item.kind {
    case .text:
      content = item.text
    case .image:
      content = [item.ocrText, item.detectedBarcodes.map(\.payload).joined(separator: " ")]
        .joined(separator: " ")
    case .files:
      content = item.filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
        .joined(separator: " ")
    }
    let combined = [
      item.customTitle ?? "", item.tags.joined(separator: " "), content,
      item.sourceApplication,
    ]
    .joined(separator: " ")
    .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !combined.isEmpty else { return nil }
    let boundedText = String(combined.prefix(Self.maximumTextCharacters))
    id = item.id
    text = boundedText
    signature = Self.signature(for: boundedText)
  }

  init(id: UUID = UUID(), text: String) {
    let boundedText = String(text.prefix(Self.maximumTextCharacters))
    self.id = id
    self.text = boundedText
    signature = Self.signature(for: boundedText)
  }

  private static func signature(for text: String) -> Signature {
    var hasher = Hasher()
    hasher.combine(text)
    return Signature(hash: hasher.finalize(), utf8Count: text.utf8.count)
  }
}

struct SemanticVector: Equatable, Sendable {
  let language: String
  let values: [Float]

  init?(language: String, values: [Float]) {
    guard !values.isEmpty else { return nil }
    let magnitude = sqrt(values.reduce(Float.zero) { $0 + $1 * $1 })
    guard magnitude.isFinite, magnitude > 0 else { return nil }
    self.language = language
    self.values = values.map { $0 / magnitude }
  }

  func similarity(to other: Self) -> Float? {
    guard language == other.language, values.count == other.values.count else { return nil }
    var result = Float.zero
    values.withUnsafeBufferPointer { left in
      other.values.withUnsafeBufferPointer { right in
        for index in left.indices { result += left[index] * right[index] }
      }
    }
    return result
  }
}

struct SemanticSearchHit: Equatable, Sendable {
  let id: UUID
  let score: Float
}

enum SemanticMatchConfidence: Equatable, Sendable {
  static let minimumCollectionScore: Float = 0.24

  case strong
  case related
  case possible

  init(score: Float) {
    if score >= 0.5 {
      self = .strong
    } else if score >= Self.minimumCollectionScore {
      self = .related
    } else {
      self = .possible
    }
  }

  var localizedLabel: String {
    switch self {
    case .strong:
      L10n.text("semantic.match.strong", fallback: "Strong meaning match")
    case .related:
      L10n.text("semantic.match.related", fallback: "Related by meaning")
    case .possible:
      L10n.text("semantic.match.possible", fallback: "Possible meaning match")
    }
  }

  var systemImage: String {
    switch self {
    case .strong: "sparkles"
    case .related: "brain.head.profile"
    case .possible: "waveform.path.ecg"
    }
  }
}

struct SemanticSearchResult: Equatable, Sendable {
  enum Availability: Equatable, Sendable {
    case available
    case modelUnavailable
    case invalidQuery
  }

  let availability: Availability
  let hits: [SemanticSearchHit]
  let indexedDocumentCount: Int
}

enum SemanticSearchStatus: Equatable, Sendable {
  case inactive
  case preparing(query: String)
  case refining(query: String, indexedCount: Int, totalCount: Int, resultCount: Int)
  case ready(query: String, resultCount: Int, indexedCount: Int)
  case invalidQuery
  case modelUnavailable

  var isPreparing: Bool {
    switch self {
    case .preparing, .refining: true
    default: false
    }
  }

  var canCollectResults: Bool {
    if case .ready(_, let resultCount, _) = self { return resultCount > 0 }
    return false
  }

  var localizedMessage: String? {
    switch self {
    case .inactive:
      nil
    case .preparing:
      L10n.text(
        "semantic.preparing",
        fallback: "Finding related memories locally…"
      )
    case .refining(_, let indexedCount, let totalCount, let resultCount):
      L10n.format(
        "semantic.refining",
        fallback: "Showing %d early results · refining %d of %d local memories…",
        resultCount,
        indexedCount,
        totalCount
      )
    case .ready(_, let resultCount, let indexedCount):
      L10n.format(
        "semantic.ready",
        fallback: "Meaning search found %d results across %d private local memories",
        resultCount,
        indexedCount
      )
    case .invalidQuery:
      L10n.text(
        "semantic.invalid",
        fallback: "Add at least two characters after ~ to search by meaning."
      )
    case .modelUnavailable:
      L10n.text(
        "semantic.unavailable",
        fallback: "The on-device language model is unavailable for this query."
      )
    }
  }
}

actor SemanticSearchIndex {
  typealias Vectorizer = @Sendable (String) -> SemanticVector?

  private struct CachedVector {
    let signature: SemanticSearchDocument.Signature
    let vector: SemanticVector?
  }

  private let vectorizer: Vectorizer
  private let removeVectorizerCache: @Sendable () -> Void
  private var vectors: [UUID: CachedVector] = [:]

  init() {
    let systemVectorizer = SystemSemanticVectorizer()
    self.vectorizer = { systemVectorizer.vector(for: $0) }
    self.removeVectorizerCache = { systemVectorizer.removeAllCachedTokens() }
  }

  init(vectorizer: @escaping Vectorizer) {
    self.vectorizer = vectorizer
    self.removeVectorizerCache = {}
  }

  func search(
    request: SemanticSearchRequest,
    documents: [SemanticSearchDocument],
    limit: Int? = nil,
    prunesMissingDocuments: Bool = true
  ) -> SemanticSearchResult {
    guard request.isValid else {
      return SemanticSearchResult(
        availability: .invalidQuery,
        hits: [],
        indexedDocumentCount: 0
      )
    }
    guard let queryVector = vectorizer(request.query) else {
      return SemanticSearchResult(
        availability: .modelUnavailable,
        hits: [],
        indexedDocumentCount: 0
      )
    }

    if prunesMissingDocuments {
      let liveIDs = Set(documents.map(\.id))
      vectors = vectors.filter { liveIDs.contains($0.key) }
    }
    var hits: [SemanticSearchHit] = []
    hits.reserveCapacity(documents.count)
    var indexedCount = 0

    for document in documents {
      if Task.isCancelled { break }
      let vector: SemanticVector?
      if let cached = vectors[document.id], cached.signature == document.signature {
        vector = cached.vector
      } else {
        vector = vectorizer(document.text)
        vectors[document.id] = CachedVector(signature: document.signature, vector: vector)
      }
      guard let vector else { continue }
      indexedCount += 1
      guard let similarity = queryVector.similarity(to: vector), similarity.isFinite else {
        continue
      }
      hits.append(SemanticSearchHit(id: document.id, score: similarity))
    }

    hits.sort {
      $0.score == $1.score ? $0.id.uuidString < $1.id.uuidString : $0.score > $1.score
    }
    if let limit {
      hits = Array(hits.prefix(max(0, limit)))
    }
    return SemanticSearchResult(
      availability: .available,
      hits: hits,
      indexedDocumentCount: indexedCount
    )
  }

  func removeAll() {
    vectors.removeAll(keepingCapacity: false)
    removeVectorizerCache()
  }

  func remove(ids: Set<UUID>) {
    guard !ids.isEmpty else { return }
    for id in ids { vectors.removeValue(forKey: id) }
  }

  var cachedDocumentCount: Int { vectors.count }
}

final class SystemSemanticVectorizer: @unchecked Sendable {
  static let shared = SystemSemanticVectorizer()
  static let maximumTokens = 64
  private static let maximumCachedTokens = 4_096

  private struct TokenCacheKey: Hashable {
    let language: String
    let digest: SHA256.Digest
  }

  private enum CachedTokenVector {
    case available([Float])
    case missing
  }

  private let lock = NSLock()
  private var embeddings: [String: NLEmbedding] = [:]
  private var tokenVectors: [TokenCacheKey: CachedTokenVector] = [:]

  private let ignoredTokens: Set<String> = [
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in", "is", "it",
    "of", "on", "or", "that", "the", "this", "to", "was", "were", "with", "you", "your",
    "了", "和", "在", "是", "的", "与", "及", "这", "那", "一个", "我们", "你", "我",
  ]

  init() {}

  func removeAllCachedTokens() {
    lock.lock()
    tokenVectors.removeAll(keepingCapacity: false)
    lock.unlock()
  }

  var cachedTokenCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return tokenVectors.count
  }

  func vector(for rawText: String) -> SemanticVector? {
    lock.lock()
    defer { lock.unlock() }

    let text = String(rawText.prefix(SemanticSearchDocument.maximumTextCharacters))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let language = detectedLanguage(for: text)
    guard let embedding = embedding(for: language) else { return nil }

    var sum = Array(repeating: Float.zero, count: embedding.dimension)
    var accepted = 0
    var seen = Set<String>()

    func addToken(_ rawToken: String) {
      guard accepted < Self.maximumTokens else { return }
      let token = SearchMatcher.normalize(rawToken)
      guard token.count >= 2, !token.allSatisfy(\.isNumber), !ignoredTokens.contains(token),
        seen.insert(token).inserted,
        let values = cachedVector(for: token, language: language, embedding: embedding),
        values.count == sum.count
      else { return }
      for index in sum.indices { sum[index] += values[index] }
      accepted += 1
    }

    if language == .english, text.unicodeScalars.allSatisfy({ $0.value < 0x80 }) {
      for token in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
        if accepted >= Self.maximumTokens { break }
        addToken(String(token))
      }
    } else {
      let tokenizer = NLTokenizer(unit: .word)
      tokenizer.string = text
      tokenizer.setLanguage(language)
      for range in tokenizer.tokens(for: text.startIndex..<text.endIndex) {
        if accepted >= Self.maximumTokens { break }
        addToken(String(text[range]))
      }
    }
    guard accepted > 0 else { return nil }
    return SemanticVector(language: language.rawValue, values: sum)
  }

  private func cachedVector(
    for token: String,
    language: NLLanguage,
    embedding: NLEmbedding
  ) -> [Float]? {
    let key = TokenCacheKey(
      language: language.rawValue,
      digest: SHA256.hash(data: Data(token.utf8))
    )
    if let cached = tokenVectors[key] {
      return switch cached {
      case .available(let values): values
      case .missing: nil
      }
    }
    let values = embedding.vector(for: token)?.map(Float.init)
    if tokenVectors.count >= Self.maximumCachedTokens {
      tokenVectors.removeAll(keepingCapacity: true)
    }
    tokenVectors[key] = values.map(CachedTokenVector.available) ?? .missing
    return values
  }

  private func detectedLanguage(for text: String) -> NLLanguage {
    if text.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains(Int($0.value)) }) {
      return .simplifiedChinese
    }
    if text.unicodeScalars.allSatisfy({ $0.value < 0x80 }) { return .english }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    let language = recognizer.dominantLanguage ?? .english
    return NLEmbedding.wordEmbedding(for: language) == nil ? .english : language
  }

  private func embedding(for language: NLLanguage) -> NLEmbedding? {
    if let cached = embeddings[language.rawValue] { return cached }
    guard let embedding = NLEmbedding.wordEmbedding(for: language) else { return nil }
    embeddings[language.rawValue] = embedding
    return embedding
  }
}
