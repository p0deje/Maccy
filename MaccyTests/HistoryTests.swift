// swiftlint:disable file_length
import XCTest
import Defaults
import SwiftData
@testable import Maccy

@MainActor
class HistoryTests: XCTestCase { // swiftlint:disable:this type_body_length
  let savedIgnoreEvents = Defaults[.ignoreEvents]
  let savedExtendedHistory = Defaults[.extendedHistory]
  let savedSize = Defaults[.size]
  let savedSortBy = Defaults[.sortBy]
  let savedPinTo = Defaults[.pinTo]
  let history = History.shared

  override func setUp() {
    super.setUp()
    Defaults[.ignoreEvents] = true
    history.searchQuery = ""
    history.clearAll()
    Defaults[.extendedHistory] = false
    Defaults[.size] = 10
    Defaults[.sortBy] = .firstCopiedAt
    Defaults[.pinTo] = .bottom
  }

  override func tearDown() {
    super.tearDown()
    Defaults[.ignoreEvents] = savedIgnoreEvents
    Defaults[.extendedHistory] = savedExtendedHistory
    Defaults[.size] = savedSize
    Defaults[.sortBy] = savedSortBy
    Defaults[.pinTo] = savedPinTo
  }

  func testDefaultIsEmpty() {
    XCTAssertEqual(history.items, [])
  }

  func testAdding() {
    let first = history.add(historyItem("foo"))
    let second = history.add(historyItem("bar"))
    XCTAssertEqual(history.items, [second, first])
  }

  func testAddingPersistedDuplicate() throws {
    let first = historyItem("foo")
    first.title = "xyz"
    first.application = "iTerm.app"
    history.add(first)
    first.pin = "f"

    let third = historyItem("foo")
    third.application = "Xcode.app"
    let transferredContents = first.contents
    let merged = history.add(third)

    XCTAssertEqual(history.all, [merged])
    XCTAssertEqual(Set(merged.item.contents), Set(transferredContents))
    XCTAssertTrue(merged.item.lastCopiedAt > merged.item.firstCopiedAt)
    XCTAssertEqual(merged.item.numberOfCopies, 2)
    XCTAssertEqual(merged.item.pin, "f")
    XCTAssertEqual(merged.item.title, "xyz")
    XCTAssertEqual(merged.item.application, "iTerm.app")
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testAddingUnsavedDuplicate() throws {
    guard #available(macOS 15.0, *) else {
      throw XCTSkip("Incoming history items are inserted before add on macOS 14")
    }

    let first = historyItem("foo")
    first.title = "xyz"
    first.application = "iTerm.app"
    history.add(first)
    first.pin = "f"

    let second = historyItem("foo", persisted: false)
    second.application = "Xcode.app"
    let transferredContents = first.contents
    let merged = history.add(second)

    XCTAssertEqual(history.all, [merged])
    XCTAssertEqual(Set(merged.item.contents), Set(transferredContents))
    XCTAssertTrue(merged.item.lastCopiedAt > merged.item.firstCopiedAt)
    XCTAssertEqual(merged.item.numberOfCopies, 2)
    XCTAssertEqual(merged.item.pin, "f")
    XCTAssertEqual(merged.item.title, "xyz")
    XCTAssertEqual(merged.item.application, "iTerm.app")
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testAddingItemThatIsSupersededByExisting() throws {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.rtf.rawValue,
        value: "two".data(using: .utf8)!
      )
    ]
    let firstItem = HistoryItem()
    Storage.shared.context.insert(firstItem)
    firstItem.application = "Maccy.app"
    firstItem.contents = firstContents
    firstItem.title = firstItem.generateTitle()
    history.add(firstItem)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      )
    ]
    let secondItem = HistoryItem()
    Storage.shared.context.insert(secondItem)
    secondItem.application = "Maccy.app"
    secondItem.contents = secondContents
    secondItem.title = secondItem.generateTitle()
    let second = history.add(secondItem)

    XCTAssertEqual(history.items, [second])
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
    try assertStorageCounts(items: 1, contents: firstContents.count)
  }

  func testAddingItemWithDifferentModifiedType() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: "1".data(using: .utf8)!
      )
    ]
    let firstItem = HistoryItem()
    Storage.shared.context.insert(firstItem)
    firstItem.contents = firstContents
    history.add(firstItem)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: "2".data(using: .utf8)!
      )
    ]
    let secondItem = HistoryItem()
    Storage.shared.context.insert(secondItem)
    secondItem.contents = secondContents
    let second = history.add(secondItem)

    XCTAssertEqual(history.items, [second])
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testAddingItemFromMaccy() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)
      )
    ]
    let first = HistoryItem()
    Storage.shared.context.insert(first)
    first.application = "Xcode.app"
    first.contents = firstContents
    history.add(first)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fromMaccy.rawValue,
        value: "".data(using: .utf8)
      )
    ]
    let second = HistoryItem()
    Storage.shared.context.insert(second)
    second.application = "Maccy.app"
    second.contents = secondContents
    let secondDecorator = history.add(second)

    XCTAssertEqual(history.items, [secondDecorator])
    XCTAssertEqual(history.items[0].item.application, "Xcode.app")
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testModifiedAfterCopying() {
    history.add(historyItem("foo"))

    let modifiedItem = historyItem("bar")
    modifiedItem.contents.append(HistoryItemContent(
      type: NSPasteboard.PasteboardType.modified.rawValue,
      value: String(Clipboard.shared.changeCount).data(using: .utf8)
    ))
    let modifiedItemDecorator = history.add(modifiedItem)

    XCTAssertEqual(history.items, [modifiedItemDecorator])
    XCTAssertEqual(history.items[0].text, "bar")
  }

  func testClearingUnpinned() throws {
    let pinned = history.add(historyItem("foo"))
    pinned.togglePin()
    history.add(historyItem("bar"))
    let orphan = HistoryItemContent(
      type: NSPasteboard.PasteboardType.string.rawValue,
      value: "orphan".data(using: .utf8)
    )
    Storage.shared.context.insert(orphan)
    try Storage.shared.context.save()

    history.clear()

    XCTAssertEqual(history.items, [pinned])
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testClearingAll() throws {
    history.add(historyItem("foo"))
    let pinned = history.add(historyItem("bar"))
    pinned.togglePin()
    Storage.shared.context.insert(HistoryItemContent(
      type: NSPasteboard.PasteboardType.string.rawValue,
      value: "orphan".data(using: .utf8)
    ))
    try Storage.shared.context.save()

    history.clearAll()

    XCTAssertEqual(history.items, [])
    try assertStorageCounts(items: 0, contents: 0)
  }

  func testMaxSize() throws {
    var items: [HistoryItemDecorator] = []
    for index in 0...10 {
      items.append(history.add(historyItem(String(index))))
    }

    XCTAssertEqual(history.items.count, 10)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertFalse(history.items.contains(items[0]))
    try assertStorageCounts(items: 10, contents: 10)
  }

  func testMaxSizeIgnoresPinned() {
    var items: [HistoryItemDecorator] = []

    let item = history.add(historyItem("0"))
    items.append(item)
    item.togglePin()

    for index in 1...11 {
      items.append(history.add(historyItem(String(index))))
    }

    XCTAssertEqual(history.items.count, 11)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertTrue(history.items.contains(items[0]))
    XCTAssertFalse(history.items.contains(items[1]))
  }

  func testMaxSizeIsChanged() {
    var items: [HistoryItemDecorator] = []
    for index in 0...10 {
      items.append(history.add(historyItem(String(index))))
    }
    Defaults[.size] = 5
    history.add(historyItem("11"))

    XCTAssertEqual(history.items.count, 5)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertFalse(history.items.contains(items[5]))
  }

  func testNewCopyIsRetainedWhenSortingByCopyCount() throws {
    Defaults[.size] = 2
    Defaults[.sortBy] = .numberOfCopies
    history.add(historyItem("frequent one"))
    history.add(historyItem("frequent two"))
    history.add(historyItem("frequent one"))
    history.add(historyItem("frequent two"))
    XCTAssertTrue(history.all.allSatisfy { $0.item.numberOfCopies == 2 })

    let newest = history.add(historyItem("newest copy"))
    XCTAssertFalse(newest.item.isDeleted)
    XCTAssertTrue(history.all.contains(newest))
    try assertStorageCounts(items: 2, contents: 2)
  }

  func testSingleItemLimitStillRetainsNewCopy() throws {
    Defaults[.size] = 1
    Defaults[.sortBy] = .numberOfCopies
    history.add(historyItem("frequent"))
    history.add(historyItem("frequent"))
    let newest = history.add(historyItem("newest copy"))
    XCTAssertEqual(history.all, [newest])
    XCTAssertFalse(newest.item.isDeleted)
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testReaddingBottomMostPinnedItemAtFullCapacity() {
    // Regression test for a crash when re-copying (invoking) the bottom-most
    // pinned item while history is at full capacity and pins are sorted to the
    // bottom. The stale insert index used to trap with an out-of-bounds insert.
    // Issue link: https://github.com/p0deje/Maccy/issues/1466
    // `pinTo` is restored to its default value(.top) in `tearDown`.
    Defaults[.pinTo] = .bottom

    // Pin an item; `history.togglePin` re-sorts `all`, so with `.bottom` the
    // pinned item ends up as the last element.
    let pinned = history.add(historyItem("pinned"))
    history.togglePin(pinned)

    // Fill unpinned history to full capacity.
    for index in 0..<Defaults[.size] {
      history.add(historyItem(String(index)))
    }

    XCTAssertEqual(history.all.last, pinned)

    // Re-copy the pinned item and retain its position after deduplication.
    let readded = history.add(historyItem("pinned"))

    XCTAssertTrue(history.all.contains(readded))
    XCTAssertEqual(history.all.filter(\.isPinned).count, 1)
  }

  func testRemoving() throws {
    let foo = history.add(historyItem("foo"))
    let bar = history.add(historyItem("bar"))
    history.delete(foo)
    XCTAssertEqual(history.items, [bar])
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testCleaningUpOrphanedContents() throws {
    let live = history.add(historyItem("live"))
    let liveContent = live.item.contents[0]
    for value in ["orphan-1", "orphan-2"] {
      Storage.shared.context.insert(HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      ))
    }
    try Storage.shared.context.save()

    XCTAssertEqual(try Storage.shared.cleanupOrphanedContents(), 2)
    XCTAssertEqual(try Storage.shared.cleanupOrphanedContents(), 0)
    XCTAssertEqual(live.item.contents, [liveContent])
    try assertStorageCounts(items: 1, contents: 1)
  }

  private func assertStorageCounts(
    items: Int,
    contents: Int,
    orphaned: Int = 0,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let context = Storage.shared.context
    context.processPendingChanges()
    try context.save()
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<HistoryItem>()),
      items,
      file: file,
      line: line
    )
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<HistoryItemContent>()),
      contents,
      file: file,
      line: line
    )
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<HistoryItemContent>(
        predicate: #Predicate { $0.item == nil }
      )),
      orphaned,
      file: file,
      line: line
    )
  }

  func testPermanentCacheKeepsArchiveAcrossReloadAndCopy() async throws {
    Defaults[.size] = -1
    Defaults[.extendedHistory] = true
    for index in 0..<1_205 {
      let item = historyItem("archive-entry-\(index)")
      item.lastCopiedAt = Date(timeIntervalSince1970: Double(index))
    }
    let pin = historyItem("old-pin")
    pin.pin = "b"
    pin.lastCopiedAt = .distantPast
    try Storage.shared.context.save()
    try await history.load()
    XCTAssertEqual(history.all.count, 1_001)
    XCTAssertTrue(history.all.contains { $0.item == pin })
    XCTAssertFalse(history.all.contains { $0.title == "archive-entry-0" })
    try assertStorageCounts(items: 1_206, contents: 1_206)

    history.add(historyItem("new-clipboard-value"))
    XCTAssertEqual(history.all.count, 1_001)
    try assertStorageCounts(items: 1_207, contents: 1_207)
    try await history.load()
    XCTAssertEqual(history.all.count, 1_001)
    XCTAssertTrue(history.all.contains { $0.title == "new-clipboard-value" })

    let worker = ArchiveSearch(modelContainer: Storage.shared.container)
    let found = try await worker.find(query: "archive-entry-0", page: 0)
    XCTAssertEqual(found.count, 1)
    let firstPage = try await worker.find(query: "archive-entry-", page: 0)
    let secondPage = try await worker.find(query: "archive-entry-", page: 1)
    XCTAssertEqual(firstPage.count, 101)
    XCTAssertEqual(secondPage.count, 101)
    XCTAssertTrue(Set(firstPage.prefix(100)).isDisjoint(with: Set(secondPage.prefix(100))))
    let lastPage = try await worker.find(query: "archive-entry-", page: 12)
    XCTAssertEqual(lastPage.count, 5)
    try assertStorageCounts(items: 1_207, contents: 1_207)
  }

  func testDeepSearchReturnsColdItemAndResetsOnQueryChange() async throws {
    Defaults[.size] = -1
    Defaults[.extendedHistory] = true
    let history = History()
    let savedSearchMode = Defaults[.searchMode]
    Defaults[.searchMode] = .exact
    defer { Defaults[.searchMode] = savedSearchMode }
    let cold = historyItem("cold-needle")
    cold.lastCopiedAt = .distantPast
    for index in 0..<1_001 { _ = historyItem("recent-\(index)") }
    try Storage.shared.context.save()
    try await history.load()
    history.searchQuery = "cold-needle"
    history.startDeepSearch()
    for _ in 0..<200 where history.deepSearchLoading {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertFalse(history.deepSearchLoading)
    XCTAssertNil(history.deepSearchError)
    XCTAssertEqual(history.items.map(\.title), ["cold-needle"])
    let selected = try XCTUnwrap(history.items.first)
    history.togglePin(selected)
    XCTAssertTrue(history.all.contains { $0.item == cold })
    history.searchQuery = "recent"
    XCTAssertFalse(history.deepSearchActive)
    try await Task.sleep(for: .milliseconds(250))
    XCTAssertFalse(history.items.contains { $0.item == cold })
    history.searchQuery = ""
  }

  func testNewCopyDoesNotLeaveDeletedDuplicateInArchiveResults() async throws {
    Defaults[.size] = -1
    Defaults[.extendedHistory] = true
    try await Task.sleep(for: .milliseconds(100))
    let previous = history.add(historyItem("duplicate in archive page"))
    let previousID = previous.item.persistentModelID
    history.startDeepSearch()
    for _ in 0..<200 where history.deepSearchLoading {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(history.items.contains { $0.item.persistentModelID == previousID })

    let replacement = history.add(historyItem("duplicate in archive page"))
    XCTAssertFalse(history.items.contains { $0.item.persistentModelID == previousID })
    XCTAssertTrue(history.items.contains(replacement))
    try assertStorageCounts(items: 1, contents: 1)
  }

  func testSearchTransitionsClearInvisibleSelection() throws {
    Defaults[.size] = -1
    Defaults[.extendedHistory] = true
    let recent = history.add(historyItem("recent"))
    let cold = historyItem("cold")
    let coldDecorator = HistoryItemDecorator(cold)
    history.items = [coldDecorator]
    history.deepSearchActive = true
    AppState.shared.navigator.select(item: coldDecorator)
    history.endDeepSearch()
    XCTAssertEqual(AppState.shared.navigator.selection.first, recent)
    AppState.shared.deleteSelection()
    XCTAssertFalse(cold.isDeleted)
    try assertStorageCounts(items: 1, contents: 1)

    history.startDeepSearch()
    XCTAssertTrue(AppState.shared.navigator.selection.isEmpty)
    AppState.shared.deleteSelection()
    XCTAssertFalse(cold.isDeleted)
    history.endDeepSearch()
  }

  func testCopyingArchiveWhilePausedDoesNotGrowCacheOrDeleteOldData() throws {
    Defaults[.size] = -1
    Defaults[.extendedHistory] = true
    let savedIgnore = Defaults[.ignoreEvents]
    let savedPaste = Defaults[.pasteByDefault]
    Defaults[.ignoreEvents] = true
    Defaults[.pasteByDefault] = false
    defer {
      Defaults[.ignoreEvents] = savedIgnore
      Defaults[.pasteByDefault] = savedPaste
    }
    for index in 0..<1_000 {
      history.all.append(HistoryItemDecorator(historyItem("hot-\(index)")))
    }
    let cold = (0..<3).map { historyItem("old-\($0)") }
    try Storage.shared.context.save()
    for item in cold {
      history.select(HistoryItemDecorator(item), flags: [])
      XCTAssertEqual(history.all.count, 1_000)
      XCTAssertFalse(item.isDeleted)
    }
    try assertStorageCounts(items: 1_003, contents: 1_003)
    let copied = history.add(historyItem("old-0"))
    XCTAssertEqual(history.all.count, 1_000)
    XCTAssertTrue(history.all.contains(copied))
    XCTAssertFalse(cold[0].isDeleted)
    try assertStorageCounts(items: 1_004, contents: 1_004)
  }

  func testDisabledArchiveSearchDoesNotStartOrChangeRetention() async throws {
    Defaults[.size] = -1
    Defaults[.extendedHistory] = false
    for index in 0..<1_005 { _ = historyItem("retained-\(index)") }
    try Storage.shared.context.save()
    try await history.load()
    history.startDeepSearch()
    XCTAssertFalse(history.deepSearchActive)
    XCTAssertEqual(history.all.count, 1_000)
    XCTAssertEqual(Defaults[.size], -1)
    try assertStorageCounts(items: 1_005, contents: 1_005)
    Defaults[.extendedHistory] = true
    Defaults[.extendedHistory] = false
    try await history.load()
    try assertStorageCounts(items: 1_005, contents: 1_005)
  }

  func testFiniteArchiveLimitRemovesOverflowButKeepsPins() async throws {
    Defaults[.size] = 1_100
    Defaults[.extendedHistory] = true
    Defaults[.sortBy] = .lastCopiedAt
    for index in 0..<1_205 {
      let item = historyItem("finite-\(index)-end")
      item.lastCopiedAt = Date(timeIntervalSince1970: Double(index))
    }
    let pin = historyItem("old pin")
    pin.pin = "p"
    pin.lastCopiedAt = .distantPast
    try Storage.shared.context.save()
    try await history.load()
    XCTAssertEqual(history.all.count, 1_001)
    try assertStorageCounts(items: 1_101, contents: 1_101)
    history.add(historyItem("new copy"))
    try assertStorageCounts(items: 1_101, contents: 1_101)
    XCTAssertEqual(history.all.count, 1_001)
    XCTAssertFalse(pin.isDeleted)
    let worker = ArchiveSearch(modelContainer: Storage.shared.container)
    let deleted = try await worker.find(query: "finite-0-end", page: 0)
    let retained = try await worker.find(query: "finite-106-end", page: 0)
    XCTAssertTrue(deleted.isEmpty)
    XCTAssertEqual(retained.count, 1)
  }

  func testRenderingLegacyTitleDoesNotRewriteArchive() throws {
    let item = historyItem("legacy")
    item.title = "legacy\u{FFFC}title"
    let original = item.title
    try Storage.shared.context.save()
    let decorator = HistoryItemDecorator(item)
    XCTAssertEqual(item.title, original)
    XCTAssertEqual(decorator.title, "legacytitle")
  }

  func testDecoratorCanBeReleasedAfterCacheEviction() {
    let item = historyItem("temporary")
    weak var released: HistoryItemDecorator?
    autoreleasepool {
      let decorator = HistoryItemDecorator(item)
      released = decorator
    }
    XCTAssertNil(released)
  }

  private func historyItem(_ value: String, persisted: Bool = true) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    if persisted {
      Storage.shared.context.insert(item)
    }
    item.contents = contents
    item.numberOfCopies = 1
    item.title = item.generateTitle()

    return item
  }
}
