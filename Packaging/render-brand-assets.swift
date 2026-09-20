import AppKit
import Foundation

/// Compile with Sources/ClipNest/ClipskeinMark.swift. This executable does not launch the app.
@main
struct RenderBrandAssets {
  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      throw NSError(domain: "ClipskeinArtwork", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Usage: render-brand-assets OUTPUT_DIRECTORY"
      ])
    }
    let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let iconset = destination.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    func writePNG(_ pixels: Int, name: String, directory: URL) throws {
      guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext
      else { throw NSError(domain: "ClipskeinArtwork", code: 2) }
      context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
      context.translateBy(x: 0, y: CGFloat(pixels))
      let scale = CGFloat(pixels) / ClipskeinMarkArtwork.canvasSize
      context.scaleBy(x: scale, y: -scale)
      for tile in ClipskeinMarkArtwork.tiles {
        context.setFillColor(tile.color.cgColor)
        context.addPath(tile.path)
        context.fillPath()
      }
      guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ClipskeinArtwork", code: 3)
      }
      try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    try writePNG(1024, name: "AppIcon-Master.png", directory: destination)
    for points in [16, 32, 128, 256, 512] {
      try writePNG(points, name: "icon_\(points)x\(points).png", directory: iconset)
      try writePNG(points * 2, name: "icon_\(points)x\(points)@2x.png", directory: iconset)
    }
    let rectangles = ClipskeinMarkArtwork.tiles.map { tile in
      "<rect x=\"\(Int(tile.x))\" y=\"\(Int(tile.y))\" width=\"\(Int(tile.width))\" height=\"\(Int(tile.height))\" rx=\"\(Int(tile.radius))\" fill=\"#\(tile.hex)\"/>"
    }.joined(separator: "\n  ")
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title">
      <title id="title">Clipskein — indexed recall</title>
      <!-- Generated from ClipskeinMarkArtwork. Distributed under the repository MIT license. -->
      \(rectangles)
    </svg>

    """
    try svg.write(to: destination.appendingPathComponent("AppIcon.svg"), atomically: true, encoding: .utf8)
    print(destination.path)
  }
}
