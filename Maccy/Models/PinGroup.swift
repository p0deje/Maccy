import Foundation
import SwiftData

@Model
class PinGroup {
  var name: String
  var sortOrder: Int = 0
  var createdAt: Date = Date.now

  @Relationship(deleteRule: .nullify, inverse: \HistoryItem.pinGroup)
  var items: [HistoryItem] = []

  init(name: String, sortOrder: Int = 0) {
    self.name = name
    self.sortOrder = sortOrder
    self.createdAt = Date.now
  }
}
