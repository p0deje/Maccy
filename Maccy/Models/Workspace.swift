import Foundation
import SwiftData

@Model
class Workspace {
  static let defaultName = "Default"

  var id: UUID
  var name: String = Workspace.defaultName
  var createdAt: Date
  var sortOrder: Int = 0

  @Relationship(deleteRule: .nullify)
  var items: [HistoryItem] = []

  init(name: String, sortOrder: Int = 0) {
    self.id = UUID()
    self.name = name
    self.sortOrder = sortOrder
    self.createdAt = Date.now
  }
}
