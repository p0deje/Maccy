import Defaults
import Foundation
import Logging
import Observation
import SwiftData

@Observable
final class Todos { // swiftlint:disable:this type_body_length
  static let shared = Todos()

  private let logger = Logger(label: "org.p0deje.Maccy.Todos")

  var items: [TodoItemDecorator] = []
  var searchQuery: String = "" {
    didSet { applySearch() }
  }

  var selectedId: UUID? {
    didSet {
      guard oldValue != selectedId else { return }
      guard AppState.shared.activeTab == .todos else { return }

      let preview = AppState.shared.preview
      if selectedId != nil {
        preview.resetAutoOpenSuppression()
        preview.startAutoOpen()
      } else {
        preview.cancelAutoOpen()
      }
    }
  }

  var showCompletedSection: Bool = false
  var isKeyboardNavigating: Bool = true {
    didSet {
      if !isKeyboardNavigating, let hoverSelectionId {
        self.hoverSelectionId = nil
        selectedId = hoverSelectionId
      }
    }
  }

  var hoverSelectionId: UUID?

  var isSearching: Bool {
    !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Flat list of all visible matches when searching (active, pinned, and completed).
  var searchMatches: [TodoItemDecorator] {
    guard isSearching else { return [] }
    return all
      .filter(\.isVisible)
      .sorted { lhs, rhs in
        if lhs.isCompleted != rhs.isCompleted {
          return !lhs.isCompleted
        }
        if lhs.isPinned != rhs.isPinned {
          return lhs.isPinned
        }
        return lhs.item.updatedAt > rhs.item.updatedAt
      }
  }

  var pinnedItems: [TodoItemDecorator] {
    filteredItems.filter(\.isPinned).filter(\.isVisible).sorted { $0.item.sortOrder < $1.item.sortOrder }
  }

  var activeItems: [TodoItemDecorator] {
    filteredItems.filter { !$0.isPinned && !$0.isCompleted }.filter(\.isVisible)
      .sorted { $0.item.sortOrder < $1.item.sortOrder }
  }

  var completedItems: [TodoItemDecorator] {
    filteredItems.filter(\.isCompleted).filter(\.isVisible)
      .sorted { ($0.item.completedAt ?? .distantPast) > ($1.item.completedAt ?? .distantPast) }
  }

  var selectedItem: TodoItemDecorator? {
    guard let selectedId else { return nil }
    return items.first { $0.id == selectedId }
  }

  fileprivate var all: [TodoItemDecorator] = []

  private init() {}

  @MainActor
  func load() throws {
    showCompletedSection = Defaults[.showCompletedTodos]
    let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.sortOrder)])
    let results = try Storage.shared.context.fetch(descriptor)
    all = results.map { TodoItemDecorator($0) }
    applySearch()
  }

  @MainActor
  @discardableResult
  func add(title: String = "") -> TodoItemDecorator {
    let minOrder = all.map(\.item.sortOrder).min() ?? 0
    let item = TodoItem(title: title, sortOrder: minOrder - 1)
    Storage.shared.context.insert(item)
    save()

    let decorator = TodoItemDecorator(item)
    all.insert(decorator, at: 0)
    applySearch()
    selectedId = decorator.id
    return decorator
  }

  @MainActor
  func update(_ decorator: TodoItemDecorator) {
    decorator.item.updatedAt = .now
    save()
    applySearch()
  }

  @MainActor
  func delete(_ decorator: TodoItemDecorator) {
    ReminderScheduler.shared.cancel(decorator.item)
    if selectedId == decorator.id {
      selectedId = nil
    }
    Storage.shared.context.delete(decorator.item)
    all.removeAll { $0.id == decorator.id }
    save()
    applySearch()
  }

  @MainActor
  func toggleComplete(id: UUID, source: TodoCompletionSource) {
    guard let decorator = all.first(where: { $0.id == id }) else { return }
    toggleComplete(decorator, source: source)
  }

  @MainActor
  func toggleComplete(_ decorator: TodoItemDecorator, source: TodoCompletionSource = .checkbox) {
    if decorator.isCompleted {
      markActive(decorator)
    } else {
      markCompleted(decorator, source: source)
    }
    applySearch()
  }

  @MainActor
  func setReminder(
    _ decorator: TodoItemDecorator,
    date: Date,
    repeatRule: TodoReminderRepeat
  ) {
    let item = decorator.item
    item.reminderDate = date
    item.reminderRepeatRule = repeatRule.rawValue
    item.dueDate = date
    item.updatedAt = .now
    ReminderScheduler.shared.schedule(item)
    save()
  }

  @MainActor
  func applyReminderPreset(_ decorator: TodoItemDecorator, preset: TodoReminderPreset) {
    let resolved = preset.resolve()
    setReminder(decorator, date: resolved.date, repeatRule: resolved.repeat)
  }

  @MainActor
  func clearReminder(_ decorator: TodoItemDecorator) {
    let item = decorator.item
    ReminderScheduler.shared.cancel(item)
    item.reminderDate = nil
    item.reminderRepeatRule = TodoReminderRepeat.none.rawValue
    item.updatedAt = .now
    save()
  }

  @MainActor
  func togglePin(_ decorator: TodoItemDecorator) {
    decorator.isPinned.toggle()
    decorator.item.updatedAt = .now
    save()
    applySearch()
  }

  @MainActor
  func select(_ decorator: TodoItemDecorator?) {
    selectedId = decorator?.id
  }

  @MainActor
  func select(id: UUID) {
    select(all.first { $0.id == id })
  }

  @MainActor
  func selectNext() {
    isKeyboardNavigating = true
    let list = navigableItems
    guard !list.isEmpty else { return }
    guard let selectedId,
          let index = list.firstIndex(where: { $0.id == selectedId }) else {
      select(list.first)
      return
    }
    select(list[(index + 1) % list.count])
  }

  @MainActor
  func selectPrevious() {
    isKeyboardNavigating = true
    let list = navigableItems
    guard !list.isEmpty else { return }
    guard let selectedId,
          let index = list.firstIndex(where: { $0.id == selectedId }) else {
      select(list.last)
      return
    }
    let previous = index == 0 ? list.count - 1 : index - 1
    select(list[previous])
  }

  private var navigableItems: [TodoItemDecorator] {
    pinnedItems + activeItems + (showCompletedSection ? completedItems : [])
  }

  @MainActor
  private func markCompleted(_ decorator: TodoItemDecorator, source: TodoCompletionSource) {
    let now = Date.now
    let item = decorator.item
    let duration = TodoAnalytics.activeDurationSeconds(for: item, at: now)
    let wasOverdue = TodoAnalytics.wasOverdue(item, at: now)

    item.isCompleted = true
    item.completedAt = now
    item.updatedAt = now
    item.completionDurationSeconds = duration
    item.wasOverdueWhenCompleted = wasOverdue
    item.completedVia = source.rawValue
    item.timesCompleted += 1
    item.isPinned = false

    let event = TodoCompletionEvent(
      completedAt: now,
      durationSeconds: duration,
      wasOverdue: wasOverdue,
      dueDateAtEvent: item.dueDate,
      source: source.rawValue
    )
    event.todo = item
    item.completionHistory.append(event)
    Storage.shared.context.insert(event)

    ReminderScheduler.shared.cancel(item)
    item.reminderDate = nil
    item.reminderRepeatRule = TodoReminderRepeat.none.rawValue

    logger.info("Marked todo completed: \(item.title)")
    save()
  }

  @MainActor
  private func markActive(_ decorator: TodoItemDecorator) {
    let now = Date.now
    let item = decorator.item

    if let openEvent = item.completionHistory
      .sorted(by: { $0.completedAt > $1.completedAt })
      .first(where: { $0.reopenedAt == nil }) {
      openEvent.reopenedAt = now
    }

    item.isCompleted = false
    item.completedAt = nil
    item.completionDurationSeconds = nil
    item.wasOverdueWhenCompleted = false
    item.completedVia = nil
    item.updatedAt = now

    logger.info("Marked todo active: \(item.title)")
    save()
  }

  @MainActor
  private func save() {
    do {
      try Storage.shared.context.save()
    } catch {
      logger.error("Failed to save todos: \(error.localizedDescription)")
    }
  }

  private func applySearch() {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if query.isEmpty {
      items = all
      items.forEach { $0.isVisible = true }
      return
    }

    items = all
    for decorator in all {
      let matches = decorator.title.lowercased().contains(query)
        || decorator.notes.lowercased().contains(query)
      decorator.isVisible = matches
    }
  }

  private var filteredItems: [TodoItemDecorator] {
    searchQuery.isEmpty ? all : items
  }
}
