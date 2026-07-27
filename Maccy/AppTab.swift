import Foundation

enum AppTab: String, CaseIterable, Identifiable {
  case clipboard
  case todos

  var id: String { rawValue }

  var title: String {
    switch self {
    case .clipboard:
      return NSLocalizedString("ClipboardTab", tableName: "Todos", comment: "")
    case .todos:
      return NSLocalizedString("TodosTab", tableName: "Todos", comment: "")
    }
  }

  var systemImage: String {
    switch self {
    case .clipboard:
      "doc.on.clipboard"
    case .todos:
      "checklist"
    }
  }
}
