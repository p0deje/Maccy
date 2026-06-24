import Foundation

struct SignatureIndex: Sendable {
  private var idsBySignature: [SignatureDTO: ItemID]
  private var signaturesByID: [ItemID: Set<SignatureDTO>]
  /// Per-entry containment index (BS-4.2): content entry → item IDs whose signature
  /// includes it. `candidates(forEntries:)` unions an incoming copy's entries to find
  /// every item that could supersede it in O(hits), replacing the actor's old
  /// full-table fetch + O(n) `supersedes` scan. Genuinely-new content shares no entry
  /// and yields `[]` (the common case — O(1) insert with no scan). False candidates
  /// (same-(type,size) small-content collisions, fingerprint collisions) are filtered
  /// by the caller's authoritative `supersedes` confirm, so dedup correctness is
  /// unchanged — this is a candidate generator, not the decision.
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

  func lookup(_ signature: SignatureDTO) -> ItemID? {
    idsBySignature[signature]
  }

  // The snapshot is carried by .added/.merged, so we take only the event
  // (functionally identical to a roadmap-style merge(_:snapshot:) pair).
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

  func candidates(for request: IngestRequest) -> [ItemID] {
    let requestSignature = SignatureDTO(entries: request.contents.map {
      ContentSignatureEntry(type: $0.type, fingerprint: $0.fingerprint, size: $0.size)
    })
    if let itemID = idsBySignature[requestSignature] {
      return [itemID]
    }
    return []
  }

  /// Containment candidates for an incoming copy described by its content entries
  /// (BS-4.2). Returns every indexed item sharing at least one entry with the
  /// incoming copy — i.e. every item that *could* be a superset of it. A superset
  /// item shares all incoming entries (so it is in the union); an exact duplicate
  /// shares all; genuinely-new content shares none and yields `[]`. The caller
  /// confirms each candidate with the authoritative `supersedes` check (which rules
  /// out same-size and fingerprint collisions), so this generates candidates, not the
  /// final decision. Results are de-duped; order is unspecified.
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

  mutating func remove(id: ItemID) {
    if let signatures = signaturesByID.removeValue(forKey: id) {
      for signature in signatures {
        idsBySignature.removeValue(forKey: signature)
      }
    }

    // Clean per-entry membership independently of the full-signature map: an id whose
    // signatures moved away (see `register`'s `previousID` branch) still lingers here
    // and must be dropped so `candidates(forEntries:)` never surfaces stale ids.
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

  mutating func bulkRegister(_ entries: [(SignatureDTO, ItemID)]) {
    for (signature, id) in entries {
      register(signature, id: id)
    }
  }
}
