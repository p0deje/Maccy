import AppKit

public class HistoryItem: Equatable, Codable {
  public enum Types: String, Codable {
    case string
    case image
  }

  public enum ImageTypes: String, Codable {
    case png
    case tiff
  }

  public let value: Data!
  public var firstCopiedAt: Date!
  public var lastCopiedAt: Date!
  public var numberOfCopies: Int!
  public var pin: String?
  public var type: Types!
  public var imageType: ImageTypes?

  public static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
    return lhs.value == rhs.value
  }

  public func getPasteboardType() -> NSPasteboard.PasteboardType {
    if self.type == .image {
      switch self.imageType {
      case .tiff: return .tiff
      case .png: return .png
      default: return .tiff
      }
    }
    return .string
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
