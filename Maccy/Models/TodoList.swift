import Foundation
import SwiftData

@Model
final class TodoList {
  var id: UUID
  var name: String
  var sortOrder: Int
  var createdAt: Date
  var isInbox: Bool

  init(
    id: UUID = UUID(),
    name: String,
    sortOrder: Int = 0,
    createdAt: Date = .now,
    isInbox: Bool = false
  ) {
    self.id = id
    self.name = name
    self.sortOrder = sortOrder
    self.createdAt = createdAt
    self.isInbox = isInbox
  }
}

enum TodoListFilter: Hashable {
  case today
  case upcoming
  case all
  case list(UUID)
}
