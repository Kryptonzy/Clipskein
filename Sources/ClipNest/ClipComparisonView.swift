import AppKit
import SwiftUI

struct ClipComparisonView: View {
  let comparison: ClipTextComparison
  let onClose: () -> Void

  @State private var copied = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      summary
      Divider()
      if comparison.hasChanges {
        diff
      } else {
        identicalState
      }
      Divider()
      footer
    }
    .frame(minWidth: 680, idealWidth: 820, minHeight: 480, idealHeight: 620)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 5) {
        Text(L10n.text("comparison.title", fallback: "Compare Stack Clips"))
          .font(.system(size: 20, weight: .bold, design: .rounded))
        Text(
          L10n.text(
            "comparison.detail",
            fallback: "First in Stack → second in Stack. Original clips stay unchanged."
          )
        )
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: onClose) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 18))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help(L10n.text("comparison.close", fallback: "Close comparison"))
      .accessibilityLabel(L10n.text("comparison.close", fallback: "Close comparison"))
    }
    .padding(22)
  }

  private var summary: some View {
    HStack(spacing: 12) {
      comparisonLabel(
        title: L10n.text("comparison.first", fallback: "FIRST"),
        value: comparison.firstTitle,
        color: .red
      )
      Image(systemName: "arrow.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.secondary)
      comparisonLabel(
        title: L10n.text("comparison.second", fallback: "SECOND"),
        value: comparison.secondTitle,
        color: .green
      )
      Spacer(minLength: 10)
      if comparison.hasChanges {
        Label("+\(comparison.addedLineCount)", systemImage: "plus")
          .foregroundStyle(Color.green)
        Label("−\(comparison.removedLineCount)", systemImage: "minus")
          .foregroundStyle(Color.red)
      } else {
        Label(
          L10n.text("comparison.identical", fallback: "No differences"),
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(Color.green)
      }
    }
    .font(.system(size: 11, weight: .bold, design: .rounded))
    .padding(.horizontal, 22)
    .padding(.vertical, 14)
    .background(Color.primary.opacity(0.025))
  }

  private func comparisonLabel(title: String, value: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 9, weight: .black, design: .monospaced))
        .foregroundStyle(color)
      Text(value)
        .lineLimit(1)
        .help(value)
    }
    .frame(maxWidth: 220, alignment: .leading)
  }

  private var diff: some View {
    ScrollView([.horizontal, .vertical]) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(comparison.lines) { line in
          diffRow(line)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
  }

  @ViewBuilder
  private func diffRow(_ line: ClipDiffLine) -> some View {
    if case .omitted(let count) = line.kind {
      HStack(spacing: 8) {
        Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
        Text(
          L10n.format(
            "comparison.unchanged_lines", fallback: "%d unchanged lines", count
          )
        )
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
      }
      .padding(.horizontal, 16)
      .frame(height: 30)
    } else {
      HStack(alignment: .top, spacing: 0) {
        lineNumber(line.oldLineNumber)
        lineNumber(line.newLineNumber)
        Text(marker(for: line.kind))
          .font(.system(size: 11, weight: .black, design: .monospaced))
          .foregroundStyle(markerColor(for: line.kind))
          .frame(width: 24, alignment: .center)
        Text(line.text.isEmpty ? " " : line.text)
          .font(.system(size: 11, weight: .regular, design: .monospaced))
          .textSelection(.enabled)
          .fixedSize(horizontal: true, vertical: false)
          .padding(.vertical, 5)
        Spacer(minLength: 16)
      }
      .frame(minHeight: 27)
      .background(rowColor(for: line.kind))
    }
  }

  private func lineNumber(_ number: Int?) -> some View {
    Text(number.map(String.init) ?? "")
      .font(.system(size: 9, weight: .medium, design: .monospaced))
      .foregroundStyle(.secondary)
      .frame(width: 42, alignment: .trailing)
      .padding(.trailing, 8)
      .padding(.vertical, 6)
      .background(Color.primary.opacity(0.025))
  }

  private var identicalState: some View {
    VStack(spacing: 12) {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 38))
        .foregroundStyle(Color.green)
      Text(L10n.text("comparison.identical", fallback: "No differences"))
        .font(.system(size: 16, weight: .bold, design: .rounded))
      Text(
        L10n.text(
          "comparison.identical_detail",
          fallback: "The visible text in both Stack clips is identical."
        )
      )
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var footer: some View {
    HStack {
      Text(L10n.text("comparison.local", fallback: "Compared locally on this Mac"))
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      Spacer()
      Button(L10n.text("comparison.close", fallback: "Close"), action: onClose)
        .keyboardShortcut(.cancelAction)
      if comparison.hasChanges {
        Button {
          let pasteboard = NSPasteboard.general
          pasteboard.clearContents()
          copied = pasteboard.setString(comparison.unifiedText, forType: .string)
        } label: {
          Label(
            copied
              ? L10n.text("comparison.copied", fallback: "Copied")
              : L10n.text("comparison.copy", fallback: "Copy changes"),
            systemImage: copied ? "checkmark" : "doc.on.doc"
          )
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(18)
  }

  private func marker(for kind: ClipDiffKind) -> String {
    switch kind {
    case .removed: "−"
    case .added: "+"
    case .unchanged, .omitted: " "
    }
  }

  private func markerColor(for kind: ClipDiffKind) -> Color {
    switch kind {
    case .removed: .red
    case .added: .green
    case .unchanged, .omitted: .secondary
    }
  }

  private func rowColor(for kind: ClipDiffKind) -> Color {
    switch kind {
    case .removed: Color.red.opacity(0.09)
    case .added: Color.green.opacity(0.09)
    case .unchanged, .omitted: Color.clear
    }
  }
}
