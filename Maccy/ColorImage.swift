#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftHEXColors

class ColorImage {
  #if os(macOS)
  static func from(_ colorHex: String) -> NSImage? {
    guard let color = NSColor(hexString: colorHex) else {
      return nil
    }

    let image = NSImage(size: NSSize(width: 12, height: 12))
    image.lockFocus()
    color.drawSwatch(in: NSRect(x: 0, y: 0, width: 12, height: 12))
    image.unlockFocus()

    return image
  }
  #else
  static func from(_ colorHex: String) -> UIImage? {
    guard let color = UIColor(hexString: colorHex) else {
      return nil
    }

    let size = CGSize(width: 12, height: 12)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      color.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
  }
  #endif
}
