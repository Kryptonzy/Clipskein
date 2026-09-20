import Foundation

enum ClipComparisonAvailability: Equatable, Sendable {
  case ready
  case needsExactlyTwo
  case concealed
  case unsupported
  case tooLarge
}

enum ClipDiffKind: Equatable, Sendable {
  case unchanged
  case removed
  case added
  case omitted(Int)
}

struct ClipDiffLine: Identifiable, Equatable, Sendable {
  let id: Int
  let kind: ClipDiffKind
  let oldLineNumber: Int?
  let newLineNumber: Int?
  let text: String
}

struct ClipTextComparison: Identifiable, Equatable, Sendable {
  static let maximumUTF8BytesPerClip = 200_000
  static let maximumLineCountPerClip = 1_000

  let firstID: UUID
  let secondID: UUID
  let firstTitle: String
  let secondTitle: String
  let lines: [ClipDiffLine]
  let addedLineCount: Int
  let removedLineCount: Int

  var id: String { "\(firstID.uuidString)-\(secondID.uuidString)" }
  var hasChanges: Bool { addedLineCount > 0 || removedLineCount > 0 }

  var unifiedText: String {
    var result = "--- \(firstTitle)\n+++ \(secondTitle)\n"
    for line in lines {
      switch line.kind {
      case .unchanged:
        result += "  \(line.text)\n"
      case .removed:
        result += "- \(line.text)\n"
      case .added:
        result += "+ \(line.text)\n"
      case .omitted(let count):
        result += "  … \(count) unchanged lines …\n"
      }
    }
    return result.trimmingCharacters(in: .newlines)
  }

  static func availability(for items: [ClipItem]) -> ClipComparisonAvailability {
    guard items.count == 2 else { return .needsExactlyTwo }
    guard !items.contains(where: \.isConcealed) else { return .concealed }

    let contents = items.map(ClipStackComposer.content)
    guard contents.allSatisfy({ !$0.isEmpty }) else { return .unsupported }
    guard
      contents.allSatisfy({ $0.utf8.count <= maximumUTF8BytesPerClip }),
      contents.allSatisfy({ lineCount($0) <= maximumLineCountPerClip })
    else { return .tooLarge }

    return .ready
  }

  static func comparison(for items: [ClipItem]) -> ClipTextComparison? {
    guard availability(for: items) == .ready else { return nil }
    let contents = items.map(ClipStackComposer.content)
    return compare(
      first: items[0],
      firstText: contents[0],
      second: items[1],
      secondText: contents[1]
    )
  }

  private static func compare(
    first: ClipItem,
    firstText: String,
    second: ClipItem,
    secondText: String
  ) -> ClipTextComparison {
    let oldLines = splitLines(firstText)
    let newLines = splitLines(secondText)
    let difference = newLines.difference(from: oldLines)
    var removals: [Int: String] = [:]
    var insertions: [Int: String] = [:]

    for change in difference {
      switch change {
      case .remove(let offset, let element, _):
        removals[offset] = element
      case .insert(let offset, let element, _):
        insertions[offset] = element
      }
    }

    var rawLines: [ClipDiffLine] = []
    var oldIndex = 0
    var newIndex = 0
    var nextID = 0

    func append(_ kind: ClipDiffKind, oldLine: Int?, newLine: Int?, text: String) {
      rawLines.append(
        ClipDiffLine(
          id: nextID,
          kind: kind,
          oldLineNumber: oldLine,
          newLineNumber: newLine,
          text: text
        )
      )
      nextID += 1
    }

    while oldIndex < oldLines.count || newIndex < newLines.count {
      if let removed = removals[oldIndex] {
        append(.removed, oldLine: oldIndex + 1, newLine: nil, text: removed)
        oldIndex += 1
        continue
      }
      if let inserted = insertions[newIndex] {
        append(.added, oldLine: nil, newLine: newIndex + 1, text: inserted)
        newIndex += 1
        continue
      }
      if oldIndex < oldLines.count, newIndex < newLines.count {
        if oldLines[oldIndex] == newLines[newIndex] {
          append(
            .unchanged,
            oldLine: oldIndex + 1,
            newLine: newIndex + 1,
            text: oldLines[oldIndex]
          )
          oldIndex += 1
          newIndex += 1
        } else {
          append(.removed, oldLine: oldIndex + 1, newLine: nil, text: oldLines[oldIndex])
          append(.added, oldLine: nil, newLine: newIndex + 1, text: newLines[newIndex])
          oldIndex += 1
          newIndex += 1
        }
      } else if oldIndex < oldLines.count {
        append(.removed, oldLine: oldIndex + 1, newLine: nil, text: oldLines[oldIndex])
        oldIndex += 1
      } else if newIndex < newLines.count {
        append(.added, oldLine: nil, newLine: newIndex + 1, text: newLines[newIndex])
        newIndex += 1
      }
    }

    let collapsed = collapseUnchangedRuns(rawLines)
    return ClipTextComparison(
      firstID: first.id,
      secondID: second.id,
      firstTitle: first.localizedDisplayTitle(),
      secondTitle: second.localizedDisplayTitle(),
      lines: collapsed,
      addedLineCount: rawLines.count(where: { $0.kind == .added }),
      removedLineCount: rawLines.count(where: { $0.kind == .removed })
    )
  }

  private static func collapseUnchangedRuns(
    _ lines: [ClipDiffLine],
    contextLineCount: Int = 2,
    collapseThreshold: Int = 7
  ) -> [ClipDiffLine] {
    guard lines.contains(where: { $0.kind != .unchanged }) else { return [] }
    var result: [ClipDiffLine] = []
    var index = 0

    while index < lines.count {
      guard lines[index].kind == .unchanged else {
        result.append(lines[index])
        index += 1
        continue
      }
      let start = index
      while index < lines.count, lines[index].kind == .unchanged { index += 1 }
      let run = Array(lines[start..<index])
      guard run.count >= collapseThreshold else {
        result.append(contentsOf: run)
        continue
      }

      result.append(contentsOf: run.prefix(contextLineCount))
      let omittedCount = run.count - (contextLineCount * 2)
      result.append(
        ClipDiffLine(
          id: -(start + 1),
          kind: .omitted(omittedCount),
          oldLineNumber: nil,
          newLineNumber: nil,
          text: ""
        )
      )
      result.append(contentsOf: run.suffix(contextLineCount))
    }
    return result
  }

  private static func splitLines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  private static func lineCount(_ text: String) -> Int {
    text.reduce(into: 1) { count, character in
      if character == "\n" { count += 1 }
    }
  }
}
