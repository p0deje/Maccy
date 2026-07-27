import Defaults
import SwiftData
import XCTest
@testable import Maccy

@MainActor
final class TodosTests: XCTestCase {
  private let todos = Todos.shared
  private var created: [TodoItemDecorator] = []
  private var createdLists: [TodoList] = []
  private var savedRolloverDay = ""
  private var savedListFilter: TodoListFilter = .today

  override func setUp() {
    super.setUp()
    created = []
    createdLists = []
    todos.searchQuery = ""
    savedRolloverDay = Defaults[.lastTodoRolloverDay]
    savedListFilter = todos.selectedListFilter
  }

  override func tearDown() {
    todos.searchQuery = ""
    todos.selectedListFilter = savedListFilter
    Defaults[.lastTodoRolloverDay] = savedRolloverDay
    for decorator in created {
      todos.delete(decorator)
    }
    created = []
    for list in createdLists where !list.isInbox {
      todos.deleteList(list)
    }
    createdLists = []
    super.tearDown()
  }

  func testAddPlacesAtTop() {
    let first = track(todos.add(title: "first"))
    let second = track(todos.add(title: "second"))

    XCTAssertEqual(todos.items.first?.id, second.id)
    XCTAssertTrue(todos.items.contains(where: { $0.id == first.id }))
    XCTAssertLessThan(second.item.sortOrder, first.item.sortOrder)
  }

  func testToggleCompleteSetsAnalyticsFields() {
    let decorator = track(todos.add(title: "complete me"))
    let pastDue = Date.now.addingTimeInterval(-3_600)
    decorator.item.dueDate = pastDue
    todos.update(decorator)

    todos.toggleComplete(decorator, source: .keyboard)

    XCTAssertTrue(decorator.isCompleted)
    XCTAssertNotNil(decorator.item.completedAt)
    XCTAssertNotNil(decorator.item.completionDurationSeconds)
    XCTAssertTrue(decorator.item.wasOverdueWhenCompleted)
    XCTAssertEqual(decorator.item.completedVia, TodoCompletionSource.keyboard.rawValue)
    XCTAssertEqual(decorator.item.timesCompleted, 1)
    XCTAssertFalse(decorator.isPinned)
    XCTAssertEqual(decorator.item.completionHistory.count, 1)
    XCTAssertEqual(decorator.item.completionHistory.first?.source, TodoCompletionSource.keyboard.rawValue)
    XCTAssertTrue(decorator.item.completionHistory.first?.wasOverdue ?? false)
  }

  func testToggleCompleteThenReopen() {
    let decorator = track(todos.add(title: "reopen me"))
    todos.toggleComplete(decorator, source: .checkbox)

    XCTAssertTrue(decorator.isCompleted)
    XCTAssertEqual(decorator.item.timesCompleted, 1)

    todos.toggleComplete(decorator, source: .checkbox)

    XCTAssertFalse(decorator.isCompleted)
    XCTAssertNil(decorator.item.completedAt)
    XCTAssertNil(decorator.item.completionDurationSeconds)
    XCTAssertFalse(decorator.item.wasOverdueWhenCompleted)
    XCTAssertNil(decorator.item.completedVia)
    XCTAssertEqual(decorator.item.timesCompleted, 1)
    XCTAssertNotNil(decorator.item.completionHistory.first?.reopenedAt)
  }

  func testTogglePin() {
    let decorator = track(todos.add(title: "pin me"))
    XCTAssertFalse(decorator.isPinned)

    todos.togglePin(decorator)
    XCTAssertTrue(decorator.isPinned)
    XCTAssertTrue(todos.pinnedItems.contains(where: { $0.id == decorator.id }))

    todos.togglePin(decorator)
    XCTAssertFalse(decorator.isPinned)
    XCTAssertFalse(todos.pinnedItems.contains(where: { $0.id == decorator.id }))
  }

  func testSearchFiltersTitleAndNotes() {
    let titleMatch = track(todos.add(title: "alpha unique-title"))
    let notesMatch = track(todos.add(title: "other"))
    notesMatch.notes = "contains unique-notes"
    todos.update(notesMatch)
    let noMatch = track(todos.add(title: "gamma"))

    todos.searchQuery = "unique-title"
    XCTAssertTrue(titleMatch.isVisible)
    XCTAssertFalse(notesMatch.isVisible)
    XCTAssertFalse(noMatch.isVisible)

    todos.searchQuery = "unique-notes"
    XCTAssertFalse(titleMatch.isVisible)
    XCTAssertTrue(notesMatch.isVisible)
    XCTAssertFalse(noMatch.isVisible)

    todos.searchQuery = ""
    XCTAssertTrue(titleMatch.isVisible)
    XCTAssertTrue(notesMatch.isVisible)
    XCTAssertTrue(noMatch.isVisible)
  }

  func testClearReminderPreservesDueDate() {
    let decorator = track(todos.add(title: "remind me"))
    let dueDate = Date.now.addingTimeInterval(86_400)
    let reminderDate = Date.now.addingTimeInterval(3_600)
    todos.setDueDate(decorator, date: dueDate)
    todos.setReminder(decorator, date: reminderDate, repeatRule: .once)

    XCTAssertEqual(decorator.item.reminderDate, reminderDate)
    XCTAssertEqual(decorator.item.dueDate, dueDate)
    XCTAssertEqual(decorator.item.reminderRepeatRule, TodoReminderRepeat.once.rawValue)

    todos.clearReminder(decorator)

    XCTAssertNil(decorator.item.reminderDate)
    XCTAssertEqual(decorator.item.dueDate, dueDate)
    XCTAssertNil(decorator.item.reminderRepeatRule)
  }

  func testRecurringDailyCompleteAdvancesDate() {
    let decorator = track(todos.add(title: "daily habit"))
    let reminderDate = Date.now.addingTimeInterval(3_600)
    todos.setReminder(decorator, date: reminderDate, repeatRule: .daily)
    todos.setDueDate(decorator, date: reminderDate)

    todos.toggleComplete(decorator, source: .checkbox)

    let expected = nextReminderDate(from: reminderDate, rule: .daily)
    XCTAssertFalse(decorator.isCompleted)
    XCTAssertNil(decorator.item.completedAt)
    XCTAssertEqual(decorator.item.timesCompleted, 1)
    XCTAssertEqual(decorator.item.completionHistory.count, 1)
    XCTAssertEqual(decorator.item.reminderDate, expected)
    XCTAssertEqual(decorator.item.dueDate, expected)
    XCTAssertEqual(decorator.item.reminderRepeatRule, TodoReminderRepeat.daily.rawValue)
  }

  func testDeleteCancelsSelection() {
    let decorator = track(todos.add(title: "selected"))
    XCTAssertEqual(todos.selectedId, decorator.id)

    todos.delete(decorator)
    created.removeAll { $0.id == decorator.id }

    XCTAssertNil(todos.selectedId)
    XCTAssertFalse(todos.items.contains(where: { $0.id == decorator.id }))
  }

  func testSetPriority() {
    let decorator = track(todos.add(title: "priority"))
    XCTAssertEqual(decorator.item.priorityRaw, TodoPriority.none.rawValue)

    todos.setPriority(decorator, .high)

    XCTAssertEqual(decorator.priority, .high)
    XCTAssertEqual(decorator.item.priorityRaw, TodoPriority.high.rawValue)
  }

  func testMoveActiveItemsReordersBySortOrder() {
    todos.selectedListFilter = .all
    let older = track(todos.add(title: "reorder-older"))
    let newer = track(todos.add(title: "reorder-newer"))

    XCTAssertLessThan(newer.item.sortOrder, older.item.sortOrder)

    guard let from = todos.activeItems.firstIndex(where: { $0.id == newer.id }),
          let olderIndex = todos.activeItems.firstIndex(where: { $0.id == older.id }) else {
      XCTFail("Expected both todos in activeItems")
      return
    }

    // Move newer to immediately after older.
    todos.moveActiveItems(from: IndexSet(integer: from), to: olderIndex + 1)

    guard let newNewer = todos.activeItems.firstIndex(where: { $0.id == newer.id }),
          let newOlder = todos.activeItems.firstIndex(where: { $0.id == older.id }) else {
      XCTFail("Expected both todos in activeItems after move")
      return
    }

    XCTAssertEqual(newOlder + 1, newNewer)
    XCTAssertLessThan(older.item.sortOrder, newer.item.sortOrder)
  }

  func testEnsureInboxExistsOnLoad() throws {
    let descriptor = FetchDescriptor<TodoList>(
      predicate: #Predicate { $0.isInbox == true }
    )
    let existingInboxes = try Storage.shared.context.fetch(descriptor)
    for inbox in existingInboxes {
      Storage.shared.context.delete(inbox)
    }
    try Storage.shared.context.save()

    try todos.load()

    XCTAssertNotNil(todos.inboxList)
    XCTAssertTrue(todos.inboxList?.isInbox == true)
  }

  func testAddListAndAssignNewTodo() {
    guard let list = trackList(todos.addList(name: "Work List")) else {
      return XCTFail("Expected list to be created")
    }

    XCTAssertEqual(todos.selectedListFilter, .list(list.id))

    let decorator = track(todos.add(title: "assigned to work"))
    XCTAssertEqual(decorator.item.listId, list.id)
  }

  func testDeleteListMovesTodosToInbox() {
    guard let list = trackList(todos.addList(name: "Temp List")) else {
      return XCTFail("Expected list to be created")
    }
    guard let inboxId = todos.inboxList?.id else {
      return XCTFail("Expected inbox list")
    }

    let decorator = track(todos.add(title: "moves to inbox"))
    XCTAssertEqual(decorator.item.listId, list.id)

    todos.deleteList(list)
    createdLists.removeAll { $0.id == list.id }

    XCTAssertEqual(decorator.item.listId, inboxId)
    XCTAssertFalse(todos.lists.contains(where: { $0.id == list.id }))
  }

  func testSetPriorityPersistsWithoutReordering() {
    todos.selectedListFilter = .all

    let first = track(todos.add(title: "first added"))
    let second = track(todos.add(title: "second added is top by sortOrder"))
    XCTAssertEqual(todos.activeItems.first?.id, second.id)

    todos.setPriority(first, .high)
    todos.setPriority(second, .low)

    XCTAssertEqual(first.priority, .high)
    XCTAssertEqual(second.priority, .low)
    // Manual order (sortOrder) remains primary after priority changes.
    XCTAssertEqual(todos.activeItems.first?.id, second.id)
    XCTAssertEqual(todos.activeItems.dropFirst().first?.id, first.id)
  }

  func testDayRolloverBumpsOverdueDueDateAndPriority() {
    Defaults[.lastTodoRolloverDay] = ""

    let decorator = track(todos.add(title: "overdue rollover"))
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date.now)!
    decorator.item.dueDate = yesterday
    decorator.item.priorityRaw = TodoPriority.none.rawValue
    decorator.item.listId = todos.inboxList?.id
    todos.update(decorator)

    todos.performDayRolloverIfNeeded()

    let startOfToday = Calendar.current.startOfDay(for: .now)
    XCTAssertEqual(decorator.item.dueDate, startOfToday)
    XCTAssertEqual(decorator.item.priorityRaw, TodoPriority.medium.rawValue)
    XCTAssertNotNil(decorator.item.rolledOverAt)
  }

  func testMoveToList() {
    guard let list = trackList(todos.addList(name: "Target List")) else {
      return XCTFail("Expected list to be created")
    }

    todos.selectedListFilter = .all
    let decorator = track(todos.add(title: "move me"))
    XCTAssertEqual(decorator.item.listId, todos.inboxList?.id)

    todos.moveToList(decorator, list: list)

    XCTAssertEqual(decorator.item.listId, list.id)
  }

  @discardableResult
  private func track(_ decorator: TodoItemDecorator) -> TodoItemDecorator {
    created.append(decorator)
    return decorator
  }

  @discardableResult
  private func trackList(_ list: TodoList?) -> TodoList? {
    if let list {
      createdLists.append(list)
    }
    return list
  }
}
