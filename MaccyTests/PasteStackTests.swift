import XCTest
import Defaults
import AppKit
@testable import Maccy

@MainActor
class PasteStackTests: XCTestCase {
  let history = History.shared
  let savedEnablePasteStack = Defaults[.enablePasteStack]
  let savedPasteByDefault = Defaults[.pasteByDefault]
  let savedRemoveFormattingByDefault = Defaults[.removeFormattingByDefault]
  let savedPasteStackQueueExternalCopies = Defaults[.pasteStackQueueExternalCopies]
  let savedSize = Defaults[.size]

  override func setUp() {
    super.setUp()
    history.clearAll()
    history.interruptPasteStack()
    Defaults[.size] = 10
    Defaults[.enablePasteStack] = true
    Defaults[.pasteByDefault] = false
    Defaults[.removeFormattingByDefault] = false
    Defaults[.pasteStackQueueExternalCopies] = false
  }

  override func tearDown() {
    history.interruptPasteStack()
    history.clearAll()
    Defaults[.enablePasteStack] = savedEnablePasteStack
    Defaults[.pasteByDefault] = savedPasteByDefault
    Defaults[.removeFormattingByDefault] = savedRemoveFormattingByDefault
    Defaults[.pasteStackQueueExternalCopies] = savedPasteStackQueueExternalCopies
    Defaults[.size] = savedSize
    super.tearDown()
  }

  func testStartPasteStackWithMultipleItems() {
    let first = history.add(historyItem("one"))
    let second = history.add(historyItem("two"))
    let third = history.add(historyItem("three"))

    var selection = Selection(items: [first, second, third])
    history.startPasteStack(selection: &selection, modifierFlags: [])

    XCTAssertNotNil(history.pasteStack)
    XCTAssertEqual(history.pasteStack?.items.map(\.text), ["one", "two", "three"])
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "one")
  }

  func testStartPasteStackDisabledDoesNothing() {
    Defaults[.enablePasteStack] = false
    let first = history.add(historyItem("one"))
    let second = history.add(historyItem("two"))

    var selection = Selection(items: [first, second])
    history.startPasteStack(selection: &selection, modifierFlags: [])

    XCTAssertNil(history.pasteStack)
  }

  func testAdvancePasteStackCopiesNextItem() async {
    let first = history.add(historyItem("one"))
    let second = history.add(historyItem("two"))
    let third = history.add(historyItem("three"))

    var selection = Selection(items: [first, second, third])
    history.startPasteStack(selection: &selection, modifierFlags: [])

    history.handlePasteStack()
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(history.pasteStack?.items.map(\.text), ["two", "three"])
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "two")

    history.handlePasteStack()
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(history.pasteStack?.items.map(\.text), ["three"])
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "three")

    history.handlePasteStack()
    XCTAssertNil(history.pasteStack)
  }

  func testInterruptPasteStackClearsStack() {
    let first = history.add(historyItem("one"))
    let second = history.add(historyItem("two"))

    var selection = Selection(items: [first, second])
    history.startPasteStack(selection: &selection, modifierFlags: [])
    XCTAssertNotNil(history.pasteStack)

    history.interruptPasteStack()
    XCTAssertNil(history.pasteStack)
  }

  func testMultiSelectionEnabledTracksDefaults() {
    Defaults[.enablePasteStack] = true
    XCTAssertTrue(AppState.shared.multiSelectionEnabled)

    Defaults[.enablePasteStack] = false
    XCTAssertFalse(AppState.shared.multiSelectionEnabled)
  }

  private func historyItem(_ value: String) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.numberOfCopies = 1
    item.title = item.generateTitle()

    return item
  }
}
