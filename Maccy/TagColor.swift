import Defaults
import SwiftUI

enum TagColor: String, CaseIterable, Codable, Identifiable, Defaults.Serializable {
  case none
  case red
  case orange
  case yellow
  case green
  case blue
  case purple
  case gray

  var id: String { rawValue }

  var color: Color {
    switch self {
    case .none:    return .clear
    case .red:     return Color(.systemRed)
    case .orange:  return Color(.systemOrange)
    case .yellow:  return Color(.systemYellow)
    case .green:   return Color(.systemGreen)
    case .blue:    return Color(.systemBlue)
    case .purple:  return Color(.systemPurple)
    case .gray:    return Color(.systemGray)
    }
  }

  var displayName: String {
    switch self {
    case .none:    return NSLocalizedString("NoColor", tableName: "TagSettings", comment: "")
    case .red:     return NSLocalizedString("Red", tableName: "TagSettings", comment: "")
    case .orange:  return NSLocalizedString("Orange", tableName: "TagSettings", comment: "")
    case .yellow:  return NSLocalizedString("Yellow", tableName: "TagSettings", comment: "")
    case .green:   return NSLocalizedString("Green", tableName: "TagSettings", comment: "")
    case .blue:    return NSLocalizedString("Blue", tableName: "TagSettings", comment: "")
    case .purple:  return NSLocalizedString("Purple", tableName: "TagSettings", comment: "")
    case .gray:    return NSLocalizedString("Gray", tableName: "TagSettings", comment: "")
    }
  }
}
