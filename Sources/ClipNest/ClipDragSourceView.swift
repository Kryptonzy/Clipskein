import AppKit
import SwiftUI

enum ClipDragAvailability: Equatable, Sendable {
  case ready(itemCount: Int)
  case checkingReference
  case preparingImage
  case concealed
  case missingReference
  case imageUnavailable
  case unavailable

  var isEnabled: Bool {
    if case .ready = self { return true }
    return false
  }

  var helpText: String {
    switch self {
    case .ready(let itemCount):
      itemCount == 1
        ? L10n.text("drag.ready_clip", fallback: "Drag this clip into another app")
        : L10n.format(
          "drag.ready_files", fallback: "Drag all %d files into another app", itemCount)
    case .checkingReference:
      L10n.text(
        "drag.checking_reference",
        fallback: "Checking whether the referenced files are available")
    case .preparingImage:
      L10n.text(
        "drag.preparing_image",
        fallback: "Preparing the full-resolution image for drag and drop")
    case .concealed:
      L10n.text(
        "drag.concealed", fallback: "Concealed clips use secure copy instead of drag and drop")
    case .missingReference:
      L10n.text(
        "drag.missing_reference",
        fallback: "A referenced file is missing, so this group cannot be dragged")
    case .imageUnavailable:
      L10n.text(
        "drag.image_unavailable",
        fallback: "The stored image is unavailable and cannot be dragged")
    case .unavailable:
      L10n.text("drag.unavailable", fallback: "This clip is not available for drag and drop")
    }
  }

  var systemImage: String {
    switch self {
    case .ready: "hand.draw"
    case .checkingReference, .preparingImage: "ellipsis.circle"
    case .concealed: "lock.fill"
    case .missingReference: "exclamationmark.triangle.fill"
    case .imageUnavailable: "photo.badge.exclamationmark"
    case .unavailable: "nosign"
    }
  }
}

struct ClipDragSourceView: NSViewRepresentable {
  let availability: ClipDragAvailability
  let makePasteboardWriters: () -> [NSPasteboardWriting]
  let makePreviewImage: () -> NSImage
  let onCompleted: () -> Void

  func makeNSView(context: Context) -> ClipDragSourceNSView {
    let view = ClipDragSourceNSView()
    update(view)
    return view
  }

  func updateNSView(_ nsView: ClipDragSourceNSView, context: Context) {
    update(nsView)
  }

  private func update(_ view: ClipDragSourceNSView) {
    view.availability = availability
    view.makePasteboardWriters = makePasteboardWriters
    view.makePreviewImage = makePreviewImage
    view.onCompleted = onCompleted
  }
}

@MainActor
final class ClipDragSourceNSView: NSView, NSDraggingSource {
  var availability: ClipDragAvailability = .unavailable {
    didSet {
      toolTip = availability.helpText
      setAccessibilityEnabled(availability.isEnabled)
      setAccessibilityHelp(availability.helpText)
      needsDisplay = true
    }
  }
  var makePasteboardWriters: () -> [NSPasteboardWriting] = { [] }
  var makePreviewImage: () -> NSImage = { NSImage() }
  var onCompleted: () -> Void = {}

  private var isHovering = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(L10n.text("drag.accessibility", fallback: "Drag clip to another app"))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.activeInKeyWindow, .mouseEnteredAndExited],
        owner: self
      )
    )
  }

  override func mouseEntered(with event: NSEvent) {
    isHovering = true
    if availability.isEnabled { NSCursor.openHand.push() }
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    if availability.isEnabled { NSCursor.pop() }
    isHovering = false
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    guard availability.isEnabled else {
      NSSound.beep()
      return
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard availability.isEnabled else { return }
    let writers = makePasteboardWriters()
    guard !writers.isEmpty else {
      NSSound.beep()
      return
    }

    let preview = makePreviewImage()
    let previewSize = preview.size.width > 0 ? preview.size : NSSize(width: 44, height: 44)
    let origin = convert(event.locationInWindow, from: nil)
    let frame = NSRect(
      x: origin.x - previewSize.width / 2,
      y: origin.y - previewSize.height / 2,
      width: previewSize.width,
      height: previewSize.height
    )
    let draggingItems = writers.map { writer -> NSDraggingItem in
      let item = NSDraggingItem(pasteboardWriter: writer)
      item.setDraggingFrame(frame, contents: preview)
      return item
    }
    let session = beginDraggingSession(with: draggingItems, event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if isHovering {
      NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
    let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
    let image = NSImage(systemSymbolName: availability.systemImage, accessibilityDescription: nil)?
      .withSymbolConfiguration(configuration)
    image?.isTemplate = true
    let imageSize = image?.size ?? NSSize(width: 12, height: 12)
    let imageRect = NSRect(
      x: bounds.midX - imageSize.width / 2,
      y: bounds.midY - imageSize.height / 2,
      width: imageSize.width,
      height: imageSize.height
    )
    (availability.isEnabled ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).set()
    image?.draw(in: imageRect)
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .copy
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    guard operation != [] else { return }
    onCompleted()
  }
}
