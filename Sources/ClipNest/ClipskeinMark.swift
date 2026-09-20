import AppKit
import SwiftUI

/// The same authored geometry draws the in-app mark and the exported icon assets.
/// Coordinates use a 1,024-point, top-left-origin canvas. No reference image is used.
enum ClipskeinMarkArtwork {
  struct Tile {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let hex: String

    var path: CGPath {
      CGPath(
        roundedRect: CGRect(x: x, y: y, width: width, height: height),
        cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    var color: NSColor {
      let value = UInt32(hex, radix: 16)!
      return NSColor(
        srgbRed: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255,
        blue: CGFloat(value & 255) / 255, alpha: 1)
    }
  }

  static let canvasSize: CGFloat = 1024
  static let tiles = [
    Tile(x: 64, y: 64, width: 896, height: 896, radius: 208, hex: "70466F"),
    Tile(x: 274, y: 276, width: 476, height: 96, radius: 20, hex: "F7F1F8"),
    Tile(x: 274, y: 464, width: 286, height: 96, radius: 20, hex: "F7F1F8"),
    Tile(x: 274, y: 652, width: 476, height: 96, radius: 20, hex: "F7F1F8"),
    Tile(x: 654, y: 464, width: 96, height: 284, radius: 20, hex: "A4D0BD"),
  ]
}

struct ClipskeinMark: View {
  var body: some View {
    Canvas { context, size in
      let transform = CGAffineTransform(
        scaleX: size.width / ClipskeinMarkArtwork.canvasSize,
        y: size.height / ClipskeinMarkArtwork.canvasSize)
      for tile in ClipskeinMarkArtwork.tiles {
        context.fill(Path(tile.path).applying(transform), with: .color(Color(nsColor: tile.color)))
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityLabel("Clipskein")
  }
}
