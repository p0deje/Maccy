import AppKit
import Foundation
@testable import Maccy

struct PasteboardSimulator: PasteboardSource {
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

  func snapshot() -> [PasteboardItemSnapshot] { items }
}
