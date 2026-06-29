import Foundation
import SwiftData

/// Stable, value-type identifier for a history item, derived from its
/// `PersistentIdentifier` so it can be used as a dictionary key off the main actor.
typealias ItemID = UUID

/// A single, `Sendable` pasteboard content entry projected from a `HistoryItemContent`.
struct ContentDTO: Equatable, Hashable, Sendable {
  let type: String
  let value: Data?
  let fingerprint: UInt64?
  let size: Int
}

/// A `Sendable` snapshot of one clipboard copy: its content entries plus source metadata.
struct ClipboardItemDTO: Equatable, Sendable {
  let contents: [ContentDTO]
  let application: String?
  let source: CopyOrigin
}

/// Origin of a copy: its pasteboard `changeCount` plus the source app's name, if known.
struct CopyOrigin: Equatable, Hashable, Sendable {
  let changeCount: Int
  let name: String?

  init(changeCount: Int, name: String? = nil) {
    self.changeCount = changeCount
    self.name = name
  }
}

/// A history item's dedup signature: its content entries, sorted for order-independent comparison.
struct SignatureDTO: Equatable, Hashable, Sendable {
  let entries: [ContentSignatureEntry]

  init(entries: [ContentSignatureEntry]) {
    self.entries = entries.sorted()
  }
}

/// One entry of a dedup signature, identifying a single content value by type, size, and (when large enough) fingerprint.
struct ContentSignatureEntry: Comparable, Equatable, Hashable, Sendable {
  let type: String
  let fingerprint: UInt64?
  let size: Int

  static func < (lhs: ContentSignatureEntry, rhs: ContentSignatureEntry) -> Bool {
    if lhs.type != rhs.type {
      return lhs.type < rhs.type
    }

    if lhs.size != rhs.size {
      return lhs.size < rhs.size
    }

    return (lhs.fingerprint ?? 0) < (rhs.fingerprint ?? 0)
  }
}

/// An image fingerprint: its byte size plus the 64-bit content hash.
struct MaccyFingerprint: Equatable, Hashable, Sendable {
  let size: Int
  let hash: UInt64
}

/// A `Sendable` projection of a `@Model HistoryItem`.
///
/// `@Model` instances never cross an actor boundary; this value type carries the
/// fields the main-observer and the dedup index need (title, timestamps, pin,
/// preview, signature, …) plus the fetchable `persistentID` handle.
struct ItemSnapshotDTO: Equatable, Sendable {
  let id: ItemID

  /// The SwiftData fetchable handle (`ModelContext.model(for:)`). Set by
  /// `snapshot(of:)` from the `@Model`; `nil` in synthetic test snapshots, in
  /// which case the consumer falls back to a full reconcile. `PersistentIdentifier`
  /// is a `Sendable` value handle, not the `@Model` itself, so it crosses the
  /// ingest-to-main actor boundary safely.
  let persistentID: PersistentIdentifier?
  let title: String
  let firstCopiedAt: Date
  let lastCopiedAt: Date
  let numberOfCopies: Int
  let pin: String?
  let application: String?
  let textPreview: String
  let imageFingerprint: UInt64?
  let signature: SignatureDTO
}

/// A `Sendable` change notification emitted by the ingest actor and consumed by the main-observer history.
enum StoreEvent: Equatable, Sendable {
  case added(ItemSnapshotDTO)
  case merged(ItemSnapshotDTO)
  case removed(ItemID)
  case cleared
}

/// A single clipboard copy submitted to the ingest actor.
struct IngestRequest: Equatable, Sendable {
  let source: CopyOrigin
  let contents: [ContentDTO]
  let application: String?
  let now: Date
}

/// The planned disposition of an ingest, decided before writing.
enum IngestPlan: Equatable, Sendable {
  case create([ContentDTO])
  case merge(existingID: ItemID, contents: [ContentDTO])
  case ignore(IngestIgnoreReason)
}

/// Why an ingest was ignored.
enum IngestIgnoreReason: Equatable, Sendable {
  case empty
  case ignoredType
  case ignoredApplication
  case duplicateInFlight
}

/// The outcome of an ingest: the resulting `StoreEvent` (if any) plus instrumentation metrics.
struct IngestResult: Equatable, Sendable {
  let event: StoreEvent?
  let metrics: IngestMetrics
}

/// Instrumentation for one ingest: dedup candidate hits, bytes fingerprinted, and parse wall-time in milliseconds.
struct IngestMetrics: Equatable, Sendable {
  let dedupHits: Int
  let bytesHashed: Int
  let parseMs: Double

  static let zero = IngestMetrics(dedupHits: 0, bytesHashed: 0, parseMs: 0)
}

/// Projects a `@Model HistoryItem` into a `Sendable` `ItemSnapshotDTO`, computing its dedup signature and stable `ItemID`.
func snapshot(of item: HistoryItem) -> ItemSnapshotDTO {
  let signature = SignatureDTO(entries: item.contents.map { content in
    let value = content.value
    return ContentSignatureEntry(
      type: content.type,
      fingerprint: value.flatMap(ClipboardDataProcessor.fingerprintIfLarge),
      size: value?.count ?? 0
    )
  })
  return ItemSnapshotDTO(
    id: itemID(for: item),
    persistentID: item.persistentModelID,
    title: item.title,
    firstCopiedAt: item.firstCopiedAt,
    lastCopiedAt: item.lastCopiedAt,
    numberOfCopies: item.numberOfCopies,
    pin: item.pin,
    application: item.application,
    textPreview: item.previewableTextPrefix(maxLength: HistoryItem.textPreviewLimit),
    imageFingerprint: item.imageData.flatMap(ClipboardDataProcessor.fingerprintIfLarge),
    signature: signature
  )
}

/// Projects a `@Model HistoryItem`'s contents into `Sendable` `ContentDTO` values.
func contentDTOs(of item: HistoryItem) -> [ContentDTO] {
  item.contents.map { content in
    let value = content.value
    return ContentDTO(
      type: content.type,
      value: value,
      fingerprint: value.flatMap(ClipboardDataProcessor.fingerprintIfLarge),
      size: value?.count ?? 0
    )
  }
}

/// Derives the stable `ItemID` for a `@Model HistoryItem` from its `persistentModelID`.
private func itemID(for item: HistoryItem) -> ItemID {
  itemID(from: String(describing: item.persistentModelID))
}

/// Hashes a string into a deterministic `UUID` via a double FNV-1a fold over its UTF-8 bytes.
///
/// Two independent seeds are mixed over the same byte stream to widen the 64-bit
/// hash space across both halves of the resulting 128-bit UUID.
private func itemID(from string: String) -> ItemID {
  let bytes = Array(string.utf8)
  var first = UInt64(0xcbf29ce484222325)
  var second = UInt64(0x84222325cbf29ce4)

  for byte in bytes {
    first ^= UInt64(byte)
    first &*= 0x00000100000001b3

    second ^= UInt64(byte)
    second &*= 0x00000100000001b3
  }

  return UUID(uuid: (
    UInt8((first >> 56) & 0xff),
    UInt8((first >> 48) & 0xff),
    UInt8((first >> 40) & 0xff),
    UInt8((first >> 32) & 0xff),
    UInt8((first >> 24) & 0xff),
    UInt8((first >> 16) & 0xff),
    UInt8((first >> 8) & 0xff),
    UInt8(first & 0xff),
    UInt8((second >> 56) & 0xff),
    UInt8((second >> 48) & 0xff),
    UInt8((second >> 40) & 0xff),
    UInt8((second >> 32) & 0xff),
    UInt8((second >> 24) & 0xff),
    UInt8((second >> 16) & 0xff),
    UInt8((second >> 8) & 0xff),
    UInt8(second & 0xff)
  ))
}
