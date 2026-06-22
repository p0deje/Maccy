import Foundation

extension NSRect {
  static func centered(ofSize size: NSSize, in frame: NSRect) -> NSRect {
    let bottomLeftX = (frame.width - size.width) / 2 + frame.minX
    let bottomLeftY = (frame.height - size.height) / 2 + frame.minY

    return NSRect(x: bottomLeftX + 1.0, y: bottomLeftY + 1.0, width: size.width, height: size.height)
  }

  func constrainedToFit(in frame: NSRect) -> NSRect {
    let width = min(size.width, frame.width)
    let height = min(size.height, frame.height)
    var origin = origin

    if origin.x + width > frame.maxX {
      origin.x = frame.maxX - width
    }
    if origin.x < frame.minX {
      origin.x = frame.minX
    }
    if origin.y + height > frame.maxY {
      origin.y = frame.maxY - height
    }
    if origin.y < frame.minY {
      origin.y = frame.minY
    }

    return NSRect(origin: origin, size: NSSize(width: width, height: height))
  }
}
