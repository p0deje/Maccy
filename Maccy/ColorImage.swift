import AppKit
import SwiftHEXColors

class ColorImage {
  static func from(_ colorHex: String) -> NSImage? {
    guard let color = NSColor(hexString: colorHex) else {
      return nil
    }

    let image = NSImage(size: NSSize(width: 10, height: 10))
    image.lockFocus()
    color.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
    image.unlockFocus()

    return image
  }
}
