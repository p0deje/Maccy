import Defaults
import SwiftData
import XCTest
@testable import Maccy

/// Integration tests for `History.refreshForModeChange()` — the search-field
/// mode button's effect on search: re-running the active query under a new
/// mode, and being a no-op when the query is empty.
///
/// The button↔`Defaults[.searchMode]`↔Settings sync is inherent (all bind the
/// same key) and the cycle order is covered by ``SearchModeCycleTests``. These
/// tests pin the *re-search trigger* on ``History/searchGeneration`` — the
/// staleness oracle that `performSearch` bumps synchronously — so assertions
/// are deterministic and free of the debounced search-actor hop's timing.
@MainActor
final class SearchFieldCycleTests: XCTestCase {
  private let stringType = NSPasteboard.PasteboardType.string.rawValue
  private var history = History.shared
  private var savedSearchMode = Defaults[.searchMode]

  override func setUp() async throws {
    try await super.setUp()
    try? Storage.shared.context.delete(model: HistoryItem.self)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()
    history.clearAll()
    history.searchQuery = ""
    savedSearchMode = Defaults[.searchMode]
    Defaults[.searchMode] = .exact
  }

  override func tearDown() async throws {
    Defaults[.searchMode] = savedSearchMode
    history.searchQuery = ""
    try await super.tearDown()
  }

  /// Empty query → `refreshForModeChange` is a no-op: items stay = all, and no
  /// search generation is bumped.
  func test_refreshForModeChange_emptyQuery_isNoOp() {
    populate(["hello", "world"])
    let itemsBefore = history.items.count
    let generationBefore = history.searchGeneration

    history.refreshForModeChange()

    XCTAssertEqual(history.items.count, itemsBefore, "empty query must leave all items visible")
    XCTAssertEqual(history.searchGeneration, generationBefore, "empty query must not trigger a search")
  }

  /// Non-empty query → `refreshForModeChange` re-runs `performSearch`, bumping
  /// the generation oracle synchronously.
  func test_refreshForModeChange_nonEmptyQuery_triggersSearch() {
    populate(["hello", "world"])
    history.searchQuery = "hello"
    let generationAfterQuerySet = history.searchGeneration

    history.refreshForModeChange()

    XCTAssertEqual(
      history.searchGeneration,
      generationAfterQuerySet + 1,
      "refreshForModeChange with a non-empty query must re-run performSearch (bump generation)"
    )
  }

  /// Each refresh re-runs (the mode button can be clicked repeatedly without
  /// getting stuck); every call bumps the oracle once.
  func test_refreshForModeChange_reRunsOnEachCall() {
    populate(["hello", "world"])
    history.searchQuery = "hello"
    history.refreshForModeChange()
    let generationAfterFirst = history.searchGeneration

    Defaults[.searchMode] = .fuzzy
    history.refreshForModeChange()
    Defaults[.searchMode] = .regexp
    history.refreshForModeChange()

    XCTAssertEqual(
      history.searchGeneration,
      generationAfterFirst + 2,
      "two more refreshForModeChange calls must bump generation twice"
    )
  }

  // MARK: - Helpers

  private func populate(_ titles: [String]) {
    for title in titles {
      let contents = [HistoryItemContent(type: stringType, value: title.data(using: .utf8))]
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = contents
      item.numberOfCopies = 1
      item.title = item.generateTitle()
      try? Storage.shared.context.save()
      history.consume(.added(snapshot(of: item)))
    }
  }
}
