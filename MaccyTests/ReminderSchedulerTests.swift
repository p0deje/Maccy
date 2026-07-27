import XCTest
@testable import Maccy

@MainActor
final class ReminderSchedulerTests: XCTestCase {
  func testParseNotificationIdentifierPlain() {
    let id = UUID()
    let identifier = "todo-reminder-\(id.uuidString)"

    XCTAssertEqual(ReminderScheduler.todoId(fromNotificationIdentifier: identifier), id)
  }

  func testParseNotificationIdentifierWithRepeatSuffix() {
    let id = UUID()
    let identifier = "todo-reminder-\(id.uuidString)-repeat"

    XCTAssertEqual(ReminderScheduler.todoId(fromNotificationIdentifier: identifier), id)
  }

  func testParseNotificationIdentifierWithWeekdaySuffix() {
    let id = UUID()
    let identifier = "todo-reminder-\(id.uuidString)-wd-2"

    XCTAssertEqual(ReminderScheduler.todoId(fromNotificationIdentifier: identifier), id)
  }

  func testParseNotificationIdentifierInvalid() {
    XCTAssertNil(ReminderScheduler.todoId(fromNotificationIdentifier: "todo-reminder-not-a-uuid"))
    XCTAssertNil(ReminderScheduler.todoId(fromNotificationIdentifier: "todo-reminder-"))
    XCTAssertNil(
      ReminderScheduler.todoId(fromNotificationIdentifier: "todo-reminder-12345678-1234-1234-1234-123456")
    )
  }

  func testParseNotificationIdentifierWrongPrefix() {
    let id = UUID()
    XCTAssertNil(ReminderScheduler.todoId(fromNotificationIdentifier: "reminder-\(id.uuidString)"))
    XCTAssertNil(ReminderScheduler.todoId(fromNotificationIdentifier: "todo-\(id.uuidString)"))
    XCTAssertNil(ReminderScheduler.todoId(fromNotificationIdentifier: id.uuidString))
  }
}
