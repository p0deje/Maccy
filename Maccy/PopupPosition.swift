import AppKit.NSEvent
import Defaults
import Foundation

enum PopupPosition: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case cursor
  case statusItem
  case window
  case center
  case spotlight

  var id: Self { self }

  var description: String {
    switch self {
    case .cursor:
      return NSLocalizedString("PopupAtCursor", tableName: "AppearanceSettings", comment: "")
    case .statusItem:
      return NSLocalizedString("PopupAtMenuBarIcon", tableName: "AppearanceSettings", comment: "")
    case .window:
      return NSLocalizedString("PopupAtWindowCenter", tableName: "AppearanceSettings", comment: "")
    case .center:
      return NSLocalizedString("PopupAtScreenCenter", tableName: "AppearanceSettings", comment: "")
    case .spotlight:
      return NSLocalizedString("PopupAtSpotlight", tableName: "AppearanceSettings", comment: "")
    }
  }

  func origin(size: NSSize, menuBarButton: NSStatusBarButton?) -> NSPoint {
    switch self {
    case .center:
      if let frame = NSScreen.forPopup?.visibleFrame {
        return NSRect.centered(ofSize: size, in: frame).origin
      }
    case .spotlight:
      if let frame = NSScreen.forPopup?.visibleFrame {
        let topPadding = frame.height * 0.2
        let bottomLeftX = frame.minX + (frame.width - size.width) / 2
        let bottomLeftY = frame.maxY - topPadding - size.height
        return NSPoint(x: bottomLeftX + 1.0, y: bottomLeftY + 1.0)
      }
    case .window:
      if let frame = NSWorkspace.shared.frontmostApplication?.windowFrame {
        return NSRect.centered(ofSize: size, in: frame).origin
      }
    case .statusItem:
      if let menuBarButton {
        let rectInWindow = menuBarButton.convert(menuBarButton.bounds, to: nil)
        if let screenRect = menuBarButton.window?.convertToScreen(rectInWindow) {
          return screenRect.origin
        }
      }
    default:
      break
    }

    var point = NSEvent.mouseLocation
    point.y = point.y - size.height
    return point
  }

}
