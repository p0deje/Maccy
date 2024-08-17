import Foundation
import Defaults

enum HighlightMatch: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case color
  case bold
  case italic
  case underline

  var id: Self { self }

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
