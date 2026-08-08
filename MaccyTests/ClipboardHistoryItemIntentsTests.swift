import AppIntents
import XCTest
import Defaults
@testable import Maccy

@MainActor
final class ClipboardHistoryItemIntentsTests: XCTestCase {
  private let history = History.shared
  private let savedPasteByDefault = Defaults[.pasteByDefault]
  private let savedSize = Defaults[.size]

  override func setUp() {
    super.setUp()
    history.clearAll()
    Defaults[.size] = 10
    // Selecting a valid item copies it to the pasteboard and, when
    // `pasteByDefault` is on, pastes it; both are unwanted side effects in a
    // headless unit test, so pasting is suppressed for the success-path check.
    Defaults[.pasteByDefault] = false
  }

  override func tearDown() {
    Defaults[.pasteByDefault] = savedPasteByDefault
    Defaults[.size] = savedSize
    // Don't leave inserted items or a mutated pasteboard for downstream test
    // classes that share the process-wide Storage / Clipboard singletons.
    history.clearAll()
    super.tearDown()
  }

  /// Regression test for an off-by-one bound check in the clipboard-history
  /// Shortcuts actions (`Delete`, `Select`, `Get`). With `number` set one past
  /// the last item — or below 1 — the old `items.count >= index` guard let the
  /// invalid 0-based `index` through and the next `items[index]` access trapped
  /// with an index-out-of-range crash.
  func testDeleteItemIntentBounds() async {
    // `number = 4` with three items (one past the last valid number) must reject.
    populateHistory(3)
    let over = Delete()
    over.number = 4
    await assertRejectsOutOfRange(over)
    XCTAssertEqual(history.items.count, 3, "An out-of-range number must not delete anything")

    // `number = 3` (the last valid item) must succeed and delete exactly that item.
    populateHistory(3)
    let valid = Delete()
    valid.number = history.items.count
    await assertResolves(valid)
    XCTAssertEqual(history.items.count, 2, "The last valid item should have been deleted")

    // `number = 0` (below the first item) must reject.
    populateHistory(3)
    let under = Delete()
    under.number = 0
    await assertRejectsOutOfRange(under)
    XCTAssertEqual(history.items.count, 3, "A number below 1 must not delete anything")
  }

  func testSelectItemIntentBounds() async throws {
    populateHistory(3)
    let over = Select()
    over.number = 4
    await assertRejectsOutOfRange(over)

    populateHistory(3)
    let lastIndex = history.items.count - 1
    // Capture before perform(): selecting the item copies it and reorders the
    // history, so reading the expected value afterwards would compare the wrong row.
    let expectedTitle: String? = history.items[lastIndex].title
    let valid = Select()
    valid.number = history.items.count
    let result = try await valid.perform()
    XCTAssertEqual(result.value, expectedTitle)

    populateHistory(3)
    let under = Select()
    under.number = 0
    await assertRejectsOutOfRange(under)
  }

  func testGetItemIntentBounds() async throws {
    populateHistory(3)
    let over = Get()
    over.selected = false
    over.number = 4
    await assertRejectsOutOfRange(over)

    populateHistory(3)
    let lastIndex = history.items.count - 1
    let expectedText: String? = history.items[lastIndex].item.text
    let valid = Get()
    valid.selected = false
    valid.number = history.items.count
    let result = try await valid.perform()
    XCTAssertEqual(result.value?.text, expectedText)

    populateHistory(3)
    let under = Get()
    under.selected = false
    under.number = 0
    await assertRejectsOutOfRange(under)
  }

  // MARK: - Helpers

  @discardableResult
  private func populateHistory(_ count: Int) -> [HistoryItemDecorator] {
    history.clearAll()
    return (1...count).map { history.add(historyItem(String($0))) }
  }

  private func assertRejectsOutOfRange<T: AppIntent>(_ intent: T) async {
    do {
      _ = try await intent.perform()
      XCTFail("Expected AppIntentError.notFound for an out-of-range item number")
    } catch {
      // Cast before the case-match: a bare `catch AppIntentError.notFound` is
      // resolved against `_ErrorCodeProtocol` on the current SDK and won't compile.
      if let intentError = error as? Maccy.AppIntentError, case .notFound = intentError {
        // expected — the invalid number is rejected instead of indexing past the end
      } else {
        XCTFail("Expected AppIntentError.notFound but got \(error)")
      }
    }
  }

  private func assertResolves<T: AppIntent>(_ intent: T) async {
    do {
      _ = try await intent.perform()
    } catch {
      XCTFail("Expected the last valid item number to resolve but got \(error)")
    }
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
