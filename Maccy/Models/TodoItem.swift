import Foundation
import SwiftData

@Model
final class TodoItem {
  var id: UUID
  var title: String
  var notes: String
  var isCompleted: Bool
  var isPinned: Bool
  var createdAt: Date
  var updatedAt: Date
  var sortOrder: Int

  var completedAt: Date?
  var completionDurationSeconds: Int?
  var wasOverdueWhenCompleted: Bool
  var completedVia: String?
  var timesCompleted: Int

  var dueDate: Date?
  var reminderDate: Date?
  var reminderRepeatRule: String?
  var notificationId: String?

  var listId: UUID?
  var priorityRaw: Int = 0
  var rolledOverAt: Date?

  @Relationship(deleteRule: .cascade, inverse: \TodoCompletionEvent.todo)
  var completionHistory: [TodoCompletionEvent] = []

  init(
    id: UUID = UUID(),
    title: String = "",
    notes: String = "",
    isCompleted: Bool = false,
    isPinned: Bool = false,
    createdAt: Date = .now,
    updatedAt: Date = .now,
    sortOrder: Int = 0,
    listId: UUID? = nil,
    priorityRaw: Int = 0
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.isPinned = isPinned
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.sortOrder = sortOrder
    self.listId = listId
    self.priorityRaw = priorityRaw
    self.wasOverdueWhenCompleted = false
    self.timesCompleted = 0
  }
}

extension TodoItem {
  var priority: TodoPriority {
    get { TodoPriority(rawValue: priorityRaw) ?? .none }
    set { priorityRaw = newValue.rawValue }
  }
}
