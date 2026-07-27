import XCTest
@testable import Maccy

@MainActor
final class TodoAnalyticsTests: XCTestCase {
  private var createdItems: [TodoItem] = []

  override func tearDown() {
    for item in createdItems {
      Storage.shared.context.delete(item)
    }
    createdItems = []
    try? Storage.shared.context.save()
    super.tearDown()
  }

  func testWasOverdue() {
    let item = makeItem()
    let now = Date.now

    XCTAssertFalse(TodoAnalytics.wasOverdue(item, at: now))

    item.dueDate = now.addingTimeInterval(60)
    XCTAssertFalse(TodoAnalytics.wasOverdue(item, at: now))

    item.dueDate = now.addingTimeInterval(-60)
    XCTAssertTrue(TodoAnalytics.wasOverdue(item, at: now))
  }

  func testActiveDurationSeconds() {
    let createdAt = Date.now.addingTimeInterval(-120)
    let item = makeItem(createdAt: createdAt)
    let now = Date.now

    let duration = TodoAnalytics.activeDurationSeconds(for: item, at: now)
    XCTAssertLessThanOrEqual(abs(duration - Int(now.timeIntervalSince(createdAt))), 1)

    let reopenedAt = now.addingTimeInterval(-30)
    let event = TodoCompletionEvent(
      completedAt: now.addingTimeInterval(-90),
      reopenedAt: reopenedAt,
      durationSeconds: 60
    )
    event.todo = item
    item.completionHistory.append(event)
    Storage.shared.context.insert(event)

    let afterReopen = TodoAnalytics.activeDurationSeconds(for: item, at: now)
    XCTAssertLessThanOrEqual(abs(afterReopen - Int(now.timeIntervalSince(reopenedAt))), 1)
  }

  func testCompletionSubtitle() {
    let item = makeItem()
    XCTAssertNil(TodoAnalytics.completionSubtitle(for: item))

    item.isCompleted = true
    item.completedAt = Date.now
    item.completionDurationSeconds = 3_600
    item.wasOverdueWhenCompleted = true

    let subtitle = TodoAnalytics.completionSubtitle(for: item)
    XCTAssertNotNil(subtitle)
    XCTAssertTrue(subtitle?.contains("·") == true)
    XCTAssertTrue(subtitle?.contains("Overdue") == true)
  }

  private func makeItem(createdAt: Date = .now) -> TodoItem {
    let item = TodoItem(title: "analytics", createdAt: createdAt, updatedAt: createdAt)
    Storage.shared.context.insert(item)
    createdItems.append(item)
    return item
  }
}
