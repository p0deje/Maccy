import AppKit
import SwiftData
import XCTest
@testable import Maccy

@MainActor
class StorageMigrationTests: XCTestCase {
  func testV1ToV2Migration() throws {
    let storeURL = try makeStoreURL()
    let legacyContainer = try makeLegacyContainer(at: storeURL)
    let ctx = legacyContainer.mainContext

    let foo = insertV1Item(into: ctx, title: "foo", application: "Xcode.app",
                           firstCopiedAt: Date(timeIntervalSince1970: 100),
                           lastCopiedAt: Date(timeIntervalSince1970: 200),
                           numberOfCopies: 3, pin: "x",
                           contents: [(.string, "foo"), (.rtf, "foo-rtf")])
    let bar = insertV1Item(into: ctx, title: "bar", application: "Safari.app",
                           firstCopiedAt: Date(timeIntervalSince1970: 300),
                           lastCopiedAt: Date(timeIntervalSince1970: 400),
                           contents: [(.string, "bar")])
    try ctx.save()

    let migratedContainer = try makeMigratedContainer(at: storeURL)
    let items = try migratedContainer.mainContext.fetch(FetchDescriptor<HistoryItem>())
      .sorted { $0.title < $1.title }

    XCTAssertEqual(items.count, 2)

    XCTAssertEqual(items[0].application, bar.application)
    XCTAssertEqual(items[0].firstCopiedAt, bar.firstCopiedAt)
    XCTAssertEqual(items[0].lastCopiedAt, bar.lastCopiedAt)
    XCTAssertEqual(items[0].numberOfCopies, bar.numberOfCopies)
    XCTAssertEqual(items[0].pin, bar.pin)
    XCTAssertEqual(items[0].title, "bar")
    XCTAssertEqual(items[0].tags, [])
    XCTAssertEqual(items[0].contents.count, 1)

    XCTAssertEqual(items[1].application, foo.application)
    XCTAssertEqual(items[1].firstCopiedAt, foo.firstCopiedAt)
    XCTAssertEqual(items[1].lastCopiedAt, foo.lastCopiedAt)
    XCTAssertEqual(items[1].numberOfCopies, 3)
    XCTAssertEqual(items[1].pin, "x")
    XCTAssertEqual(items[1].title, "foo")
    XCTAssertEqual(items[1].tags, [])
    XCTAssertEqual(items[1].contents.count, 2)
  }

  func testMigratedStoreLoadsHistory() async throws {
    let storeURL = try makeStoreURL()
    let legacyContainer = try makeLegacyContainer(at: storeURL)
    let ctx = legacyContainer.mainContext
    insertV1Item(into: ctx, title: "foo", contents: [(.string, "foo")])
    insertV1Item(into: ctx, title: "bar", contents: [(.string, "bar")])
    try ctx.save()

    let migratedContainer = try makeMigratedContainer(at: storeURL)
    let originalContainer = Storage.shared.container
    defer { Storage.shared.container = originalContainer }

    Storage.shared.container = migratedContainer
    try await History.shared.load()

    XCTAssertEqual(Set(History.shared.all.map(\.item.title)), Set(["foo", "bar"]))
    XCTAssertTrue(History.shared.all.allSatisfy { $0.item.tags.isEmpty })
  }

  // MARK: - Helpers

  private func makeStoreURL() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    return directoryURL.appendingPathComponent("Storage.sqlite")
  }

  private func makeLegacyContainer(at storeURL: URL) throws -> ModelContainer {
    let configuration = ModelConfiguration(url: storeURL)
    return try ModelContainer(
      for: Schema(versionedSchema: StorageSchemaV1.self),
      configurations: configuration
    )
  }

  private func makeMigratedContainer(at storeURL: URL) throws -> ModelContainer {
    let configuration = ModelConfiguration(url: storeURL)
    return try ModelContainer(
      for: Schema(versionedSchema: StorageSchemaV2.self),
      migrationPlan: StorageMigrationPlan.self,
      configurations: configuration
    )
  }

  @discardableResult
  private func insertV1Item(
    into context: ModelContext,
    title: String,
    application: String? = nil,
    firstCopiedAt: Date = Date(timeIntervalSince1970: 0),
    lastCopiedAt: Date = Date(timeIntervalSince1970: 0),
    numberOfCopies: Int = 1,
    pin: String? = nil,
    contents: [(NSPasteboard.PasteboardType, String)]
  ) -> StorageSchemaV1.HistoryItem {
    let item = StorageSchemaV1.HistoryItem()
    item.title = title
    item.application = application
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = numberOfCopies
    item.pin = pin
    item.contents = contents.map { type, value in
      let c = StorageSchemaV1.HistoryItemContent()
      c.type = type.rawValue
      c.value = value.data(using: .utf8)
      return c
    }
    context.insert(item)
    return item
  }
}
