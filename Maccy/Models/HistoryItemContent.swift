import CryptoKit
import Foundation
import SwiftData

@Model
class HistoryItemContent {
  var type: String = ""
  // Stored outside of SQLite so that reading `type` doesn't load the blob into memory.
  @Attribute(.externalStorage)
  var value: Data?
  // Lets duplicate detection compare contents without loading `value`.
  // SwiftData doesn't fire `didSet`, so update it whenever `value` changes.
  var digest: Data?

  @Relationship
  var item: HistoryItem?

  init(type: String, value: Data? = nil) {
    self.type = type
    self.value = value
    self.digest = value.map(Self.digest)
  }

  static func digest(_ data: Data) -> Data {
    Data(SHA256.hash(data: data))
  }

  func hasSameValue(as other: HistoryItemContent) -> Bool {
    if let digest, let otherDigest = other.digest {
      return digest == otherDigest
    }

    return value == other.value
  }
}
