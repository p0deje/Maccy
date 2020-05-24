import Cocoa

enum MenuTag: Int {
  case separator = 100
  case clear = 101
  case about = 103
  case quit = 104
  case clearAll = 106
  case preferences = 107

  var string: String {
    switch self {
    case .clear:
      return NSLocalizedString("clear", comment: "")
    case .clearAll:
      return NSLocalizedString("clear_all", comment: "")
    case .about:
      return NSLocalizedString("about", comment: "")
    case .quit:
      return NSLocalizedString("quit", comment: "")
    case .preferences:
      return NSLocalizedString("preferences", comment: "")
    default:
      return ""
    }
  }
}
