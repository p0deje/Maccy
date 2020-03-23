import AppKit

public class HistoryItem: Equatable, Codable {
  @available(*, deprecated, message: "Use typesWithData to control HistoryItem values")
  public var value: Data?
  public var firstCopiedAt: Date!
  public var lastCopiedAt: Date!
  public var numberOfCopies: Int!
  public var pin: String?
  public var typesWithData: [NSPasteboard.PasteboardType: Data] = [:]

  private enum CodingKeys: String, CodingKey {
    case value
    case firstCopiedAt
    case lastCopiedAt
    case numberOfCopies
    case pin
    case typesWithData
  }

  public static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
    lhs.typesWithData == rhs.typesWithData
  }

  init(typesWithData: [NSPasteboard.PasteboardType: Data]) {
    self.typesWithData = typesWithData
    self.firstCopiedAt = Date()
    self.lastCopiedAt = firstCopiedAt
    self.numberOfCopies = 1
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encodeIfPresent(value, forKey: .value)
    try values.encode(firstCopiedAt, forKey: .firstCopiedAt)
    try values.encode(lastCopiedAt, forKey: .lastCopiedAt)
    try values.encode(numberOfCopies, forKey: .numberOfCopies)
    try values.encode(pin, forKey: .pin)
    var rawTypeWithData: [String: Data] = [:]
    for (type, data) in typesWithData {
      rawTypeWithData[type.rawValue] = data
    }
    try values.encode(rawTypeWithData, forKey: .typesWithData)
  }

  public required init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    value = try values.decodeIfPresent(Data.self, forKey: .value)
    firstCopiedAt = try values.decode(Date.self, forKey: .firstCopiedAt)
    lastCopiedAt = try values.decode(Date.self, forKey: .lastCopiedAt)
    numberOfCopies = try values.decode(Int.self, forKey: .numberOfCopies)
    pin = try values.decodeIfPresent(String.self, forKey: .pin)
    // Backwards compatibility because migrations are executed after storage initialization
    let rawTypes: [String: Data] = try values.decodeIfPresent([String: Data].self, forKey: .typesWithData) ?? [:]
    for (rawType, data) in rawTypes {
      typesWithData[NSPasteboard.PasteboardType.init(rawValue: rawType)] = data
    }
  }

  convenience init(typesWithData: [NSPasteboard.PasteboardType: Data], firstCopiedAt: Date, lastCopiedAt: Date, numberOfCopies: Int) {
    self.init(typesWithData: typesWithData)

    self.firstCopiedAt = firstCopiedAt
    self.lastCopiedAt = lastCopiedAt
    self.numberOfCopies = numberOfCopies
  }
}
