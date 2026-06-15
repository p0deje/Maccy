// swiftlint:disable file_length
import Defaults
import SwiftData
import XCTest
@testable import Maccy

// Integration tests for `BackgroundClipboardIngestor`, the BS-2 off-main ingest
// actor. Under the test plan's `enable-testing` launch argument `Storage.shared`
// is an in-memory SwiftData store; the `@ModelActor` actor is constructed with
// `Storage.shared.container` and commits on its isolated `modelContext`. A fresh
// `fetch` on the MAIN context (`Storage.shared.context`) observes the actor's
// committed save (Core Data shared-store semantics), so each test reads back
// from there. Each test asserts the OUTCOMES of the single-transaction commit
// (item count, event kind, numberOfCopies, applied filters).
//
// Single-save invariant — why it is not asserted directly here (B §2 deferral):
// The structural guarantee is exactly ONE `modelContext.transaction { … }`
// followed by ONE `modelContext.save()` in `BackgroundClipboardIngestor.commit`
// (ClipboardIngestor.swift:248-272). Asserting save-count directly is infeasible
// without a production test-seam:
//  - `ModelContext` is declared `class ModelContext` (Apple,
//    /documentation/swiftdata/modelcontext) — not `final` — but the
//    `@ModelActor` macro constructs it internally via
//    `ModelContext(modelContainer)` into the actor's `modelExecutor`
//    (BackgroundClipboardIngestor.init, ClipboardIngestor.swift:97). There is no
//    injection point to substitute a `save()`-counting subclass for the actor's
//    isolated context, so a ContextSpy can't reach it.
//  - SwiftData DOES post `ModelContext.didSave`
//    (/documentation/swiftdata/modelcontext/didsave), but it is posted by a
//    specific `ModelContext` instance; observing it needs a handle to the
//    actor's private context, which the actor never exposes.
// Injecting a test-only save-count hook into the production actor is rejected as
// an anti-pattern. `testCommitPreservesDistinctItemsAndCountsDuplicateOnMerge`
// below is the strongest feasible BEHAVIORAL PROXY for that atomicity: it would
// break (wrong count / lost distinct item / wrong numberOfCopies) if the
// dup-delete, trim, and insert were not one coordinated transaction.
@MainActor
final class BackgroundClipboardIngestorTests: XCTestCase { // swiftlint:disable:this type_body_length
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
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    let result = await ingestor.ingest(request(text: "hello"))

    XCTAssertEqual(collector.all.count, 1)
    XCTAssertEqual(result.event, collector.all.first)
    XCTAssertEqual(result.metrics.dedupHits, 0)
    XCTAssertGreaterThanOrEqual(result.metrics.bytesHashed, 0)

    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
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
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    _ = await ingestor.ingest(request(text: "duplicate me"))
    let second = await ingestor.ingest(request(text: "duplicate me"))

    XCTAssertEqual(collector.all.count, 2)
    XCTAssertEqual(second.metrics.dedupHits, 1)

    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
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
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    let oversized = String(repeating: "a", count: HistoryItemContent.maxValueSize + 1)
    let result = await ingestor.ingest(request(text: oversized))

    XCTAssertNil(result.event)
    XCTAssertEqual(collector.all.count, 0)

    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 0)
  }

  func testIngestContentMatchingIgnoreRegexpEmitsNoEvent() async {
    Defaults[.ignoreRegexp] = ["secret"]
    let collector = EventCollector()
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    let result = await ingestor.ingest(request(text: "this is a secret message"))

    XCTAssertNil(result.event)
    XCTAssertEqual(collector.all.count, 0)

    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 0)
  }

  // MARK: - Size trim

  func testTrimRemovesOldestUnpinnedItemBeyondSizeLimit() async {
    // With size=2 the trim keeps (size-1)=1 unpinned BEFORE each insert, so after
    // the 3rd ingest only the two most-recent survive — mirroring
    // History.add's limitHistorySize(to: historySizeLimit - 1) (History.swift:244).
    Defaults[.size] = 2
    let collector = EventCollector()
    let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { clock.now },
      onEvent: { event in collector.append(event) }
    )

    _ = await ingestor.ingest(request(text: "first"))
    clock.advance(by: 10)
    _ = await ingestor.ingest(request(text: "second"))
    clock.advance(by: 10)
    _ = await ingestor.ingest(request(text: "third"))

    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    let titles = (stored?.map(\.title) ?? []).sorted()
    XCTAssertEqual(titles, ["second", "third"], "Trim must evict the oldest item ('first')")
  }

  // MARK: - Metrics sanity

  func testParseMsIsFiniteAndNonNegativeOnAdd() async {
    let collector = EventCollector()
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    let result = await ingestor.ingest(request(text: "timing"))

    XCTAssertFalse(result.metrics.parseMs.isNaN)
    XCTAssertGreaterThanOrEqual(result.metrics.parseMs, 0)
  }

  // MARK: - Cross-context visibility (the path the UI tests exercise)

  /// The actor commits on a background `ModelContext`; `History`/UI read the
  /// MAIN context (`Storage.shared.context`). A fresh `fetch` on the main
  /// context must observe the actor's committed save (Core Data shared-store
  /// semantics: all contexts from one container share the store, and a fetch
  /// reads committed rows). This test exercises exactly that cross-context read
  /// under the in-memory `enable-testing` store — the configuration the UI tests
  /// use — so it pinpoints whether a visibility gap is the root cause of the
  /// UI-test "items don't appear" failure. If this FAILS, cross-context
  /// propagation is the issue (fix the write/read bridge); if it PASSES, the UI
  /// failure is a different bug (crash/invocation/timing).
  func testActorBackgroundSaveIsVisibleToMainContext() async {
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { _ in }
    )

    _ = await ingestor.ingest(request(text: "cross-context visibility"))

    // Read back from the MAIN context — NOT the actor's background context.
    // This is the read `History.reconcileWithStore` performs.
    let mainStored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(
      mainStored?.count, 1,
      "Main context must observe the background actor's committed save via a fresh fetch"
    )
    XCTAssertEqual(mainStored?.first?.title, "cross-context visibility")
  }

  // MARK: - RTF (regression guard for off-main NSAttributedString)

  /// RTF/HTML title generation parses via `NSAttributedString`, which is
  /// main-thread-affine (AppKit/WebKit). The actor runs that parsing on the main
  /// actor (see `BackgroundClipboardIngestor.title(for:)`). Driving the actor —
  /// whose body runs on its off-main executor — with RTF would TRAP if
  /// `NSAttributedString` ran off-main, so this test guards that regression.
  func testIngestRtfContentDoesNotTrapOffMain() async {
    let rtf = "{\\rtf1\\ansi rich body}".data(using: .utf8)!
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { _ in }
    )

    let result = await ingestor.ingest(
      IngestRequest(
        source: CopyOrigin(changeCount: 1, name: "test"),
        contents: [ContentDTO(type: "public.rtf", value: rtf, fingerprint: nil, size: rtf.count)],
        application: nil,
        now: Date(timeIntervalSince1970: 1_700_000_000)
      )
    )

    // Reaching here means the actor did NOT trap on off-main NSAttributedString.
    XCTAssertNotNil(result.event, "RTF ingest should produce an event")
    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 1)
  }

  // MARK: - Off-main ingest gate (the core BS-2 promise)

  /// Regression guard proving the heavy ingest work — fetch-all dedup, the
  /// single `transaction`, `processPendingChanges`, and `save` — runs OFF the
  /// main thread. `MainThreadProbe` schedules a 10 ms repeating `Timer` on the
  /// main run loop; if the main thread is blocked, ticks are delayed and
  /// `maxGap` grows well past the tick interval. We pre-populate the store with
  /// 300 `HistoryItem`s so the actor's off-main `findDuplicate` fetch (a
  /// fetch-all over the whole table) plus the transaction/save has real
  /// substance — that is what makes this a meaningful guard: if that work ever
  /// moved back onto the main thread, a 300-row fetch + transaction + save
  /// blocks the run loop for tens of ms and `maxGap` spikes past the threshold.
  ///
  /// This is a COARSE regression guard, NOT the tight <16 ms `G-copy-text`
  /// performance gate (B §4). The strict per-ingest budget is deferred to the
  /// not-yet-created `MaccyPerformanceTests` target. The 100 ms threshold is
  /// chosen for CI scheduling-noise tolerance (timer coalescing, runner load,
  /// GCD hop latency) while still clearly separating an off-main ingest
  /// (`maxGap` ≈ the 10 ms tick + a few ms of jitter ≪ 100 ms) from an on-main
  /// regression (a 300-row fetch + transaction + save on the main thread is
  /// reliably > 100 ms). Plain text never hits `NSAttributedString`, so the
  /// brief `MainActor.run { filterContents + title + ingestConfig }` hop the
  /// actor performs stays cheap and does not by itself move `maxGap`.
  func testIngestKeepsMainThreadFreeUnderLoad() async {
    // Pre-populate the store on the main context (cheap, before the probe).
    let context = Storage.shared.context
    for index in 0..<300 {
      let content = HistoryItemContent(type: stringType, value: "seed-\(index)".data(using: .utf8))
      let item = HistoryItem(contents: [content])
      item.title = "seed-\(index)"
      item.firstCopiedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
      item.lastCopiedAt = item.firstCopiedAt
      context.insert(item)
    }
    try? context.save()

    // Heavy payload via the shared fixture (~31 KB of UTF-8 plain text). The
    // 300-row dedup fetch + single transaction + save over this payload is the
    // work that must stay off-main.
    let heavy = try? Data(contentsOf: FixtureLoader.heavyTextURL)
    XCTAssertNotNil(heavy, "heavy_text.txt fixture must be present at the repo root")
    let request = IngestRequest(
      source: CopyOrigin(changeCount: 1, name: "test"),
      contents: [ContentDTO(type: stringType, value: heavy, fingerprint: nil, size: heavy?.count ?? 0)],
      application: nil,
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { _ in }
    )

    let probe = MainThreadProbe(interval: 0.01)
    probe.start()
    let result = await ingestor.ingest(request)
    probe.stop()

    XCTAssertNotNil(result.event, "Heavy-text ingest should produce an event")
    // 100 ms: see the doc comment for the threshold rationale.
    XCTAssertLessThan(
      probe.maxGap, 0.1,
      "Main thread was blocked for \(probe.maxGap)s during ingest — the heavy " +
      "dedup/transaction/save must run off-main, not on the main actor"
    )
  }

  // MARK: - Single-transaction atomicity (behavioral proxy)

  /// Strongest feasible behavioral proxy for the single-transaction invariant
  /// (B §2). See the file header for why save-count can't be asserted directly.
  ///
  /// `BackgroundClipboardIngestor.commit` removes the duplicate from the
  /// unpinned set BEFORE applying the `limit - 1` trim
  /// (ClipboardIngestor.swift:259-262), then deletes the dup, trims, and inserts
  /// the merged item all inside one `transaction { … }` + one `save()`. This test
  /// guards that ordering specifically: the duplicate is the NEWER item, so that
  /// if `commit` failed to remove the dup from the unpinned count before
  /// trimming, the size-2 trim would evict the distinct OLDER item A.
  ///
  /// Scenario with `Defaults[.size] = 2` (clock advances +10s per ingest):
  ///  - ingest distinct "A" (lastCopiedAt = base) → store [A]
  ///  - ingest distinct "B" (lastCopiedAt = base+10) → store [A, B]
  ///  - ingest a DUPLICATE of "B" (the newer item) under a moved clock → the
  ///    actor merges (dup = B), and `commit(newItem, deleting: B, limit: 2)` must
  ///    remove B from the unpinned count BEFORE the trim.
  ///
  /// Why this makes the ordering observable — `commit` sorts unpinned by
  /// `lastCopiedAt` DESCENDING and trims the oldest tail (`dropFirst(limit - 1)`):
  ///  - Real code: unpinned = [B, A]; remove dup B first → [A], count 1;
  ///    `1 > limit-1 (1)` is false → no trim; delete B; insert mergedB. Final
  ///    store [A, mergedB], count 2, distinct A survives.
  ///  - Broken counterfactual (dup NOT removed before counting): unpinned = [B, A],
  ///    count 2 > 1 → `dropFirst(1)` = [A] → trim deletes distinct A; then delete
  ///    dup B and insert mergedB. Final store [mergedB], count 1, A LOST.
  /// So `count == 2` and "distinct A survives" distinguish the real code from the
  /// broken one; that removal-before-count ordering is exactly what this test
  /// guards. It does NOT exercise every conceivable trim-ordering bug, only this
  /// specific (and the spec-relevant) one.
  ///
  /// The surviving merged "B" item carrying `numberOfCopies == 2` is a separate
  /// atomicity check: it proves the merge read the dup's `numberOfCopies` (1) and
  /// the dup-delete + insert of the augmented item happened in the same
  /// coordinated write.
  func testCommitPreservesDistinctItemsAndCountsDuplicateOnMerge() async {
    Defaults[.size] = 2
    let collector = EventCollector()
    let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { clock.now },
      onEvent: { event in collector.append(event) }
    )

    // Two DISTINCT items → store [A (older), B (newer)].
    _ = await ingestor.ingest(request(text: "A"))
    clock.advance(by: 10)
    _ = await ingestor.ingest(request(text: "B"))
    clock.advance(by: 10)

    // A DUPLICATE of "B" — the NEWER item — under a moved clock → merge.
    let duplicate = await ingestor.ingest(request(text: "B"))

    XCTAssertEqual(collector.all.count, 3)
    if case .merged = collector.all.last {
      // expected: the duplicate ingest produced a .merged event
    } else {
      XCTFail("Expected .merged event on duplicate ingest, got \(String(describing: collector.all.last))")
    }
    XCTAssertEqual(duplicate.metrics.dedupHits, 1, "The duplicate of 'B' must be detected")

    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 2, "Atomic dup-delete + merged-insert must keep the count at 2, not 1 or 3")
    let titles = stored?.map(\.title) ?? []
    XCTAssertTrue(titles.contains("A"), "The distinct older item 'A' must survive the size-2 trim")
    // Only one "B"-content row survives: the duplicate's original row is gone and
    // only the merged B remains.
    let bRows = stored?.filter { $0.title == "B" } ?? []
    XCTAssertEqual(bRows.count, 1, "The duplicate's original 'B' row must be deleted, leaving one merged B")
    // The merged "B" item carries numberOfCopies == 2 (original 1 + this copy).
    XCTAssertEqual(bRows.first?.numberOfCopies, 2, "The merged duplicate must accumulate numberOfCopies")
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
