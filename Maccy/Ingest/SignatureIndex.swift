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

  func lookup(_ signature: SignatureDTO) -> ItemID? {
    idsBySignature[signature]
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
