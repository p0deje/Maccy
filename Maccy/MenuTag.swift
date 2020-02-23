enum MenuTag: Int {
  case separator = 100
  case clear = 101
  case launchAtLogin = 102
  case about = 103
  case quit = 104
  case checkForUpdates = 105

  var string: String {
    switch self {
    case .clear:
      return "Clear"
    case .launchAtLogin:
      return "Launch at login"
    case .about:
      return "About"
    case .quit:
      return "Quit"
    case .checkForUpdates:
      return "Check for updates"
    default:
      return ""
    }
  }
}
