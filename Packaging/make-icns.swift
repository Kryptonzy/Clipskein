#!/usr/bin/swift
import Foundation

struct IconEntry {
  let type: String
  let fileName: String
}

let entries = [
  IconEntry(type: "icp4", fileName: "icon_16x16.png"),
  IconEntry(type: "ic11", fileName: "icon_16x16@2x.png"),
  IconEntry(type: "icp5", fileName: "icon_32x32.png"),
  IconEntry(type: "ic12", fileName: "icon_32x32@2x.png"),
  IconEntry(type: "ic07", fileName: "icon_128x128.png"),
  IconEntry(type: "ic13", fileName: "icon_128x128@2x.png"),
  IconEntry(type: "ic08", fileName: "icon_256x256.png"),
  IconEntry(type: "ic14", fileName: "icon_256x256@2x.png"),
  IconEntry(type: "ic09", fileName: "icon_512x512.png"),
  IconEntry(type: "ic10", fileName: "icon_512x512@2x.png"),
]

func fourByteType(_ value: String) throws -> Data {
  let data = Data(value.utf8)
  guard data.count == 4 else {
    throw NSError(domain: "ClipNestICNS", code: 1, userInfo: [
      NSLocalizedDescriptionKey: "ICNS entry type must be four bytes: \(value)"
    ])
  }
  return data
}

func bigEndianSize(_ value: Int) throws -> Data {
  guard value <= Int(UInt32.max) else {
    throw NSError(domain: "ClipNestICNS", code: 2, userInfo: [
      NSLocalizedDescriptionKey: "ICNS output is too large"
    ])
  }
  var size = UInt32(value).bigEndian
  return Data(bytes: &size, count: MemoryLayout<UInt32>.size)
}

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(Data("Usage: make-icns.swift ICONSET_DIR OUTPUT.icns\n".utf8))
  exit(64)
}

do {
  let inputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
  let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
  var body = Data()

  for entry in entries {
    let imageURL = inputURL.appendingPathComponent(entry.fileName)
    let image = try Data(contentsOf: imageURL)
    guard image.starts(with: [0x89, 0x50, 0x4E, 0x47]) else {
      throw NSError(domain: "ClipNestICNS", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "Expected PNG data at \(imageURL.path)"
      ])
    }
    body.append(try fourByteType(entry.type))
    body.append(try bigEndianSize(image.count + 8))
    body.append(image)
  }

  var archive = try fourByteType("icns")
  archive.append(try bigEndianSize(body.count + 8))
  archive.append(body)
  try archive.write(to: outputURL, options: .atomic)
  print(outputURL.path)
} catch {
  FileHandle.standardError.write(Data("make-icns: \(error.localizedDescription)\n".utf8))
  exit(1)
}
