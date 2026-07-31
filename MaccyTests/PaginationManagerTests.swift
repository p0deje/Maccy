import XCTest
@testable import Maccy

/// Synthetic source serving a large list of numbers in small pages,
/// so pagination can be tested independently of history and SwiftData.
private final class NumberSource: PaginatedItemSource {
  var values: [Int]
  var tall: [Int] = []
  private(set) var fetchCalls = 0

  init(count: Int) {
    values = Array(0..<count)
  }

  func count() throws -> Int {
    values.count
  }

  func fetch(offset: Int, limit: Int) throws -> [Int] {
    fetchCalls += 1
    guard offset < values.count else { return [] }
    return Array(values[offset ..< min(values.count, offset + limit)])
  }

  func tallRowIndices() throws -> [Int] {
    tall
  }
}

@MainActor
class PaginationManagerTests: XCTestCase {
  private var source: NumberSource!
  private var manager: PaginationManager<NumberSource>!

  override func setUp() {
    super.setUp()
    source = NumberSource(count: 10_000)
    manager = PaginationManager(source: source, pageSize: 20)
  }

  func testInitialLoad() throws {
    try manager.load()

    XCTAssertEqual(manager.totalCount, 10_000)
    XCTAssertEqual(manager.pageCount, 500)
    // First page plus one page of lookahead.
    XCTAssertEqual(manager.loadedRange, 0..<40)
    XCTAssertEqual(manager.loadedItems, Array(0..<40))
  }

  func testScrollingExtendsWindow() throws {
    try manager.load()
    try manager.ensureRowsLoaded(15..<35)

    // Rows 15..<35 span pages 0-1; with lookahead pages 0-2 are loaded.
    XCTAssertEqual(manager.loadedRange, 0..<60)
    XCTAssertEqual(manager.loadedItems, Array(0..<60))
  }

  func testJumpFarAheadLoadsExactWindow() throws {
    try manager.load()
    // Simulates a fast scroll far beyond the loaded window: the target
    // window must be loaded directly, not reached page by page.
    try manager.ensureRowsLoaded(5000..<5030)

    XCTAssertEqual(manager.loadedRange, 4980..<5060)
    XCTAssertEqual(manager.loadedItems.first, 4980)
    XCTAssertEqual(manager.loadedItems.last, 5059)
    // Pages outside the window were dropped.
    XCTAssertEqual(manager.pages.count, 4)
  }

  func testUnchangedWindowDoesNotRefetch() throws {
    try manager.load()
    try manager.ensureRowsLoaded(15..<35)

    let fetchesBefore = source.fetchCalls
    try manager.ensureRowsLoaded(20..<30)

    XCTAssertEqual(source.fetchCalls, fetchesBefore)
  }

  func testOverlappingPagesAreReused() throws {
    try manager.load()
    try manager.ensureRowsLoaded(0..<30) // pages 0-2

    let fetchesBefore = source.fetchCalls
    try manager.ensureRowsLoaded(30..<50) // pages 0-3, reusing 0-2

    XCTAssertEqual(source.fetchCalls, fetchesBefore + 1)
    XCTAssertEqual(manager.loadedRange, 0..<80)
  }

  func testShortLastPage() throws {
    source.values = Array(0..<45)
    try manager.load()
    try manager.ensureRowsLoaded(40..<45)

    XCTAssertEqual(manager.pageCount, 3)
    XCTAssertEqual(manager.loadedRange, 20..<45)
    XCTAssertEqual(manager.loadedItems.last, 44)
  }

  func testRefreshClampsWindowAfterRemoval() throws {
    try manager.load()
    try manager.ensureRowsLoaded(9_990..<10_000)
    XCTAssertEqual(manager.loadedRange, 9_960..<10_000)

    source.values.removeLast(35)
    try manager.refresh()

    XCTAssertEqual(manager.totalCount, 9_965)
    XCTAssertEqual(manager.loadedRange.upperBound, 9_965)
    XCTAssertEqual(manager.loadedItems.last, 9_964)
  }

  func testRefreshAfterInsertionShiftsContent() throws {
    try manager.load()
    source.values.insert(-1, at: 0)
    try manager.refresh()

    XCTAssertEqual(manager.totalCount, 10_001)
    XCTAssertEqual(manager.loadedItems.first, -1)
  }

  func testEmptySource() throws {
    source.values = []
    try manager.load()

    XCTAssertEqual(manager.totalCount, 0)
    XCTAssertEqual(manager.loadedRange, 0..<0)
    XCTAssertTrue(manager.loadedItems.isEmpty)

    try manager.ensureRowsLoaded(0..<10)
    XCTAssertTrue(manager.loadedItems.isEmpty)
  }

  func testClearedSourceDropsPages() throws {
    try manager.load()
    source.values = []
    try manager.refresh()

    XCTAssertEqual(manager.totalCount, 0)
    XCTAssertTrue(manager.loadedItems.isEmpty)
  }

  func testTallRowIndicesArePassedThrough() throws {
    source.tall = [3, 7, 42]
    try manager.load()

    XCTAssertEqual(manager.tallRowIndices, [3, 7, 42])
  }

  func testOutOfBoundsRequestIsClamped() throws {
    try manager.load()
    try manager.ensureRowsLoaded(20_000..<20_010)

    // Clamped to the last pages of the list.
    XCTAssertEqual(manager.loadedRange.upperBound, 10_000)
    XCTAssertEqual(manager.loadedItems.last, 9_999)
  }
}
