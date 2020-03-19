import AppKit

public class HistoryItem: Equatable, Codable {
  public let value: Data!
  public var firstCopiedAt: Date!
  public var lastCopiedAt: Date!
  public var numberOfCopies: Int!
  public var pin: String?
  public var types: [NSPasteboard.PasteboardType] = []

  private enum CodingKeys: String, CodingKey {
    case value
    case firstCopiedAt
    case lastCopiedAt
    case numberOfCopies
    case pin
    case types
  }

  public static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
    return lhs.value == rhs.value
  }

  init(value: Data) {
    self.value = value
    self.firstCopiedAt = Date()
    self.lastCopiedAt = firstCopiedAt
    self.numberOfCopies = 1
  }

  public func getPasteboardType() -> NSPasteboard.PasteboardType {
    if types.contains(.tiff) { return .tiff }
    if types.contains(.png) { return .png }
    return .string
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(value, forKey: .value)
    try values.encode(firstCopiedAt, forKey: .firstCopiedAt)
    try values.encode(lastCopiedAt, forKey: .lastCopiedAt)
    try values.encode(numberOfCopies, forKey: .numberOfCopies)
    try values.encode(pin, forKey: .pin)
    try values.encode(types.map({ $0.rawValue }), forKey: .types)
  }

  public required init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    value = try values.decode(Data.self, forKey: .value)
    firstCopiedAt = try values.decode(Date.self, forKey: .firstCopiedAt)
    lastCopiedAt = try values.decode(Date.self, forKey: .lastCopiedAt)
    numberOfCopies = try values.decode(Int.self, forKey: .numberOfCopies)
    pin = try values.decodeIfPresent(String.self, forKey: .pin)
    // Backwards compatibility because migrations are executed after storage initialization
    let rawTypes = try values.decodeIfPresent([String].self, forKey: .types) ?? []
    types = rawTypes.map({ NSPasteboard.PasteboardType.init(rawValue: $0) })
  }

  convenience init(value: Data, firstCopiedAt: Date, lastCopiedAt: Date, numberOfCopies: Int) {
    self.init(value: value)

    self.firstCopiedAt = firstCopiedAt
    self.lastCopiedAt = lastCopiedAt
    self.numberOfCopies = numberOfCopies
  }
}
