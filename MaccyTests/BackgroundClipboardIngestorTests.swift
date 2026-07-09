import Defaults
import SwiftData
import XCTest
import os
@testable import Maccy

/// Integration tests for the off-main clipboard ingest actor.
///
/// Under the test plan's `enable-testing` launch argument `Storage.shared` is an
/// in-memory SwiftData store. The actor is constructed with
/// `Storage.shared.container` and commits on its isolated `modelContext`; a
/// fresh `fetch` on the main context (`Storage.shared.context`) observes the
/// actor's committed save via Core Data shared-store semantics, so each test
/// reads back from there. Each test asserts the outcomes of the actor's
/// single-transaction commit (item count, event kind, `numberOfCopies`, applied
/// filters).
///
/// The single-transaction invariant (one `modelContext.transaction { … }` plus
/// one `save()` per ingest) is not asserted directly: the `@ModelActor` macro
/// constructs the actor's isolated `ModelContext` internally, so there is no
/// injection point for a save-counting test double, and SwiftData's
/// `ModelContext.didSave` notification needs a handle to that private context.
/// `testCommitPreservesDistinctItemsAndCountsDuplicateOnMerge` is the strongest
/// feasible behavioral proxy: it would break if the dup-delete, trim, and insert
/// were not one coordinated transaction.
@MainActor
final class BackgroundClipboardIngestorTests: XCTestCase {
  /// Standard pasteboard UTI for UTF-8 plain text.
  private let stringType = "public.utf8-plain-text"

  private var savedSize: Int = 200
  private var savedIgnoreRegexp: [String] = []
  private var savedMaxContentSize: Int = ClipboardContentSizeLimit.defaultMegabytes

  override func setUp() async throws {
    try await super.setUp()
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

  override func tearDown() async throws {
    Defaults[.size] = savedSize
    Defaults[.ignoreRegexp] = savedIgnoreRegexp
    Defaults[.maxClipboardContentSize] = savedMaxContentSize
    try await super.tearDown()
  }

  // MARK: - Add path

  /// Ingesting a text copy emits an `.added` event and persists exactly one item.
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

  /// Re-ingesting identical content emits a `.merged` event, bumps
  /// `numberOfCopies`, and keeps a single stored item.
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

  /// Content exceeding the per-value size cap is dropped: no event, nothing persisted.
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

  /// Content matching an ignore-regexp rule is dropped: no event, nothing persisted.
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

  /// Beyond the size limit, the oldest unpinned item is evicted before each insert.
  func testTrimRemovesOldestUnpinnedItemBeyondSizeLimit() async {
    // With size=2 the trim keeps (size-1)=1 unpinned before each insert, so after
    // the 3rd ingest only the two most-recent survive — mirroring the
    // `limitHistorySize(to: historySizeLimit - 1)` contract.
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

  /// The reported parse time is finite and non-negative on a text ingest.
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

  /// The actor commits on a background `ModelContext`; `History` and the UI read
  /// the main context (`Storage.shared.context`). A fresh `fetch` on the main
  /// context must observe the actor's committed save (Core Data shared-store
  /// semantics: all contexts from one container share the store, and a fetch
  /// reads committed rows). This test exercises that cross-context read under
  /// the in-memory `enable-testing` store — the configuration the UI tests use —
  /// so it pinpoints whether a visibility gap is the root cause of an
  /// "items don't appear" UI failure. If this fails, cross-context propagation
  /// is the issue (fix the write/read bridge); if it passes, the UI failure is
  /// a different bug (crash/invocation/timing).
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
  /// whose body runs on its off-main executor — with RTF would trap if
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

  // MARK: - Off-main ingest gate

  /// Non-flaky load-path smoke test: ingesting a ~31 KB payload over a 300-row
  /// store (beyond the size limit) must complete, emit one event, and trim back
  /// to the limit in a single transaction.
  ///
  /// The off-main guarantee is structural, not timing-based:
  /// `BackgroundClipboardIngestor` is a `@ModelActor` actor, so Swift runs its
  /// fetch/dedup/transaction/save on the actor's serial executor off the main
  /// thread. An earlier main-thread-gap version of this test was flaky on the
  /// shared CI runner — the actor's intentional
  /// `MainActor.run { filterContents + title }` hop on a 31 KB payload
  /// legitimately costs ~100-200 ms on the main thread (the designed on-main
  /// parsing path), which is not an off-main leak. A strict sub-frame gate on
  /// the copy path belongs in the dedicated performance-test target; the
  /// off-main property is also guarded by
  /// `testIngestRtfContentDoesNotTrapOffMain`.
  func testIngestUnderLoadCompletesAndTrimsToSizeLimit() async {
    let context = Storage.shared.context
    let sizeLimit = max(1, Defaults[.size])
    for index in 0..<300 {
      let content = HistoryItemContent(type: stringType, value: "seed-\(index)".data(using: .utf8))
      let item = HistoryItem(contents: [content])
      item.title = "seed-\(index)"
      item.firstCopiedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
      item.lastCopiedAt = item.firstCopiedAt
      context.insert(item)
    }
    try? context.save()

    // Heavy payload via the shared fixture (~31 KB of UTF-8 plain text).
    let heavy = try? Data(contentsOf: FixtureLoader.heavyTextURL)
    XCTAssertNotNil(heavy, "heavy_text.txt fixture must be present in MaccyTests/Fixtures/")
    let request = IngestRequest(
      source: CopyOrigin(changeCount: 1, name: "test"),
      contents: [ContentDTO(type: stringType, value: heavy, fingerprint: nil, size: heavy?.count ?? 0)],
      application: nil,
      now: Date(timeIntervalSince1970: 1_700_000_300)
    )

    let collector = EventCollector()
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_300) },
      onEvent: { event in collector.append(event) }
    )

    let result = await ingestor.ingest(request)

    XCTAssertNotNil(result.event, "Heavy-text ingest should produce an event")
    XCTAssertEqual(collector.all.count, 1, "Ingest should emit exactly one event")
    // The 300 seed rows exceed the size limit; the single transaction must trim
    // back to the limit while inserting the new item (300 - evicted + 1).
    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, sizeLimit, "Ingest under load must trim to the size limit")
  }

  // MARK: - Single-transaction atomicity (behavioral proxy)

  /// Strongest feasible behavioral proxy for the single-transaction invariant.
  /// See the file header for why save-count can't be asserted directly.
  ///
  /// `BackgroundClipboardIngestor.commit` removes the duplicate from the
  /// unpinned set before applying the `limit - 1` trim, then deletes the dup,
  /// trims, and inserts the merged item all inside one `transaction { … }` plus
  /// one `save()`. This test guards that ordering specifically: the duplicate is
  /// the newer item, so that if `commit` failed to remove the dup from the
  /// unpinned count before trimming, the size-2 trim would evict the distinct
  /// older item A.
  ///
  /// Scenario with `Defaults[.size] = 2` (clock advances +10s per ingest):
  ///  - ingest distinct "A" (lastCopiedAt = base) → store [A]
  ///  - ingest distinct "B" (lastCopiedAt = base+10) → store [A, B]
  ///  - ingest a duplicate of "B" (the newer item) under a moved clock → the
  ///    actor merges (dup = B), and `commit(newItem, deleting: B, limit: 2)` must
  ///    remove B from the unpinned count before the trim.
  ///
  /// Why this makes the ordering observable — `commit` sorts unpinned by
  /// `lastCopiedAt` descending and trims the oldest tail (`dropFirst(limit - 1)`):
  ///  - Real code: unpinned = [B, A]; remove dup B first → [A], count 1;
  ///    `1 > limit-1 (1)` is false → no trim; delete B; insert mergedB. Final
  ///    store [A, mergedB], count 2, distinct A survives.
  ///  - Broken counterfactual (dup not removed before counting): unpinned = [B, A],
  ///    count 2 > 1 → `dropFirst(1)` = [A] → trim deletes distinct A; then delete
  ///    dup B and insert mergedB. Final store [mergedB], count 1, A lost.
  /// So `count == 2` and "distinct A survives" distinguish the real code from the
  /// broken one; that removal-before-count ordering is exactly what this test
  /// guards. It does not exercise every conceivable trim-ordering bug, only this
  /// specific (and spec-relevant) one.
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

  // MARK: - Per-entry containment + fingerprint-symmetry dedup

  /// Containment dedup: a plain copy whose content is a subset of an existing
  /// richer item must merge into it. This is the case the old full-table scan
  /// handled but a naive exact-match index would miss (creating a duplicate), and
  /// the reason the per-entry dedup index keys on individual content entries: the
  /// plain copy's string entry matches the richer item's string entry in the
  /// index → candidate → `supersedes` confirms (the plain signature is contained
  /// in the richer item's contents) → merge. The second type is a non-supported
  /// UTI so it survives `filterContents` regardless of the default enabled-type
  /// set, guaranteeing a true subset (not an exact duplicate).
  func testIngestSubsetOfExistingRicherItemMerges() async {
    let collector = EventCollector()
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    let foo = "foo".data(using: .utf8)
    let rich = IngestRequest(
      source: CopyOrigin(changeCount: 1, name: "test"),
      contents: [
        ContentDTO(type: stringType, value: foo, fingerprint: nil, size: 3),
        ContentDTO(type: "com.test.richmarker", value: "bar".data(using: .utf8), fingerprint: nil, size: 3)
      ],
      application: nil,
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    _ = await ingestor.ingest(rich)

    // Plain copy: string "foo" only — a strict subset of the rich item above.
    let plain = IngestRequest(
      source: CopyOrigin(changeCount: 2, name: "test"),
      contents: [ContentDTO(type: stringType, value: foo, fingerprint: nil, size: 3)],
      application: nil,
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let second = await ingestor.ingest(plain)

    XCTAssertEqual(second.metrics.dedupHits, 1, "A subset copy must merge into the richer existing item")
    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 1, "Subset copy must merge, not create a second item")
  }

  /// Fingerprint-symmetry dedup: a large (>16 KiB) re-copy must merge. The
  /// dedup signature for large content carries a real xxh3 fingerprint; the index
  /// entry (built from the existing item's contents) and the lookup entry (built
  /// from the new item's contents) must both carry the computed fingerprint to
  /// match. If the request's nil fingerprint leaked into the lookup, the entries
  /// would differ (nil != hash) and no merge would happen. `heavy_text.txt` is
  /// ~31 KB.
  func testIngestLargeTextReCopyMergesViaFingerprint() async {
    let heavy = try? Data(contentsOf: FixtureLoader.heavyTextURL)
    XCTAssertNotNil(heavy, "heavy_text.txt fixture must be present in MaccyTests/Fixtures/")
    let collector = EventCollector()
    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { event in collector.append(event) }
    )

    func heavyRequest(changeCount: Int) -> IngestRequest {
      IngestRequest(
        source: CopyOrigin(changeCount: changeCount, name: "test"),
        contents: [
          ContentDTO(type: stringType, value: heavy, fingerprint: nil, size: heavy?.count ?? 0)
        ],
        application: nil,
        now: Date(timeIntervalSince1970: 1_700_000_000)
      )
    }

    _ = await ingestor.ingest(heavyRequest(changeCount: 1))
    let second = await ingestor.ingest(heavyRequest(changeCount: 2))

    XCTAssertEqual(
      second.metrics.dedupHits, 1,
      "A large (>16 KiB) re-copy must merge via the fingerprinted signature"
    )
    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 1, "Large-text re-copy must merge, not duplicate")
    XCTAssertEqual(stored?.first?.numberOfCopies, 2)
  }

  // MARK: - Dedup-index init failure recovery

  #if DEBUG
  /// A transient failure of the dedup-index init fetch must not permanently
  /// disable dedup for the session. The index is built from rows that existed
  /// before the first ingest; if that init fetch fails, those rows stay
  /// un-indexed and a later duplicate of one of them would be missed — until
  /// the fetch recovers and the index rebuilds on a subsequent ingest.
  ///
  /// Regression guard for the silent session-wide dedup-disable: the old
  /// `ensureDedupIndexInitialized` did `(try? fetch) ?? []` and flipped
  /// `dedupIndexInitialized = true` on failure, so one transient error left the
  /// index empty for the whole process and every later copy created a new item.
  /// The fix retries on the next ingest (with backoff) instead of giving up.
  ///
  /// Scenario: pre-seed "pre" outside the ingestor; force the first ingest's
  /// init fetch to fail (so "pre" is not loaded into the index); clear the
  /// failure; re-copy "pre". On the fixed code the second ingest rebuilds the
  /// index and the duplicate merges (`dedupHits == 1`, one "pre" row); on the
  /// broken code the index never rebuilds, the duplicate misses, and a second
  /// "pre" row appears (`dedupHits == 0`).
  func testTransientInitFetchFailureDoesNotPermanentlyDisableDedup() async {
    let context = Storage.shared.context
    let pre = HistoryItem(
      contents: [HistoryItemContent(type: stringType, value: "pre".data(using: .utf8))]
    )
    pre.title = "pre"
    pre.firstCopiedAt = Date(timeIntervalSince1970: 1_700_000_000)
    pre.lastCopiedAt = pre.firstCopiedAt
    context.insert(pre)
    try? context.save()

    let ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { _ in }
    )

    // First ingest with the init fetch forced to fail: "pre" never enters the
    // index. "other" is distinct, so it inserts regardless of dedup.
    await ingestor.setDedupInitFetchFailureForTesting(true)
    _ = await ingestor.ingest(request(text: "other"))
    await ingestor.setDedupInitFetchFailureForTesting(false)

    // Re-copy "pre" now that the init fetch can succeed: the index rebuilds and
    // the duplicate must merge into the pre-seeded "pre".
    let duplicate = await ingestor.ingest(request(text: "pre"))

    XCTAssertEqual(
      duplicate.metrics.dedupHits, 1,
      "Dedup must recover after a transient init-fetch failure (silent-disable regression)"
    )
    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    let preRows = stored?.filter { $0.title == "pre" } ?? []
    XCTAssertEqual(
      preRows.count, 1,
      "The re-copy of 'pre' must merge into the pre-seeded item, not create a second 'pre' row"
    )
    XCTAssertEqual(preRows.first?.numberOfCopies, 2)
  }
  #endif

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
private final class EventCollector: Sendable {
  private let events = OSAllocatedUnfairLock(initialState: [StoreEvent]())

  func append(_ event: StoreEvent) {
    events.withLock { $0.append(event) }
  }

  var all: [StoreEvent] {
    events.withLock { $0 }
  }
}

/// Mutable test clock advanced by hand so the actor sees a moving `now` across
/// ingests in the same test.
private final class TestClock: Sendable {
  private let current = OSAllocatedUnfairLock(initialState: Date())

  init(start: Date) {
    current.withLock { $0 = start }
  }

  var now: Date {
    current.withLock { $0 }
  }

  func advance(by interval: TimeInterval) {
    current.withLock { $0 = $0.addingTimeInterval(interval) }
  }
}
