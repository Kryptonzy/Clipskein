import AppKit
import SwiftUI
import Testing

@testable import ClipNest

/// Opt-in, synthetic-only visual QA. This never launches ClipNestApp or its delegate.
/// Run: CLIPSKEIN_RENDER_BRAND_PREVIEWS=1 swift test --filter BrandPreviewTests
/// PNGs are written to the ignored .build/brand-preview directory.
@MainActor
struct BrandPreviewTests {
  @Test(.enabled(
    if: ProcessInfo.processInfo.environment["CLIPSKEIN_RENDER_BRAND_PREVIEWS"] == "1",
    "Set CLIPSKEIN_RENDER_BRAND_PREVIEWS=1 to render synthetic brand previews."
  ))
  func renderSyntheticBrandPreviews() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
      .appendingPathComponent("ClipskeinBrandPreview-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let suite = "ClipskeinBrandPreview.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ClipPreferences(defaults: defaults)
    preferences.completeOnboarding()
    preferences.watchScreenshots = false
    preferences.captureFeedbackSound = false
    let pasteboard = NSPasteboard(name: .init(suite))
    defer { pasteboard.releaseGlobally() }

    // Explicit isolation: no real history, general pasteboard, production key loader,
    // system screenshot folder, global shortcuts, or running-application discovery.
    let store = ClipStore(
      rootURL: root,
      startsMonitoring: false,
      preferences: preferences,
      pasteboard: pasteboard,
      storageProtector: try SecureLocalStorage(keyData: Data(repeating: 0x5A, count: 32)),
      asynchronouslyLoadsStorageProtector: false,
      storageProtectorLoader: { throw SecureLocalStorageError.invalidKey },
      persistsHistoryInBackground: false,
      captureFeedbackPlayer: {},
      semanticSearchIndex: SemanticSearchIndex(vectorizer: { _ in nil })
    )
    #expect(!store.isMonitoring)
    #expect(!store.isUnlockingStorage)
    let board = try #require(store.createBoard(named: "Reference desk"))
    let snippet = store.createSnippet(
      text: "Hello {{name}},\n\nHere are the references for our next conversation.",
      title: "Project follow-up",
      alias: "followup",
      tags: ["writing"],
      boardID: board.id,
      sourceApplication: "Fixture Notes",
      sourceBundleIdentifier: "app.clipskein.fixture"
    )
    #expect(snippet.succeededID != nil)
    store.addText(
      "Research notes\n\nFind useful material. Arrange it in Pinboards. Reuse it with Stack.",
      source: "Fixture Notes",
      sourceBundleIdentifier: "app.clipskein.fixture"
    )
    store.addText(
      "找回资料，组合使用。\n把常用内容整理到 Pinboards，再通过 Stack 按顺序复用。",
      source: "Fixture Notes",
      sourceBundleIdentifier: "app.clipskein.fixture"
    )
    _ = store.addItemsToStack(Array(store.items.prefix(2)))

    let output = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(".build/brand-preview", isDirectory: true)
    try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
    _ = NSApplication.shared

    for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
      try await render(
        WelcomeView(store: store, finish: {}),
        size: CGSize(width: 660, height: 780), scheme: scheme,
        to: output.appendingPathComponent("welcome-\(name).png")
      )
      try await render(
        ContentView(store: store),
        size: CGSize(width: 1200, height: 860), scheme: scheme,
        to: output.appendingPathComponent("workbench-\(name).png")
      )
      try await render(
        brandComponents,
        size: CGSize(width: 660, height: 320), scheme: scheme,
        to: output.appendingPathComponent("components-\(name).png")
      )
    }
    try await render(
      QuickPickerView(store: store, pasteCoordinator: QuickPasteCoordinator()),
      size: CGSize(width: 820, height: 520), scheme: .dark,
      to: output.appendingPathComponent("picker-dark.png")
    )
    print("Synthetic Clipskein previews: \(output.path)")
  }

  private var brandComponents: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(spacing: 18) {
        ClipskeinMark().frame(width: 80, height: 80)
        VStack(alignment: .leading, spacing: 6) {
          Text("Clipskein").font(.system(size: 28, weight: .semibold, design: .rounded))
          Text("Find. Arrange. Reuse.")
          Text("找回资料，组合使用。").foregroundStyle(.secondary)
        }
      }
      HStack(spacing: 18) {
        ForEach([16, 24, 32, 48], id: \.self) { size in
          ClipskeinMark().frame(width: CGFloat(size), height: CGFloat(size))
        }
        Spacer()
        Text("⌃⇧V").font(.system(.body, design: .monospaced))
      }
    }
    .padding(36)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .foregroundStyle(BrandTheme.text)
    .background(BrandTheme.canvas)
  }

  private func render<V: View>(
    _ view: V, size: CGSize, scheme: ColorScheme, to url: URL
  ) async throws {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    let window = NSWindow(
      contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    // The window is never ordered on screen; cache only this synthetic view tree.
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(png.count > 1_000)
    try png.write(to: url, options: .atomic)
  }
}
