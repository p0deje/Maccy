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
  /// Added as a nullable column via a lightweight SwiftData migration (no
  /// `VersionedSchema` / `SchemaMigrationPlan` needed; old rows migrate as
  /// `nil`). `nil` for small content (no fingerprint stored) or pre-migration
  /// rows. Note that the write-back backfill that would populate this column
  /// for existing rows was never implemented, so pre-migration rows stay `nil`
  /// for their lifetime and the dedup projection re-hashes them on every
  /// containment build (correct, but perpetually on the slow path).
  var fingerprint: UInt64?

  @Relationship
  var item: HistoryItem?

  init(type: String, value: Data? = nil) {
    self.type = type
    self.value = value
    self.fingerprint = value.flatMap(ClipboardDataProcessor.fingerprintIfLarge)
  }
}
