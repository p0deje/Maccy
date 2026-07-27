import Foundation

enum TodoPriority: Int, CaseIterable, Codable, Identifiable {
  case none = 0
  case low = 1
  case medium = 2
  case high = 3

  var id: Int { rawValue }

  var label: String {
    switch self {
    case .none:
      return NSLocalizedString("PriorityNone", tableName: "Todos", comment: "")
    case .low:
      return NSLocalizedString("PriorityLow", tableName: "Todos", comment: "")
    case .medium:
      return NSLocalizedString("PriorityMedium", tableName: "Todos", comment: "")
    case .high:
      return NSLocalizedString("PriorityHigh", tableName: "Todos", comment: "")
    }
  }

  var systemImage: String {
    switch self {
    case .none:
      return "flag"
    case .low, .medium, .high:
      return "flag.fill"
    }
  }
}
