import NaturalLanguage
import Testing

@testable import ClipNest

enum SystemEmbeddingTestResources {
  // Apple documents that wordEmbedding(for:) returns nil when unavailable:
  // https://developer.apple.com/documentation/naturallanguage/nlembedding/wordembedding(for:)
  // Check the system resource, not the product's output, so a vectorizer regression
  // still fails every integration assertion when the corresponding model is present.
  static var englishWordEmbeddingAvailable: Bool {
    NLEmbedding.wordEmbedding(for: .english) != nil
  }

  static var simplifiedChineseWordEmbeddingAvailable: Bool {
    NLEmbedding.wordEmbedding(for: .simplifiedChinese) != nil
  }
}

struct SemanticModelAvailabilityTests {
  @Test(arguments: ["invoice amount", "编译失败"])
  func missingSystemLanguageModelReportsUnavailableWithoutIndexing(_ query: String) async throws {
    let index = SemanticSearchIndex(vectorizer: { _ in nil })
    let request = try #require(SemanticSearchRequest("~ \(query)"))
    let result = await index.search(
      request: request,
      documents: [SemanticSearchDocument(text: "invoice amount 构建错误需要修复")]
    )

    #expect(result.availability == .modelUnavailable)
    #expect(result.hits.isEmpty)
    #expect(result.indexedDocumentCount == 0)
    #expect(await index.cachedDocumentCount == 0)
  }
}
