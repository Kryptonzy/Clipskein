import Foundation
import Testing

@testable import ClipNest

struct LocalizationTests {
  @Test(arguments: ["zh-hans", "zh-Hans", "zh_Hans"])
  func resourceDirectoryCasingDoesNotChangeLanguageIdentityOrChineseLookup(
    resourceLanguage: String
  ) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ClipNestLocalization-\(UUID().uuidString).bundle", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let resources = directory.appendingPathComponent("Contents/Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let info = try PropertyListSerialization.data(
      fromPropertyList: [
        "CFBundleIdentifier": "app.clipnest.localization-test.\(UUID().uuidString)",
        "CFBundleDevelopmentRegion": "en",
        "CFBundleLocalizations": ["en", resourceLanguage],
      ],
      format: .xml,
      options: 0
    )
    try info.write(to: directory.appendingPathComponent("Contents/Info.plist"))
    for (language, greeting) in [("en", "Hello"), (resourceLanguage, "你好")] {
      let localization = resources.appendingPathComponent("\(language).lproj", isDirectory: true)
      try FileManager.default.createDirectory(at: localization, withIntermediateDirectories: true)
      try Data("\"fixture.greeting\" = \"\(greeting)\";\n".utf8)
        .write(to: localization.appendingPathComponent("Localizable.strings"))
    }
    let bundle = try #require(Bundle(url: directory))

    #expect(L10n.availableLanguages(in: bundle) == ["en", "zh-Hans"])
    for language in ["zh-Hans", "zh-hans", "ZH_hANS", "zh-Hans-CN", "zh"] {
      #expect(
        L10n.text(
          "fixture.greeting", fallback: "Missing", language: language, resourceBundle: bundle
        ) == "你好"
      )
    }
    #expect(
      L10n.text(
        "fixture.greeting", fallback: "Missing", language: "en-US", resourceBundle: bundle
      ) == "Hello"
    )
    #expect(
      L10n.text(
        "fixture.missing", fallback: "Fallback", language: "zh-Hans", resourceBundle: bundle
      ) == "Fallback"
    )
  }
}
