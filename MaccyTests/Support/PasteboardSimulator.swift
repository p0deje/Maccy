import AppKit
import Foundation

struct PasteboardSimulator: Sendable {
  private(set) var changeCount: Int
  private(set) var items: [PasteboardItemSnapshot]

  init(changeCount: Int = 0, items: [PasteboardItemSnapshot] = []) {
    self.changeCount = changeCount
    self.items = items
  }

  mutating func copy(_ items: [PasteboardItemSnapshot]) {
    changeCount += 1
    self.items = items
  }

  mutating func clear() {
    changeCount += 1
    items = []
  }
}

struct PasteboardItemSnapshot: Sendable {
  let contents: [String: Data]

  init(contents: [String: Data]) {
    self.contents = contents
  }

  var types: Set<NSPasteboard.PasteboardType> {
    Set(contents.keys.map(NSPasteboard.PasteboardType.init(_:)))
  }

  func data(for type: NSPasteboard.PasteboardType) -> Data? {
    contents[type.rawValue]
  }
}
