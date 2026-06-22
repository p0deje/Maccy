import AppKit
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

  func constrainedSize(_ size: NSSize, statusBarButton _: NSStatusBarButton?) -> NSSize {
    guard self == .cursor, let visibleFrame = NSScreen.containing(NSEvent.mouseLocation)?.visibleFrame else {
      return size
    }

    return Self.constrainedSize(size, visibleFrame: visibleFrame)
  }

  static func constrainedSize(_ size: NSSize, visibleFrame: NSRect) -> NSSize {
    return NSSize(
      width: min(size.width, visibleFrame.width),
      height: min(size.height, visibleFrame.height)
    )
  }

  // swiftlint:disable:next cyclomatic_complexity
  func origin(size: NSSize, statusBarButton: NSStatusBarButton?) -> NSPoint {
    switch self {
    case .center:
      if let frame = NSScreen.forPopup?.visibleFrame {
        return NSRect.centered(ofSize: size, in: frame).origin
      }
    case .window:
      if let frame = NSWorkspace.shared.frontmostApplication?.windowFrame {
        return NSRect.centered(ofSize: size, in: frame).origin
      }
    case .statusItem:
      if let statusBarButton, let screen = NSScreen.main {
        let rectInWindow = statusBarButton.convert(statusBarButton.bounds, to: nil)
        if let screenRect = statusBarButton.window?.convertToScreen(rectInWindow) {
          var topLeftPoint = NSPoint(x: screenRect.minX, y: screenRect.minY - size.height)
          // Ensure that window doesn't spill over to the right screen.
          if (topLeftPoint.x + size.width) > screen.frame.maxX {
            topLeftPoint.x = screen.frame.maxX - size.width
          }

          return topLeftPoint
        }
      }
    case .lastPosition:
      if let frame = NSScreen.forPopup?.visibleFrame {
        let relativePos = Defaults[.windowPosition]
        let anchorX = frame.minX + frame.width * relativePos.x
        let anchorY = frame.minY + frame.height * relativePos.y
        // Anchor is top middle of frame
        return NSPoint(x: anchorX - size.width / 2, y: anchorY - size.height)
      }
    default:
      break
    }

    let mouseLocation = NSEvent.mouseLocation
    guard let visibleFrame = NSScreen.containing(mouseLocation)?.visibleFrame else {
      return NSPoint(x: mouseLocation.x, y: mouseLocation.y - size.height)
    }
    return Self.cursorOrigin(size: size, mouseLocation: mouseLocation, visibleFrame: visibleFrame)
  }

  static func cursorOrigin(size: NSSize, mouseLocation: NSPoint, visibleFrame: NSRect) -> NSPoint {
    let proposedFrame = NSRect(
      x: mouseLocation.x,
      y: mouseLocation.y - size.height,
      width: size.width,
      height: size.height
    )
    return proposedFrame.constrainedToFit(in: visibleFrame).origin
  }
}
