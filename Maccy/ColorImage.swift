import AppKit
import SwiftHEXColors

/// Renders (and caches) small color swatch images from hex color strings.
@MainActor
class ColorImage {
  /// Cache of already-rendered color swatches, keyed by hex string.
  ///
  /// `from(_:)` is called from row bodies on every layout pass. For a color-code
  /// title the bitmap generation is the expensive part and is identical for a
  /// given hex, so cache it. Non-color titles fast-fail inside
  /// `NSColor(hexString:)` (cheap) and are not cached: `nil` is not storable in
  /// `NSCache`, and a negative cache over arbitrary titles would grow unbounded.
  private static let cache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 64
    cache.totalCostLimit = 4 * 1024 * 1024
    return cache
  }()

  /// Returns a cached 12x12 swatch for `colorHex`, rendering one on first request.
  static func from(_ colorHex: String) -> NSImage? {
    let key = colorHex as NSString
    if let cached = cache.object(forKey: key) {
      return cached
    }

    guard let color = NSColor(hexString: colorHex) else {
      return nil
    }

    // NSImage(size:flipped:drawingHandler:) avoids the focus-stack bitmap
    // context that lockFocus/unlockFocus would create; the handler draws lazily.
    let size = NSSize(width: 12, height: 12)
    let image = NSImage(size: size, flipped: false) { rect in
      color.drawSwatch(in: rect)
      return true
    }

    cache.setObject(image, forKey: key, cost: Int(size.width * size.height * 4))
    return image
  }
}
