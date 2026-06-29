import Foundation
import Defaults

/// The visual style used to highlight matched search terms.
enum HighlightMatch: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case color
  case bold
  case italic
  case underline

  var id: Self { self }

  /// Localized user-facing name.
  var description: String {
    switch self {
    case .bold:
      return NSLocalizedString("HighlightMatchBold", tableName: "AppearanceSettings", comment: "")
    case .color:
      return NSLocalizedString("HighlightMatchColor", tableName: "AppearanceSettings", comment: "")
    case .italic:
      return NSLocalizedString("HighlightMatchItalic", tableName: "AppearanceSettings", comment: "")
    case .underline:
      return NSLocalizedString("HighlightMatchUnderline", tableName: "AppearanceSettings", comment: "")
    }
  }
}
