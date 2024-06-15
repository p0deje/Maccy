import Foundation
import Defaults

enum PinsPosition: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case top
  case bottom

  var id: Self { self }

  var description: String {
    switch self {
    case .top:
      return NSLocalizedString("PinToTop", tableName: "AppearanceSettings", comment: "")
    case .bottom:
      return NSLocalizedString("PinToBottom", tableName: "AppearanceSettings", comment: "")
    }
  }
}
