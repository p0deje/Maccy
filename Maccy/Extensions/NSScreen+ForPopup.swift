import AppKit
import Defaults

extension NSScreen {
  static var forPopup: NSScreen? {
    let desiredScreen = Defaults[.popupScreen]
    if desiredScreen == 0 || desiredScreen > NSScreen.screens.count {
      return NSScreen.main
    } else {
      return NSScreen.screens[desiredScreen - 1]
    }
  }

  static func containing(_ point: NSPoint) -> NSScreen? {
    return screens.first { $0.frame.contains(point) } ?? screens.min {
      distanceSquared(from: point, to: $0.frame) < distanceSquared(from: point, to: $1.frame)
    }
  }

  private static func distanceSquared(from point: NSPoint, to frame: NSRect) -> CGFloat {
    let deltaX = max(frame.minX - point.x, 0, point.x - frame.maxX)
    let deltaY = max(frame.minY - point.y, 0, point.y - frame.maxY)
    return deltaX * deltaX + deltaY * deltaY
  }
}
