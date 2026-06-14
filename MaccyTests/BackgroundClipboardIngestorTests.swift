import Defaults
import SwiftData
import XCTest
@testable import Maccy

// Integration tests for `BackgroundClipboardIngestor`, the BS-2 off-main ingest
// actor. Under the test plan's `enable-testing` launch argument `Storage.shared`
// is an in-memory SwiftData store, so `Storage.shared.newBackgroundContext()`
// yields a disposable `ModelContext` we can hand to the actor and then read back
// from. Each test asserts the OUTCOMES of the single-transaction commit (item
// count, event kind, numberOfCopies, applied filters) — the single-save invariant
// itself is verified by code review of `BackgroundClipboardIngestor.ingest`,
// since asserting save-count directly would require spying on SwiftData.
@MainActor
final class BackgroundClipboardIngestorTests: XCTestCase {
  // Standard pasteboard type rawValues (UTIs). Mirrors NSPasteboard.PasteboardType.
  private let stringType = "public.utf8-plain-text"

  private var savedSize: Int = 200
  private var savedIgnoreRegexp: [String] = []
  private var savedMaxContentSize: Int = ClipboardContentSizeLimit.defaultMegabytes

  override func setUp() {
    super.setUp()
    // `Storage.shared` is an in-memory singleton shared across every test in this
    // run, so clear it in setUp so each test starts from a known-empty store.
    try? Storage.shared.context.delete(model: HistoryItem.self)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()

    savedSize = Defaults[.size]
    savedIgnoreRegexp = Defaults[.ignoreRegexp]
    savedMaxContentSize = Defaults[.maxClipboardContentSize]
    // Make the size limit deterministic and large enough that none of these
    // tests trip the trim path unless they intend to.
    Defaults[.size] = 200
    Defaults[.ignoreRegexp] = []
  }

  override func tearDown() {
    Defaults[.size] = savedSize
    Defaults[.ignoreRegexp] = savedIgnoreRegexp
    Defaults[.maxClipboardContentSize] = savedMaxContentSize
    super.tearDown()
  }

  // MARK: - Add path

  func testIngestTextCopyEmitsAddedEventAndPersistsItem() async {
    let collector = EventCollector()
    let backgroundContext = Storage.shared.newBackgroundContext()
    let ingestor = BackgroundClipboardIngestor(
      backgroundContext: backgroundContext,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    let result = await ingestor.ingest(request(text: "hello"))

    XCTAssertEqual(collector.all.count, 1)
    XCTAssertEqual(result.event, collector.all.first)
    XCTAssertEqual(result.metrics.dedupHits, 0)
    XCTAssertGreaterThanOrEqual(result.metrics.bytesHashed, 0)

    let stored = try? backgroundContext.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 1)
    XCTAssertEqual(stored?.first?.title, "hello")
    XCTAssertEqual(stored?.first?.contents.map(\.type), [stringType])
    XCTAssertEqual(stored?.first?.contents.first?.value, "hello".data(using: .utf8))
    XCTAssertEqual(stored?.first?.numberOfCopies, 1)
    XCTAssertEqual(stored?.first?.firstCopiedAt, Date(timeIntervalSince1970: 1_700_000_000))
    XCTAssertEqual(stored?.first?.lastCopiedAt, Date(timeIntervalSince1970: 1_700_000_000))

    if case .added(let snapshot) = collector.all.first {
      XCTAssertEqual(snapshot.title, "hello")
      XCTAssertEqual(snapshot.numberOfCopies, 1)
    } else {
      XCTFail("Expected .added event, got \(String(describing: collector.all.first))")
    }
  }

  // MARK: - Merge path

  func testIngestSameContentAgainEmitsMergedEventAndKeepsSingleItem() async {
    let collector = EventCollector()
    let backgroundContext = Storage.shared.newBackgroundContext()
    let ingestor = BackgroundClipboardIngestor(
      backgroundContext: backgroundContext,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    _ = await ingestor.ingest(request(text: "duplicate me"))
    let second = await ingestor.ingest(request(text: "duplicate me"))

    XCTAssertEqual(collector.all.count, 2)
    XCTAssertEqual(second.metrics.dedupHits, 1)

    let stored = try? backgroundContext.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 1, "Merge must delete the prior duplicate, not duplicate it")
    XCTAssertEqual(stored?.first?.numberOfCopies, 2)
    XCTAssertEqual(stored?.first?.title, "duplicate me")

    if case .merged(let snapshot) = collector.all.last {
      XCTAssertEqual(snapshot.numberOfCopies, 2)
    } else {
      XCTFail("Expected .merged event on second ingest, got \(String(describing: collector.all.last))")
    }
  }

  // MARK: - Filter-out paths

  func testIngestContentOverMaxValueSizeEmitsNoEventAndPersistsNothing() async {
    // Lower the content-size limit so the oversized payload is modest. With the
    // limit at 1 MiB, any payload larger than 1 MiB is dropped by filterContents.
    Defaults[.maxClipboardContentSize] = 1
    let collector = EventCollector()
    let backgroundContext = Storage.shared.newBackgroundContext()
    let ingestor = BackgroundClipboardIngestor(
      backgroundContext: backgroundContext,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    let oversized = String(repeating: "a", count: HistoryItemContent.maxValueSize + 1)
    let result = await ingestor.ingest(request(text: oversized))

    XCTAssertNil(result.event)
    XCTAssertEqual(collector.all.count, 0)

    let stored = try? backgroundContext.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 0)
  }

  func testIngestContentMatchingIgnoreRegexpEmitsNoEvent() async {
    Defaults[.ignoreRegexp] = ["secret"]
    let collector = EventCollector()
    let backgroundContext = Storage.shared.newBackgroundContext()
    let ingestor = BackgroundClipboardIngestor(
      backgroundContext: backgroundContext,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    let result = await ingestor.ingest(request(text: "this is a secret message"))

    XCTAssertNil(result.event)
    XCTAssertEqual(collector.all.count, 0)

    let stored = try? backgroundContext.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 0)
  }

  // MARK: - Size trim

  func testTrimRemovesOldestUnpinnedItemBeyondSizeLimit() async {
    // With size=2 the trim keeps (size-1)=1 unpinned BEFORE each insert, so after
    // the 3rd ingest only the two most-recent survive — mirroring
    // History.add's limitHistorySize(to: historySizeLimit - 1) (History.swift:244).
    Defaults[.size] = 2
    let collector = EventCollector()
    let backgroundContext = Storage.shared.newBackgroundContext()
    let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
    let ingestor = BackgroundClipboardIngestor(
      backgroundContext: backgroundContext,
      image: PassthroughImageProcessor(),
      now: { clock.now },
      onEvent: { event in collector.append(event) }
    )

    _ = await ingestor.ingest(request(text: "first"))
    clock.advance(by: 10)
    _ = await ingestor.ingest(request(text: "second"))
    clock.advance(by: 10)
    _ = await ingestor.ingest(request(text: "third"))

    let stored = try? backgroundContext.fetch(FetchDescriptor<HistoryItem>())
    let titles = (stored?.map(\.title) ?? []).sorted()
    XCTAssertEqual(titles, ["second", "third"], "Trim must evict the oldest item ('first')")
  }

  // MARK: - Metrics sanity

  func testParseMsIsFiniteAndNonNegativeOnAdd() async {
    let collector = EventCollector()
    let backgroundContext = Storage.shared.newBackgroundContext()
    let ingestor = BackgroundClipboardIngestor(
      backgroundContext: backgroundContext,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    let result = await ingestor.ingest(request(text: "timing"))

    XCTAssertFalse(result.metrics.parseMs.isNaN)
    XCTAssertGreaterThanOrEqual(result.metrics.parseMs, 0)
  }

  // MARK: - Helpers

  /// Builds a single-content text `IngestRequest`.
  private func request(text: String) -> IngestRequest {
    let data = text.data(using: .utf8)
    return IngestRequest(
      source: CopyOrigin(changeCount: 1, name: "test"),
      contents: [
        ContentDTO(type: stringType, value: data, fingerprint: nil, size: data?.count ?? 0)
      ],
      application: nil,
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }
}

/// Thread-safe collector for the `StoreEvent`s the actor emits via its
/// `@Sendable` `onEvent` closure (which can run off the test's isolation).
/// Wrapping the array in a lock avoids the "mutation of captured var in
/// concurrent code" Swift 6 warning that a plain `var events` would trigger.
private final class EventCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [StoreEvent] = []

  func append(_ event: StoreEvent) {
    lock.lock()
    events.append(event)
    lock.unlock()
  }

  var all: [StoreEvent] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }
}

/// Mutable test clock advanced by hand so the actor sees a moving `now` across
/// ingests in the same test.
private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current: Date

  init(start: Date) {
    current = start
  }

  var now: Date {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  func advance(by interval: TimeInterval) {
    lock.lock()
    current = current.addingTimeInterval(interval)
    lock.unlock()
  }
}
