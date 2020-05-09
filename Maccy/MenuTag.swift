import Cocoa

enum MenuTag: Int {
  case separator = 100
  case clear = 101
  case launchAtLogin = 102
  case about = 103
  case quit = 104
  case checkForUpdates = 105
  case clearAll = 106

  var string: String {
    switch self {
    case .clear:
      return NSLocalizedString("clear", comment: "")
    case .clearAll:
      return NSLocalizedString("clear_all", comment: "")
    case .launchAtLogin:
      return NSLocalizedString("launch_at_login", comment: "")
    case .about:
      return NSLocalizedString("about", comment: "")
    case .quit:
      return NSLocalizedString("quit", comment: "")
    case .checkForUpdates:
      return NSLocalizedString("check_for_updates", comment: "")
    default:
      return ""
    }
  }
}
