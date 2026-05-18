import Foundation
import Observation

@Observable
final class TodoItemDecorator: Identifiable, Hashable {
  let id: UUID
  var item: TodoItem

  var title: String {
    get { item.title }
    set { item.title = newValue }
  }

  var notes: String {
    get { item.notes }
    set { item.notes = newValue }
  }

  var isCompleted: Bool {
    get { item.isCompleted }
    set { item.isCompleted = newValue }
  }

  var isPinned: Bool {
    get { item.isPinned }
    set { item.isPinned = newValue }
  }

  var isVisible: Bool = true
  var selectionIndex: Int = -1
  var isSelected: Bool { selectionIndex != -1 }

  init(_ item: TodoItem) {
    self.id = item.id
    self.item = item
  }

  static func == (lhs: TodoItemDecorator, rhs: TodoItemDecorator) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}
