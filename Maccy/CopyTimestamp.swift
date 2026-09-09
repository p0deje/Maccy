import Defaults
import Foundation

enum CopyTimestamp: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case firstCopy
  case lastCopy

  var id: Self { self }

  var description: String {
    switch self {
    case .firstCopy:
      return String(localized: "CopyTimestampFirst", table: "AppearanceSettings")
    case .lastCopy:
      return String(localized: "CopyTimestampLast", table: "AppearanceSettings")
    }
  }

  func date(for item: HistoryItem) -> Date {
    switch self {
    case .firstCopy: return item.firstCopiedAt
    case .lastCopy: return item.lastCopiedAt
    }
  }

  static func format(for date: Date, now: Date = .now, calendar: Calendar = .current) -> Date.FormatStyle {
    let time = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).hour().minute()
    return calendar.isDate(date, inSameDayAs: now) ? time : time.month(.abbreviated).day()
  }

}
