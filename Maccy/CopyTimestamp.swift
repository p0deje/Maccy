import Defaults
import Foundation

enum CopyTimestamp: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case off
  case firstCopy
  case lastCopy

  var id: Self { self }

  var description: String {
    switch self {
    case .off:
      return String(localized: "CopyTimestampOff", table: "AppearanceSettings")
    case .firstCopy:
      return String(localized: "CopyTimestampFirst", table: "AppearanceSettings")
    case .lastCopy:
      return String(localized: "CopyTimestampLast", table: "AppearanceSettings")
    }
  }

  func date(for item: HistoryItem) -> Date? {
    switch self {
    case .off: return nil
    case .firstCopy: return item.firstCopiedAt
    case .lastCopy: return item.lastCopiedAt
    }
  }
}
