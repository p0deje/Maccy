import AppKit

// Exists for migration. Remove in 0.11+ release.
public class HistoryItemOld: Equatable, Codable {
  public enum Types: String, Codable {
    case string
    case image
  }

  public let value: Data!
  public var firstCopiedAt: Date!
  public var lastCopiedAt: Date!
  public var numberOfCopies: Int!
  public var pin: String?
  public var type: Types!

  public static func == (lhs: HistoryItemOld, rhs: HistoryItemOld) -> Bool {
    return lhs.value == rhs.value
  }

  init(value: Data) {
    self.value = value
    self.firstCopiedAt = Date()
    self.lastCopiedAt = firstCopiedAt
    self.numberOfCopies = 1
  }

  convenience init(value: Data, firstCopiedAt: Date, lastCopiedAt: Date, numberOfCopies: Int) {
    self.init(value: value)

    self.firstCopiedAt = firstCopiedAt
    self.lastCopiedAt = lastCopiedAt
    self.numberOfCopies = numberOfCopies
  }
}
