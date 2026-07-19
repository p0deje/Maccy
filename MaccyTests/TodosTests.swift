import Defaults
import XCTest
@testable import Maccy

@MainActor
final class TodosTests: XCTestCase {
  private let todos = Todos.shared
  private var created: [TodoItemDecorator] = []
  private var savedRolloverDay = ""
  private var savedListFilter: TodoListFilter = .today

  override func setUp() {
    super.setUp()
    created = []
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

  func testClearReminderClearsDueDate() {
    let decorator = track(todos.add(title: "remind me"))
    let reminderDate = Date.now.addingTimeInterval(3_600)
    todos.setReminder(decorator, date: reminderDate, repeatRule: .once)

    XCTAssertEqual(decorator.item.reminderDate, reminderDate)
    XCTAssertEqual(decorator.item.dueDate, reminderDate)
    XCTAssertEqual(decorator.item.reminderRepeatRule, TodoReminderRepeat.once.rawValue)

    todos.clearReminder(decorator)

    XCTAssertNil(decorator.item.reminderDate)
    XCTAssertNil(decorator.item.dueDate)
    XCTAssertNil(decorator.item.reminderRepeatRule)
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

  func testPerformDayRolloverPromotesOverdue() {
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

  @discardableResult
  private func track(_ decorator: TodoItemDecorator) -> TodoItemDecorator {
    created.append(decorator)
    return decorator
  }
}
