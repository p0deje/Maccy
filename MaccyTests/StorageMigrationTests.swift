import SwiftData
import XCTest
@testable import Maccy

@MainActor
final class StorageMigrationTests: XCTestCase {
  func testTodoModelsPersistInSharedContainer() throws {
    let item = TodoItem(title: "Migration test", sortOrder: 0)
    Storage.shared.context.insert(item)
    try Storage.shared.context.save()

    let descriptor = FetchDescriptor<TodoItem>(
      predicate: #Predicate { $0.title == "Migration test" }
    )
    let fetched = try Storage.shared.context.fetch(descriptor)
    XCTAssertEqual(fetched.count, 1)
    XCTAssertEqual(fetched.first?.title, "Migration test")

    Storage.shared.context.delete(fetched[0])
    try Storage.shared.context.save()
  }

  func testCompletionEventRelationship() throws {
    let item = TodoItem(title: "Complete me")
    Storage.shared.context.insert(item)

    let event = TodoCompletionEvent(durationSeconds: 60, source: "test")
    event.todo = item
    item.completionHistory.append(event)
    Storage.shared.context.insert(event)
    try Storage.shared.context.save()

    let descriptor = FetchDescriptor<TodoItem>(
      predicate: #Predicate { $0.title == "Complete me" }
    )
    let fetched = try Storage.shared.context.fetch(descriptor).first
    XCTAssertEqual(fetched?.completionHistory.count, 1)
    XCTAssertEqual(fetched?.completionHistory.first?.durationSeconds, 60)

    Storage.shared.context.delete(item)
    try Storage.shared.context.save()
  }
}
