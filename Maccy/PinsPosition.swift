import Foundation
import Defaults

/// Where pinned items appear in the history list.
enum PinsPosition: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case top
  case bottom

  var id: Self { self }

  /// The localized, user-facing name of this position.
  var description: String {
    switch self {
    case .top:
      return NSLocalizedString("PinToTop", tableName: "AppearanceSettings", comment: "")
    case .bottom:
      return NSLocalizedString("PinToBottom", tableName: "AppearanceSettings", comment: "")
    }
  }
}
