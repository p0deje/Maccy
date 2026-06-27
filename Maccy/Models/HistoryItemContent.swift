import Foundation
import Defaults
import SwiftData

@Model
class HistoryItemContent {
  static var maxValueSize: Int {
    max(
      ClipboardContentSizeLimit.minMegabytes,
      Defaults[.maxClipboardContentSize]
    ) * ClipboardContentSizeLimit.bytesPerMegabyte
  }

  var type: String = ""
  var value: Data?
  /// BS-8 (08-O-007/08-F-001): persisted xxh3 fingerprint for large content
  /// (≥ `ClipboardDataProcessor` threshold). Lightweight SwiftData migration
  /// (nullable column — no `VersionedSchema`/`SchemaMigrationPlan` needed; old
  /// rows migrate as `nil`). Lets dedup read the lhs fingerprint from the column
  /// instead of re-hashing every comparison. `nil` for small content (no
  /// fingerprint) or pre-migration rows (read path falls back to a one-time
  /// re-hash via `ClipboardDataProcessor.fingerprintIfLarge`).
  var fingerprint: UInt64?

  @Relationship
  var item: HistoryItem?

  init(type: String, value: Data? = nil) {
    self.type = type
    self.value = value
    self.fingerprint = value.flatMap(ClipboardDataProcessor.fingerprintIfLarge)
  }
}
