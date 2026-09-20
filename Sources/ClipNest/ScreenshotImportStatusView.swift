import SwiftUI

struct ScreenshotImportStatusView: View {
  @ObservedObject var store: ClipStore
  var accentColor: Color = .accentColor

  var body: some View {
    if let progress = store.imageImportProgress {
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 8) {
          Label(
            progress.isCancelling
              ? L10n.text("screenshot_import.stopping", fallback: "Stopping import…")
              : L10n.text("screenshot_import.running", fallback: "Importing screenshots"),
            systemImage: progress.isCancelling ? "stop.circle" : "photo.stack.fill"
          )
          .font(.system(size: 11, weight: .bold))
          Spacer()
          Text(
            L10n.format(
              "screenshot_import.progress",
              fallback: "%d of %d",
              progress.completed,
              progress.total
            )
          )
          .font(.system(size: 10, weight: .bold, design: .monospaced))
          .foregroundStyle(.secondary)
        }

        ProgressView(
          value: Double(progress.completed),
          total: Double(max(progress.total, 1))
        )
        .tint(accentColor)

        HStack {
          Text(
            L10n.format(
              "screenshot_import.progress_detail",
              fallback: "%d added · %d duplicates · %d unreadable · %d failed",
              progress.imported,
              progress.duplicates,
              progress.unreadable,
              progress.failed
            )
          )
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
          Spacer()
          Button(
            L10n.text("screenshot_import.stop", fallback: "Stop"),
            role: .destructive
          ) {
            store.cancelImageImport()
          }
          .buttonStyle(.plain)
          .font(.system(size: 10, weight: .bold))
          .disabled(progress.isCancelling)
        }
      }
      .padding(10)
      .background(accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    } else if let result = store.lastImageImportResult {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .top, spacing: 7) {
          Image(systemName: result.systemImage)
            .foregroundStyle(accentColor)
          Text(result.message)
            .font(.system(size: 10, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 4)
          Button {
            store.dismissImageImportResult()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            L10n.text("main.import.dismiss_result", fallback: "Dismiss import result")
          )
        }

        if store.recoverableImageImportCount > 0 {
          Button {
            store.retryLastImageImport()
          } label: {
            Label(
              L10n.format(
                result.wasCancelled
                  ? "screenshot_import.resume"
                  : "screenshot_import.retry",
                fallback: result.wasCancelled ? "Resume %d files" : "Retry %d files",
                store.recoverableImageImportCount
              ),
              systemImage: "arrow.clockwise"
            )
          }
          .buttonStyle(.plain)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(accentColor)
        }
      }
      .padding(10)
      .background(accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }
  }
}
