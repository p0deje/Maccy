import AppKit.NSEvent
import Defaults
import Foundation

enum PopupPosition: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case cursor
  case statusItem
  case window
  case center
  case lastPosition

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
    case .lastPosition:
      return NSLocalizedString("PopupAtLastPosition", tableName: "AppearanceSettings", comment: "")
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  func origin(size: NSSize, statusBarButton: NSStatusBarButton?) -> NSPoint {
    switch self {
    case .center:
      if let frame = NSScreen.forPopup?.visibleFrame {
        let origin = NSRect.centered(ofSize: size, in: frame).origin
        return Self.clamp(origin, size, to: frame)
      }
    case .window:
      if let windowFrame = NSWorkspace.shared.frontmostApplication?.windowFrame {
        let origin = NSRect.centered(ofSize: size, in: windowFrame).origin
        let windowCenter = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(windowCenter) })
          ?? NSScreen.forPopup
        if let screenRect = screen?.visibleFrame {
          return Self.clamp(origin, size, to: screenRect)
        }
        return origin
      }
    case .statusItem:
      if let statusBarButton, let screen = NSScreen.main {
        let rectInWindow = statusBarButton.convert(statusBarButton.bounds, to: nil)
        if let screenRect = statusBarButton.window?.convertToScreen(rectInWindow) {
          let origin = NSPoint(x: screenRect.minX, y: screenRect.minY - size.height)
          return Self.clamp(origin, size, to: screen.visibleFrame)
        }
      }
    case .lastPosition:
      if let frame = NSScreen.forPopup?.visibleFrame {
        let relativePos = Defaults[.windowPosition]
        let anchorX = frame.minX + frame.width * relativePos.x
        let anchorY = frame.minY + frame.height * relativePos.y
        // Anchor is top middle of frame
        let origin = NSPoint(x: anchorX - size.width / 2, y: anchorY - size.height)
        return Self.clamp(origin, size, to: frame)
      }
    default:
      break
    }

    var point = NSEvent.mouseLocation
    point.y -= size.height
    if let screenRect = NSScreen.forPopup?.visibleFrame {
      return Self.clamp(point, size, to: screenRect)
    }
    return point
  }

  static func clamp(_ origin: NSPoint, _ size: NSSize, to screen: NSRect) -> NSPoint {
    var result = origin
    if result.y + size.height > screen.maxY {
      result.y = screen.maxY - size.height
    }
    if result.y < screen.minY {
      result.y = screen.minY
    }
    if result.x + size.width > screen.maxX {
      result.x = screen.maxX - size.width
    }
    if result.x < screen.minX {
      result.x = screen.minX
    }
    return result
  }
}
