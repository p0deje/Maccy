import AppKit

enum PopupLocation {
  case inMenuBar
  case atMouseCursor(location: CGPoint)
  case centeredInWindow(frame: CGRect)
  case centeredInScreen(frame: CGRect)

  static var forUserDefaults: PopupLocation {
    switch UserDefaults.standard.popupPosition {
    case "center":
      if let frame = NSScreen.forPopup?.visibleFrame {
        return .centeredInScreen(frame: frame)
      }
    case "statusItem":
      return .inMenuBar
    case "window":
      if let windowFrame = NSWorkspace.shared.frontmostApplication?.windowFrame {
        return .centeredInWindow(frame: windowFrame)
      }
    default:
      break
    }
    let mouseLocation = NSEvent.mouseLocation
    return .atMouseCursor(location: mouseLocation)
  }

  var shouldAdjustHeight: Bool {
    switch self {
    case .centeredInScreen, .centeredInWindow:
      return true
    default:
      return false
    }
  }

  func location(for size: NSSize) -> NSPoint? {
    switch self {
    case .inMenuBar:
      return nil
    case let .atMouseCursor(location):
      return location
    case let .centeredInWindow(frame):
      return NSRect.centered(ofSize: size, in: frame).origin
    case let .centeredInScreen(frame):
      return NSRect.centered(ofSize: size, in: frame).origin
    }
  }
}
