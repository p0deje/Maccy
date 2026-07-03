import Defaults
import SwiftData
import XCTest

@testable import Maccy

/// Characterization tests for the ingest dedup metrics across multiple
/// same-type large items.
///
/// `IngestResult.metrics.bytesHashed` is computed from the incoming (rhs) copy
/// only — it is the byte volume of the new item's large contents, not a measure
/// of how much the existing (lhs) items were re-hashed. So these tests
/// characterize the metric as rhs-only and confirm dedup correctness among
/// many large items. The lhs-no-rehash invariant itself — the point of the
/// persisted fingerprint column plus the lazy backfill — is covered by
/// `DataLikelyEqualContractTests` (the comparison contract) and
/// `FingerprintMigrationTests` (the column is populated for old rows).
@MainActor
final class FingerprintSymmetryTests: XCTestCase {
  /// Standard pasteboard UTI for UTF-8 plain text.
  private let stringType = "public.utf8-plain-text"
  /// At the fingerprint threshold (16 KiB).
  private let thresholdSize = 16 * 1_024

  private var savedSize = 200

  override func setUp() async throws {
    try await super.setUp()
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

  /// Ingesting a copy when many distinct large items already exist still
  /// reports `bytesHashed` equal to the copy's own large content size — it does
  /// not scale with the number of existing items — and the copy dedups against
  /// its match.
  func testBytesHashedReflectsOnlyNewContentAndDedupHitsAmongManyLargeItems() async {
    let ingestor = makeIngestor()

    // Seed several distinct large items (different byte values, same type/size).
    for index in 0..<5 {
      let payload = Data(repeating: UInt8(0x41 + index), count: thresholdSize)
      _ = await ingestor.ingest(request([content(type: stringType, value: payload)]))
    }

    // A copy of one of them must dedup, and the hashed byte volume is the
    // copy's alone, not the sum over the seeded items.
    let copy = Data(repeating: UInt8(0x41 + 2), count: thresholdSize)
    let result = await ingestor.ingest(request([content(type: stringType, value: copy)]))

    XCTAssertEqual(result.metrics.dedupHits, 1, "The copy must dedup against its match among the seeded items.")
    XCTAssertEqual(
      result.metrics.bytesHashed,
      thresholdSize,
      "bytesHashed is the incoming copy's large content size, not scaled by the lhs count."
    )
  }

  // MARK: - Helpers

  private func makeIngestor() -> BackgroundClipboardIngestor {
    BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: PassthroughImageProcessor(),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      onEvent: { _ in }
    )
  }

  private func content(type: String, value: Data) -> ContentDTO {
    ContentDTO(
      type: type,
      value: value,
      fingerprint: ClipboardDataProcessor.fingerprintIfLarge(value),
      size: value.count
    )
  }

  private func request(_ contents: [ContentDTO], changeCount: Int = 1) -> IngestRequest {
    IngestRequest(
      source: CopyOrigin(changeCount: changeCount),
      contents: contents,
      application: nil,
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }
}
