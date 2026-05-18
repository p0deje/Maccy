import Foundation

enum TodoReminderRepeat: String, CaseIterable, Codable {
  case none
  case once
  case hourly
  case daily
  case weekly
  case weekdays

  var isRepeating: Bool {
    switch self {
    case .none, .once:
      return false
    case .hourly, .daily, .weekly, .weekdays:
      return true
    }
  }

  init(storedValue: String?) {
    guard let storedValue, let rule = TodoReminderRepeat(rawValue: storedValue) else {
      self = .none
      return
    }
    self = rule
  }
}
