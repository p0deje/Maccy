import Foundation

struct SignatureIndex: Sendable {
  private var idsBySignature: [SignatureDTO: ItemID]
  private var signaturesByID: [ItemID: Set<SignatureDTO>]

  init() {
    idsBySignature = [:]
    signaturesByID = [:]
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

  mutating func register(_ signature: SignatureDTO, id: ItemID) {
    if let previousID = idsBySignature.updateValue(id, forKey: signature) {
      signaturesByID[previousID]?.remove(signature)
      if signaturesByID[previousID]?.isEmpty == true {
        signaturesByID[previousID] = nil
      }
    }

    signaturesByID[id, default: []].insert(signature)
  }

  mutating func remove(id: ItemID) {
    guard let signatures = signaturesByID.removeValue(forKey: id) else {
      return
    }

    for signature in signatures {
      idsBySignature.removeValue(forKey: signature)
    }
  }

  mutating func bulkRegister(_ entries: [(SignatureDTO, ItemID)]) {
    for (signature, id) in entries {
      register(signature, id: id)
    }
  }
}
