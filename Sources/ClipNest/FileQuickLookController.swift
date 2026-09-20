import AppKit
import QuickLookUI

@MainActor
final class FileQuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource {
  static let shared = FileQuickLookController()

  private var urls: [URL] = []

  @discardableResult
  func preview(_ urls: [URL], startingAt index: Int = 0) -> Bool {
    guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return false }
    self.urls = urls
    panel.dataSource = self
    panel.reloadData()
    panel.currentPreviewItemIndex = min(max(0, index), urls.count - 1)
    panel.makeKeyAndOrderFront(nil)
    return true
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    urls.count
  }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
    urls[index] as NSURL
  }
}
