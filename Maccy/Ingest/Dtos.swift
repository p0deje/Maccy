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
  let source: CopyOrigin
}

struct CopyOrigin: Equatable, Hashable, Sendable {
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
  let signature: SignatureDTO
}

enum StoreEvent: Equatable, Sendable {
  case added(ItemSnapshotDTO)
  case merged(ItemSnapshotDTO)
  case removed(ItemID)
  case cleared
}

struct IngestRequest: Equatable, Sendable {
  let source: CopyOrigin
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

private func itemID(for item: HistoryItem) -> ItemID {
  itemID(from: String(describing: item.persistentModelID))
}

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
