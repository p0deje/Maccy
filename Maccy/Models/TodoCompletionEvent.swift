import Foundation
import SwiftData

@Model
final class TodoCompletionEvent {
  var completedAt: Date
  var reopenedAt: Date?
  var durationSeconds: Int
  var wasOverdue: Bool
  var dueDateAtEvent: Date?
  var source: String

  @Relationship
  var todo: TodoItem?

  init(
    completedAt: Date = .now,
    reopenedAt: Date? = nil,
    durationSeconds: Int = 0,
    wasOverdue: Bool = false,
    dueDateAtEvent: Date? = nil,
    source: String = "checkbox"
  ) {
    self.completedAt = completedAt
    self.reopenedAt = reopenedAt
    self.durationSeconds = durationSeconds
    self.wasOverdue = wasOverdue
    self.dueDateAtEvent = dueDateAtEvent
    self.source = source
  }
}
