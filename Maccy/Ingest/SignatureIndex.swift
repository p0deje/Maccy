import Foundation

/// In-memory dedup index over every committed history item's content signature.
///
/// Maintains four maps: full signature → id, id → signatures, content entry → ids,
/// and id → entries. The per-entry map lets `candidates(forEntries:)` find every
/// item that could supersede an incoming copy in O(hits), instead of a full-table
/// fetch plus an O(n) `supersedes` scan.
struct SignatureIndex: Sendable {
  private var idsBySignature: [SignatureDTO: ItemID]
  private var signaturesByID: [ItemID: Set<SignatureDTO>]

  /// Per-entry containment index: a content entry → item IDs whose signature
  /// includes it.
  ///
  /// `candidates(forEntries:)` unions an incoming copy's entries to find every
  /// item that could supersede it in O(hits). Genuinely-new content shares no
  /// entry and yields `[]` (the common case — O(1) insert with no scan). False
  /// candidates (same-(type,size) small-content collisions, fingerprint
  /// collisions) are filtered by the caller's authoritative `supersedes` confirm,
  /// so dedup correctness is unchanged — this is a candidate generator, not the
  /// decision.
  private var idsByEntry: [ContentSignatureEntry: Set<ItemID>]
  private var entriesByID: [ItemID: Set<ContentSignatureEntry>]

  init() {
    idsBySignature = [:]
    signaturesByID = [:]
    idsByEntry = [:]
    entriesByID = [:]
  }

  init(_ entries: [(SignatureDTO, ItemID)]) {
    self.init()
    bulkRegister(entries)
  }

  init(from snapshots: [ItemSnapshotDTO]) {
    self.init()
    for snapshot in snapshots {
      register(snapshot.signature, id: snapshot.id)
    }
  }

  /// Returns the id of the item with an exact-signature match, if any.
  func lookup(_ signature: SignatureDTO) -> ItemID? {
    idsBySignature[signature]
  }

  /// Applies a `StoreEvent` to keep the index in sync with the committed store.
  ///
  /// `.added`/`.merged` register the carried snapshot; `.removed` drops the id;
  /// `.cleared` resets the index. The snapshot is carried by the event, so no
  /// separate snapshot parameter is needed.
  mutating func merge(_ event: StoreEvent) {
    switch event {
    case .added(let snapshot), .merged(let snapshot):
      register(snapshot.signature, id: snapshot.id)
    case .removed(let itemID):
      remove(id: itemID)
    case .cleared:
      self = SignatureIndex()
    }
  }

  /// Returns the exact-signature match for an ingest request, if any.
  func candidates(for request: IngestRequest) -> [ItemID] {
    let requestSignature = SignatureDTO(entries: request.contents.map {
      ContentSignatureEntry(type: $0.type, fingerprint: $0.fingerprint, size: $0.size)
    })
    if let itemID = idsBySignature[requestSignature] {
      return [itemID]
    }
    return []
  }

  /// Containment candidates for an incoming copy described by its content entries.
  ///
  /// Returns every indexed item sharing at least one entry with the incoming
  /// copy — i.e. every item that could be a superset of it. A superset item
  /// shares all incoming entries (so it is in the union); an exact duplicate
  /// shares all; genuinely-new content shares none and yields `[]`. The caller
  /// confirms each candidate with the authoritative `supersedes` check (which
  /// rules out same-size and fingerprint collisions), so this generates
  /// candidates, not the final decision. Results are de-duped; order is unspecified.
  func candidates(forEntries entries: [ContentSignatureEntry]) -> [ItemID] {
    var seen = Set<ItemID>()
    var result: [ItemID] = []
    for entry in entries {
      guard let ids = idsByEntry[entry] else { continue }
      for id in ids where !seen.contains(id) {
        seen.insert(id)
        result.append(id)
      }
    }
    return result
  }

  /// Registers a signature for `id`, replacing any previous id bound to that signature.
  mutating func register(_ signature: SignatureDTO, id: ItemID) {
    if let previousID = idsBySignature.updateValue(id, forKey: signature) {
      signaturesByID[previousID]?.remove(signature)
      if signaturesByID[previousID]?.isEmpty == true {
        signaturesByID[previousID] = nil
      }
    }

    signaturesByID[id, default: []].insert(signature)

    for entry in signature.entries {
      idsByEntry[entry, default: []].insert(id)
    }
    entriesByID[id, default: []].formUnion(signature.entries)
  }

  /// Removes `id` and all of its signatures and entries from the index.
  mutating func remove(id: ItemID) {
    if let signatures = signaturesByID.removeValue(forKey: id) {
      for signature in signatures {
        idsBySignature.removeValue(forKey: signature)
      }
    }

    // Clean per-entry membership independently of the full-signature map: an id
    // whose signatures moved away (see `register`'s `previousID` branch) still
    // lingers here and must be dropped so `candidates(forEntries:)` never
    // surfaces stale ids.
    if let entries = entriesByID.removeValue(forKey: id) {
      for entry in entries {
        if idsByEntry[entry]?.count == 1 {
          idsByEntry[entry] = nil
        } else {
          idsByEntry[entry]?.remove(id)
        }
      }
    }
  }

  /// Registers many `(signature, id)` pairs at once.
  mutating func bulkRegister(_ entries: [(SignatureDTO, ItemID)]) {
    for (signature, id) in entries {
      register(signature, id: id)
    }
  }
}
