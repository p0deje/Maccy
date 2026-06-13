import AppKit
import Defaults

enum MenuIcon: String, CaseIterable, Identifiable, Defaults.Serializable {
  case maccy
  case clipboard
  case scissors
  case paperclip

  var id: Self { self }

  var image: NSImage {
    switch self {
    case .maccy:
      return NSImage(named: .maccyStatusBar) ?? NSImage()
    case .clipboard:
      return NSImage(named: .clipboard) ?? NSImage()
    case .scissors:
      return NSImage(named: .scissors) ?? NSImage()
    case .paperclip:
      return NSImage(named: .paperclip) ?? NSImage()
    }
  }
}
