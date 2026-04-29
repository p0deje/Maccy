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
        return NSRect.centered(ofSize: size, in: frame).origin
      }
    case .window:
      if let frame = NSWorkspace.shared.frontmostApplication?.windowFrame {
        return NSRect.centered(ofSize: size, in: frame).origin
      }
    case .statusItem:
      return statusItemOrigin(size: size, statusBarButton: statusBarButton)
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

    var point = NSEvent.mouseLocation
    point.y -= size.height
    return point
  }

  private func statusItemOrigin(size: NSSize, statusBarButton: NSStatusBarButton?) -> NSPoint {
    let screenRect: NSRect? = if let statusBarButton,
                                 let window = statusBarButton.window {
      window.convertToScreen(statusBarButton.convert(statusBarButton.bounds, to: nil))
    } else {
      nil
    }

    let validStatusRectAndScreen: (NSRect, NSScreen)? = screenRect.flatMap { rect in
      NSScreen.screens.first { screen in
        let frame = screen.visibleFrame
        return rect.width > 0
          && rect.height > 0
          && !(abs(rect.minX) < 1 && abs(rect.minY) < 1)
          && screen.frame.intersects(rect)
          && rect.midY >= min(screen.frame.maxY, frame.maxY) - 80
      }.map { (rect, $0) }
    }

    if let (rect, screen) = validStatusRectAndScreen {
      let frame = screen.visibleFrame
      var point = NSPoint(x: rect.minX, y: rect.minY - size.height)
      point.x = min(max(point.x, frame.minX), frame.maxX - size.width)
      point.y = min(max(point.y, frame.minY), frame.maxY - size.height)
      return point
    }

    let mouseLocation = NSEvent.mouseLocation
    let mouseScreen = NSScreen.screens.first { screen in
      screen.frame.contains(mouseLocation)
    }

    guard let screen = mouseScreen
      ?? statusBarButton?.window?.screen
      ?? NSScreen.main else {
      return .zero
    }

    let frame = screen.visibleFrame
    let fallbackX = screen.frame.contains(mouseLocation)
      ? mouseLocation.x - size.width / 2
      : frame.maxX - size.width
    var topLeftPoint = NSPoint(x: fallbackX, y: frame.maxY - size.height)
    topLeftPoint.x = min(max(topLeftPoint.x, frame.minX), frame.maxX - size.width)
    topLeftPoint.y = min(max(topLeftPoint.y, frame.minY), frame.maxY - size.height)

    return topLeftPoint
  }
}
