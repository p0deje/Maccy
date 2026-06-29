import AppKit
import Foundation
import XCTest

enum FixtureLoader {
  static var fixturesURL: URL {
    URL(filePath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Fixtures")
  }

  static var heavyTextURL: URL {
    fixturesURL.appending(path: "heavy_text.txt")
  }

  static func data(named name: String) throws -> Data {
    try Data(contentsOf: fixturesURL.appending(path: name))
  }

  static func imageData(size: NSSize = NSSize(width: 40, height: 40)) throws -> Data {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return try XCTUnwrap(image.tiffRepresentation)
  }
}
