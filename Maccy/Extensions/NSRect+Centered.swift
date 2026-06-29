import Foundation

extension NSRect {
  /// Returns a rect of `size` centered within `frame` (offset by 1pt to nudge off exact center).
  static func centered(ofSize size: NSSize, in frame: NSRect) -> NSRect {
    let bottomLeftX = (frame.width - size.width) / 2 + frame.minX
    let bottomLeftY = (frame.height - size.height) / 2 + frame.minY

    return NSRect(x: bottomLeftX + 1.0, y: bottomLeftY + 1.0, width: size.width, height: size.height)
  }
}
