import Foundation

typealias ItemID = UUID

struct ContentDTO: Equatable, Hashable, Sendable {
  let type: String
  let value: Data?
  let fingerprint: UInt64?
  let size: Int
}

struct ClipboardItemDTO: Equatable, Sendable {
  let contents: [ContentDTO]
  let application: String?
  let source: PasteboardSource
}

struct PasteboardSource: Equatable, Hashable, Sendable {
  let changeCount: Int
  let name: String?

  init(changeCount: Int, name: String? = nil) {
    self.changeCount = changeCount
    self.name = name
  }
}

struct SignatureDTO: Equatable, Hashable, Sendable {
  let entries: [ContentSignatureEntry]

  init(entries: [ContentSignatureEntry]) {
    self.entries = entries.sorted()
  }
}

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

struct MaccyFingerprint: Equatable, Hashable, Sendable {
  let size: Int
  let hash: UInt64
}

struct ItemSnapshotDTO: Equatable, Sendable {
  let id: ItemID
  let title: String
  let firstCopiedAt: Date
  let lastCopiedAt: Date
  let numberOfCopies: Int
  let pin: String?
  let application: String?
  let textPreview: String
  let imageFingerprint: UInt64?
}

enum StoreEvent: Equatable, Sendable {
  case added(ItemSnapshotDTO)
  case merged(ItemSnapshotDTO)
  case removed(ItemID)
  case cleared
}

struct IngestRequest: Equatable, Sendable {
  let source: PasteboardSource
  let contents: [ContentDTO]
  let application: String?
  let now: Date
}

enum IngestPlan: Equatable, Sendable {
  case create([ContentDTO])
  case merge(existingID: ItemID, contents: [ContentDTO])
  case ignore(IngestIgnoreReason)
}

enum IngestIgnoreReason: Equatable, Sendable {
  case empty
  case ignoredType
  case ignoredApplication
  case duplicateInFlight
}

struct IngestResult: Equatable, Sendable {
  let event: StoreEvent?
  let metrics: IngestMetrics
}

struct IngestMetrics: Equatable, Sendable {
  let dedupHits: Int
  let bytesHashed: Int
  let parseMs: Double

  static let zero = IngestMetrics(dedupHits: 0, bytesHashed: 0, parseMs: 0)
}
