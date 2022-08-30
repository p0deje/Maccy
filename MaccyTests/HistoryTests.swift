import XCTest
@testable import Maccy

class HistoryTests: XCTestCase {
  let savedSize = UserDefaults.standard.size
  let savedSortBy = UserDefaults.standard.sortBy
  let history = History()

  override func setUp() {
    super.setUp()
    CoreDataManager.inMemory = true
    history.clear()
    UserDefaults.standard.size = 10
    UserDefaults.standard.sortBy = "firstCopiedAt"
  }

  override func tearDown() {
    super.tearDown()
    CoreDataManager.inMemory = false
    UserDefaults.standard.size = savedSize
    UserDefaults.standard.sortBy = savedSortBy
  }

  func testDefaultIsEmpty() {
    XCTAssertEqual(history.all, [])
  }

  func testAdding() {
    let first = historyItem("foo")
    let second = historyItem("bar")
    history.add(first)
    history.add(second)
    XCTAssertEqual(history.all, [second, first])
  }

  func testAddingSame() {
    let first = historyItem("foo")
    first.pin = "f"
    first.title = "xyz"
    first.application = "iTerm.app"
    history.add(first)
    let second = historyItem("bar")
    history.add(second)
    let third = historyItem("foo")
    third.application = "Xcode.app"
    history.add(third)

    XCTAssertEqual(history.all, [third, second])
    XCTAssertTrue(history.all[0].lastCopiedAt > history.all[0].firstCopiedAt)
    XCTAssertEqual(history.all[0].numberOfCopies, 2)
    XCTAssertEqual(history.all[0].pin, "f")
    XCTAssertEqual(history.all[0].title, "xyz")
    XCTAssertEqual(history.all[0].application, "iTerm.app")
  }

  func testAddingItemThatIsSupersededByExisting() {
    let contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: "one".data(using: .utf8)!),
      HistoryItemContent(type: NSPasteboard.PasteboardType.rtf.rawValue, value: "two".data(using: .utf8)!)
    ]
    let first = HistoryItem(contents: contents)
    history.add(first)

    let second = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: "one".data(using: .utf8)!)
    ])
    history.add(second)

    XCTAssertEqual(history.all, [second])
    XCTAssertEqual(Set(history.all[0].getContents()), Set(contents))
  }

  func testUpdate() {
    history.add(historyItem("foo"))
    let historyItem = history.all[0]
    historyItem.numberOfCopies = 0
    history.update(historyItem)
    XCTAssertEqual(history.all[0].numberOfCopies, 0)
    CoreDataManager.shared.viewContext.refresh(historyItem, mergeChanges: false)
    XCTAssertEqual(history.all[0].numberOfCopies, 0)
  }

  func testClearingUnpinned() {
    let pinned = historyItem("foo")
    pinned.pin = "f"
    history.add(pinned)
    history.add(historyItem("bar"))
    history.clearUnpinned()
    XCTAssertEqual(history.all, [pinned])
  }

  func testClearing() {
    history.add(historyItem("foo"))
    history.clear()
    XCTAssertEqual(history.all, [])
  }

  func testMaxSize() {
    var items: [HistoryItem] = []
    for index in 0...10 {
      let item = historyItem(String(index))
      items.append(item)
      history.add(item)
    }

    XCTAssertEqual(history.all.count, 10)
    XCTAssertTrue(history.all.contains(items[10]))
    XCTAssertFalse(history.all.contains(items[0]))
  }

  func testMaxSizeIgnoresPinned() {
    var items: [HistoryItem] = []

    let item = historyItem("0")
    item.pin = "A"
    items.append(item)
    history.add(item)

    for index in 1...11 {
      let item = historyItem(String(index))
      items.append(item)
      history.add(item)
    }

    XCTAssertEqual(history.all.count, 11)
    XCTAssertTrue(history.all.contains(items[10]))
    XCTAssertTrue(history.all.contains(items[0]))
    XCTAssertFalse(history.all.contains(items[1]))
  }

  func testMaxSizeIsChanged() {
    var items: [HistoryItem] = []
    for index in 0...10 {
      let item = historyItem(String(index))
      items.append(item)
      history.add(item)
    }
    UserDefaults.standard.size = 5

    XCTAssertEqual(history.all.count, 5)
    XCTAssertTrue(history.all.contains(items[10]))
    XCTAssertFalse(history.all.contains(items[5]))
  }

  func testRemoving() {
    let foo = historyItem("foo")
    history.add(foo)
    let bar = historyItem("bar")
    history.add(bar)
    history.remove(foo)
    XCTAssertEqual(history.all, [bar])
  }

  private func historyItem(_ value: String) -> HistoryItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                     value: value.data(using: .utf8)!)
    let item = HistoryItem(contents: [content])
    return item
  }
}
