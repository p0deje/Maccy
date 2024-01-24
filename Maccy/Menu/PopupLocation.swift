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

  func location(for size: NSSize) -> NSPoint? {
    switch self {
    case .inMenuBar:
      return nil
    case let .atMouseCursor(location):
      if let frame = NSScreen.forPopup?.visibleFrame {
        return clamp(location, size, to: frame)
      }
      return location
    case let .centeredInWindow(frame):
      return NSRect.centered(ofSize: size, in: frame).origin
    case let .centeredInScreen(frame):
      return NSRect.centered(ofSize: size, in: frame).origin
    }
  }

  func clamp(_ pos: NSPoint, _ size: NSSize, to screenRect: NSRect) -> NSPoint {
    var result = pos
    if result.y > screenRect.maxY {
      result.y -= result.y - screenRect.maxY
    }
    let bottomY = result.y - size.height
    if bottomY < screenRect.minY {
      result.y += screenRect.minY - bottomY
    }
    let rightX = result.x + size.width
    if rightX > screenRect.maxX {
      result.x -= size.width
    }
    return result
  }
}
