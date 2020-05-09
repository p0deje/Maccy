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
      return NSLocalizedString("Clear", comment: "")
    case .clearAll:
      return NSLocalizedString("Clear all", comment: "")
    case .launchAtLogin:
      return NSLocalizedString("Launch at login", comment: "")
    case .about:
      return NSLocalizedString("About", comment: "")
    case .quit:
      return NSLocalizedString("Quit", comment: "")
    case .checkForUpdates:
      return NSLocalizedString("Check for updates", comment: "")
    default:
      return ""
    }
  }
}
