import Foundation

struct NewSnippetDraft: Codable, Equatable, Sendable {
  let text: String
  let title: String
  let alias: String
  let conceal: Bool
  let tags: [String]
  let boardID: UUID?
  let sourceApplication: String?
  let sourceBundleIdentifier: String?
  let richTextData: Data?

  init(
    text: String,
    title: String,
    alias: String,
    conceal: Bool,
    tags: [String],
    boardID: UUID?,
    sourceApplication: String? = nil,
    sourceBundleIdentifier: String? = nil,
    richTextData: Data? = nil
  ) {
    self.text = text
    self.title = title
    self.alias = alias
    self.conceal = conceal
    self.tags = tags
    self.boardID = boardID
    self.sourceApplication = sourceApplication
    self.sourceBundleIdentifier = ClipItem.normalizedSourceBundleIdentifier(
      sourceBundleIdentifier
    )
    self.richTextData = richTextData
  }

  static let empty = NewSnippetDraft(
    text: "",
    title: "",
    alias: "",
    conceal: false,
    tags: [],
    boardID: nil,
    sourceApplication: nil,
    sourceBundleIdentifier: nil,
    richTextData: nil
  )

  var hasContent: Bool {
    !text.isEmpty || !title.isEmpty || !alias.isEmpty || conceal || !tags.isEmpty || boardID != nil
  }
}
