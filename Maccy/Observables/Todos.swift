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
  var lists: [TodoList] = []
  var selectedListFilter: TodoListFilter = .today
  var scrollTarget: UUID?
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

  var inboxList: TodoList? {
    lists.first(where: \.isInbox)
  }

  /// Flat list of all visible matches when searching (active, pinned, and completed).
  var searchMatches: [TodoItemDecorator] {
    guard isSearching else { return [] }
    return all
      .filter(\.isVisible)
      .filter(matchesCurrentFilter)
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
    filteredItems
      .filter(\.isPinned)
      .filter(\.isVisible)
      .filter(matchesCurrentFilter)
      .sorted { $0.item.sortOrder < $1.item.sortOrder }
  }

  var activeItems: [TodoItemDecorator] {
    filteredItems
      .filter { !$0.isPinned && !$0.isCompleted }
      .filter(\.isVisible)
      .filter(matchesCurrentFilter)
      .sorted { lhs, rhs in
        if lhs.item.priorityRaw != rhs.item.priorityRaw {
          return lhs.item.priorityRaw > rhs.item.priorityRaw
        }
        return lhs.item.sortOrder < rhs.item.sortOrder
      }
  }

  var completedItems: [TodoItemDecorator] {
    filteredItems
      .filter(\.isCompleted)
      .filter(\.isVisible)
      .filter(matchesCurrentFilter)
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
    ensureInboxExists()
    reloadLists()

    let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.sortOrder)])
    let results = try Storage.shared.context.fetch(descriptor)
    all = results.map { TodoItemDecorator($0) }
    performDayRolloverIfNeeded()
    applySearch()
  }

  @MainActor
  @discardableResult
  func add(title: String = "") -> TodoItemDecorator {
    let minOrder = all.map(\.item.sortOrder).min() ?? 0
    let listId = listIdForNewTodo()
    let item = TodoItem(title: title, sortOrder: minOrder - 1, listId: listId)
    Storage.shared.context.insert(item)
    save()

    let decorator = TodoItemDecorator(item)
    all.insert(decorator, at: 0)
    applySearch()
    select(decorator)
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
      scrollTarget = nil
    }
    Storage.shared.context.delete(decorator.item)
    all.removeAll { $0.id == decorator.id }
    save()
    applySearch()
  }

  @MainActor
  @discardableResult
  func addList(name: String) -> TodoList? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let maxOrder = lists.map(\.sortOrder).max() ?? 0
    let list = TodoList(name: trimmed, sortOrder: maxOrder + 1, isInbox: false)
    Storage.shared.context.insert(list)
    save()
    reloadLists()
    selectedListFilter = .list(list.id)
    return list
  }

  @MainActor
  func renameList(_ list: TodoList, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    list.name = trimmed
    save()
    reloadLists()
  }

  @MainActor
  func deleteList(_ list: TodoList) {
    guard !list.isInbox else { return }

    let inboxId = inboxList?.id
    for decorator in all where decorator.item.listId == list.id {
      decorator.item.listId = inboxId
      decorator.item.updatedAt = .now
    }

    if case .list(let selectedId) = selectedListFilter, selectedId == list.id {
      selectedListFilter = .today
    }

    Storage.shared.context.delete(list)
    save()
    reloadLists()
    applySearch()
  }

  @MainActor
  func setPriority(_ decorator: TodoItemDecorator, _ priority: TodoPriority) {
    decorator.priority = priority
    decorator.item.updatedAt = .now
    save()
    applySearch()
  }

  @MainActor
  func moveToList(_ decorator: TodoItemDecorator, list: TodoList) {
    decorator.item.listId = list.id
    decorator.item.updatedAt = .now
    save()
    applySearch()
  }

  @MainActor
  func performDayRolloverIfNeeded() {
    let todayKey = Self.dayKey(for: .now)
    guard Defaults[.lastTodoRolloverDay] != todayKey else { return }

    let startOfToday = Calendar.current.startOfDay(for: .now)
    let now = Date.now
    var targets = all.map(\.item)
    if targets.isEmpty {
      let descriptor = FetchDescriptor<TodoItem>()
      targets = (try? Storage.shared.context.fetch(descriptor)) ?? []
    }

    var changed = false
    for item in targets where !item.isCompleted {
      guard let dueDate = item.dueDate, dueDate < startOfToday else { continue }

      item.dueDate = startOfToday
      item.rolledOverAt = now
      if item.priorityRaw < TodoPriority.medium.rawValue {
        item.priorityRaw = max(item.priorityRaw, TodoPriority.medium.rawValue)
      }
      item.updatedAt = now
      changed = true
    }

    Defaults[.lastTodoRolloverDay] = todayKey
    if changed {
      save()
      applySearch()
    }
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
    item.reminderRepeatRule = nil
    item.dueDate = nil
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
    scrollTarget = decorator?.id
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

  func listName(for item: TodoItem) -> String? {
    let resolvedId = item.listId ?? inboxList?.id
    guard let resolvedId else { return nil }
    return lists.first { $0.id == resolvedId }?.name
  }

  private var navigableItems: [TodoItemDecorator] {
    var list = pinnedItems + activeItems
    if Defaults[.showCompletedTodos], showCompletedSection {
      list += completedItems
    }
    return list
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
    item.reminderRepeatRule = nil

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
  private func ensureInboxExists() {
    let descriptor = FetchDescriptor<TodoList>(
      predicate: #Predicate { $0.isInbox == true }
    )
    guard (try? Storage.shared.context.fetch(descriptor).first) == nil else { return }

    let inbox = TodoList(
      name: NSLocalizedString("InboxList", tableName: "Todos", comment: ""),
      sortOrder: 0,
      isInbox: true
    )
    Storage.shared.context.insert(inbox)
    save()
  }

  @MainActor
  private func reloadLists() {
    let descriptor = FetchDescriptor<TodoList>(sortBy: [SortDescriptor(\.sortOrder)])
    lists = (try? Storage.shared.context.fetch(descriptor)) ?? []
  }

  private func listIdForNewTodo() -> UUID? {
    switch selectedListFilter {
    case .list(let id):
      return id
    case .today, .upcoming, .all:
      return inboxList?.id
    }
  }

  private func matchesCurrentFilter(_ decorator: TodoItemDecorator) -> Bool {
    switch selectedListFilter {
    case .all:
      return true
    case .list(let id):
      return belongs(to: id, item: decorator.item)
    case .today:
      guard !decorator.isCompleted else { return false }
      return isTodayItem(decorator.item)
    case .upcoming:
      guard !decorator.isCompleted else { return false }
      guard let dueDate = decorator.item.dueDate else { return false }
      return dueDate > endOfToday
    }
  }

  private func belongs(to listId: UUID, item: TodoItem) -> Bool {
    if let itemListId = item.listId {
      return itemListId == listId
    }
    return listId == inboxList?.id
  }

  private func isTodayItem(_ item: TodoItem) -> Bool {
    guard let dueDate = item.dueDate else { return true }
    return dueDate < endOfToday || Calendar.current.isDateInToday(dueDate)
  }

  private var endOfToday: Date {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: .now)
    return calendar.date(byAdding: .day, value: 1, to: start) ?? .now
  }

  private static func dayKey(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
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
