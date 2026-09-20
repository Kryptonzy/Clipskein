import AppKit
import SwiftUI

/// Shared colors for Clipskein's native reference workbench.
/// Keep status colors semantic; plum identifies navigation and reusable material.
enum BrandTheme {
  static let deepPlum = Color(red: 68 / 255, green: 43 / 255, blue: 72 / 255)
  static let plum = Color(red: 112 / 255, green: 70 / 255, blue: 111 / 255)
  static let paper = Color(red: 244 / 255, green: 241 / 255, blue: 246 / 255)
  static let softPlum = Color(red: 212 / 255, green: 173 / 255, blue: 215 / 255)
  static let teal = Color(red: 57 / 255, green: 121 / 255, blue: 107 / 255)
  static let softTeal = Color(red: 164 / 255, green: 208 / 255, blue: 189 / 255)

  static let text = Color(nsColor: .labelColor)
  static let surface = Color(nsColor: .controlBackgroundColor)
  static let action = adaptive(light: (112, 70, 111), dark: (212, 173, 215))
  static let canvas = adaptive(light: (244, 241, 246), dark: (36, 31, 40))

  static let railBackground = deepPlum
  static let accentOnDark = softPlum
  static let popoverBackground = Color(red: 36 / 255, green: 31 / 255, blue: 40 / 255)
  static let selectedText = deepPlum
  static let selectedAccent = deepPlum

  private static func adaptive(
    light: (CGFloat, CGFloat, CGFloat),
    dark: (CGFloat, CGFloat, CGFloat)
  ) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      let values = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      return NSColor(
        srgbRed: values.0 / 255,
        green: values.1 / 255,
        blue: values.2 / 255,
        alpha: 1
      )
    })
  }
}
