import Defaults
import SwiftData
import XCTest

@testable import Maccy

/// Tests that the persisted fingerprint column is backfilled for rows that
/// migrated in before the column existed.
///
/// Under the test plan's `enable-testing` launch argument, `Storage.shared` is
/// an in-memory SwiftData store shared between the main context and the ingest
/// actor's isolated context. Each test seeds a row whose `fingerprint` is
/// forced back to nil — simulating a row that migrated in before the column
/// existed — then drives an ingest that surfaces it as a dedup candidate, and
/// verifies the column is populated on the actor's background context and
/// observed through the shared store.
@MainActor
final class FingerprintMigrationTests: XCTestCase {
  /// Standard pasteboard UTI for UTF-8 plain text.
  private let stringType = "public.utf8-plain-text"

  /// At the fingerprint threshold (16 KiB).
  private let thresholdSize = 16 * 1_024

  private var savedSize: Int = 200

  override func setUp() async throws {
    try await super.setUp()
    // `Storage.shared` is an in-memory singleton shared across every test in
    // this run; clear it so each test starts from a known-empty store.
    try? Storage.shared.context.delete(model: HistoryItem.self)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()

    savedSize = Defaults[.size]
    Defaults[.size] = 200
  }

  override func tearDown() async throws {
    Defaults[.size] = savedSize
    try await super.tearDown()
  }

  // MARK: - Backfill on dedup hit

  /// A pre-existing large row whose fingerprint column is nil is backfilled the
  /// first time it surfaces as a dedup candidate.
  ///
  /// The incoming copy is a superset — it carries the seeded row's large string
  /// plus a second, smaller string the seeded row lacks — so the seeded row is
  /// surfaced as a candidate (it shares the large entry) but does not supersede
  /// the copy (it cannot cover the second entry), is not deleted as the
  /// duplicate, and therefore persists with its fingerprint column populated.
  func testLargeRowWithNilFingerprintIsBackfilledWhenSurfacedAsCandidate() async {
    let largeValue = Data(repeating: 0x41, count: thresholdSize)
    let expectedFingerprint = ClipboardDataProcessor.fingerprintIfLarge(largeValue)
    seedRow(contents: [(stringType, largeValue)], forceFingerprintNil: true)

    let ingestor = makeIngestor()

    let result = await ingestor.ingest(request([
      content(type: stringType, value: largeValue),
      content(type: stringType, value: Data("extra".utf8))
    ]))

    if case .added = result.event {
      // Expected: the seeded row does not supersede the superset copy.
    } else {
      XCTFail("Expected .added, got \(String(describing: result.event))")
    }

    let seeded = seededRow(matchingValue: largeValue)
    XCTAssertNotNil(seeded, "The seeded row must persist — it was not the duplicate.")
    XCTAssertEqual(
      seeded?.contents.first?.fingerprint,
      expectedFingerprint,
      "The seeded row's nil fingerprint column must be backfilled on first dedup hit."
    )
  }

  /// Backfill is idempotent: surfacing an already-backfilled row again does not
  /// rewrite or change its fingerprint.
  func testBackfillIsIdempotentAcrossIngests() async {
    let largeValue = Data(repeating: 0x41, count: thresholdSize)
    let expectedFingerprint = ClipboardDataProcessor.fingerprintIfLarge(largeValue)
    seedRow(contents: [(stringType, largeValue)], forceFingerprintNil: true)

    let ingestor = makeIngestor()

    _ = await ingestor.ingest(request([
      content(type: stringType, value: largeValue),
      content(type: stringType, value: Data("extra-1".utf8))
    ]))
    _ = await ingestor.ingest(request([
      content(type: stringType, value: largeValue),
      content(type: stringType, value: Data("extra-2".utf8))
    ]))

    let seeded = seededRow(matchingValue: largeValue)
    XCTAssertEqual(
      seeded?.contents.first?.fingerprint,
      expectedFingerprint,
      "A second ingest that resurfaces the row must not change its fingerprint."
    )
  }

  /// Content below the fingerprint threshold is never backfilled: it has no
  /// fingerprint to store, so its column stays nil.
  func testSmallContentIsNotBackfilled() async {
    let smallValue = Data("tiny".utf8)

    seedRow(contents: [(stringType, smallValue)], forceFingerprintNil: true)

    let ingestor = makeIngestor()

    _ = await ingestor.ingest(request([
      content(type: stringType, value: smallValue),
      content(type: stringType, value: Data(repeating: 0x42, count: thresholdSize))
    ]))

    let seeded = seededRow(matchingValue: smallValue)
    XCTAssertNotNil(seeded)
    XCTAssertNil(
      seeded?.contents.first?.fingerprint,
      "Content below the fingerprint threshold must not get a fingerprint."
    )
  }

  /// A newly ingested large row has its fingerprint populated at insert time —
  /// the precondition that makes backfill necessary only for pre-migration
  /// rows.
  func testNewlyInsertedLargeRowHasFingerprint() async {
    let largeValue = Data(repeating: 0x41, count: thresholdSize)

    let ingestor = makeIngestor()

    _ = await ingestor.ingest(request([content(type: stringType, value: largeValue)]))

    let stored = try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
    XCTAssertEqual(stored?.count, 1)
    XCTAssertEqual(
      stored?.first?.contents.first?.fingerprint,
      ClipboardDataProcessor.fingerprintIfLarge(largeValue),
      "A newly inserted large row must have its fingerprint populated at init."
    )
  }

  // MARK: - Helpers

  /// Constructs the ingest actor against the shared in-memory container with a
  /// fixed clock and a no-op event sink.
  private func makeIngestor() -> BackgroundClipboardIngestor {
    BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { _ in }
    )
  }

  /// Inserts a row with the given contents directly into the shared main
  /// context, optionally forcing each content's fingerprint to nil to simulate
  /// a row that migrated in before the fingerprint column existed.
  private func seedRow(contents: [(type: String, value: Data)], forceFingerprintNil: Bool) {
    let row = HistoryItem(
      contents: contents.map { HistoryItemContent(type: $0.type, value: $0.value) }
    )
    row.firstCopiedAt = Date(timeIntervalSince1970: 1_600_000_000)
    row.lastCopiedAt = Date(timeIntervalSince1970: 1_600_000_000)
    row.title = "seed"
    Storage.shared.context.insert(row)
    if forceFingerprintNil {
      for content in row.contents {
        content.fingerprint = nil
      }
    }
    try? Storage.shared.context.save()
  }

  /// Re-fetches the seeded single-content row whose content value equals
  /// `value`, read back through the shared store so the actor's committed
  /// backfill is observed.
  private func seededRow(matchingValue value: Data) -> HistoryItem? {
    let all = (try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())) ?? []
    return all.first { row in
      row.contents.count == 1 && row.contents.first?.value == value
    }
  }

  /// Builds a `ContentDTO` with its fingerprint and size derived from the value.
  private func content(type: String, value: Data) -> ContentDTO {
    ContentDTO(
      type: type,
      value: value,
      fingerprint: ClipboardDataProcessor.fingerprintIfLarge(value),
      size: value.count
    )
  }

  /// Builds an `IngestRequest` from plain content tuples.
  private func request(_ contents: [ContentDTO], changeCount: Int = 1) -> IngestRequest {
    IngestRequest(
      source: CopyOrigin(changeCount: changeCount),
      contents: contents,
      application: nil,
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }
}
