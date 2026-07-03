import Foundation
import Defaults
import SwiftData

/// A single pasteboard payload (one UTI type + its bytes) belonging to a
/// `HistoryItem`. A history item carries one `HistoryItemContent` per pasteboard
/// type it was copied with.
@Model
class HistoryItemContent {
  /// Upper bound on the byte size of a single content value, derived from the
  /// user's `maxClipboardContentSize` setting.
  static var maxValueSize: Int {
    max(
      ClipboardContentSizeLimit.minMegabytes,
      Defaults[.maxClipboardContentSize]
    ) * ClipboardContentSizeLimit.bytesPerMegabyte
  }

  var type: String = ""
  var value: Data?

  /// Persisted xxh3 fingerprint for large content (at or above the
  /// `ClipboardDataProcessor` threshold). Lets dedup read the lhs fingerprint
  /// from the column instead of re-hashing every comparison.
  ///
  /// Populated at `init` for newly inserted rows, and added as a nullable
  /// column via a lightweight SwiftData migration (no `VersionedSchema` /
  /// `SchemaMigrationPlan` needed). Rows that existed before the column was
  /// added migrate in as `nil`; the ingest actor backfills them lazily the
  /// first time they surface as a dedup candidate, so the re-hash slow path is
  /// bounded rather than permanent. `nil` for small content (below the
  /// threshold, no fingerprint stored).
  var fingerprint: UInt64?

  @Relationship
  var item: HistoryItem?

  init(type: String, value: Data? = nil) {
    self.type = type
    self.value = value
    self.fingerprint = value.flatMap(ClipboardDataProcessor.fingerprintIfLarge)
  }
}
