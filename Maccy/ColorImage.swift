import AppKit
import SwiftHEXColors

class ColorImage {
  /// Cache of already-rendered color swatches, keyed by hex string.
  ///
  /// `from(_:)` is called from row bodies (`HistoryItemView` / `PasteStackItemView`)
  /// on every layout pass. For a color-code title the `lockFocus`/`drawSwatch`
  /// bitmap generation is the expensive part and is identical for a given hex, so
  /// cache it. Non-color titles fast-fail inside `NSColor(hexString:)` (cheap) and
  /// are NOT cached — nil isn't storable in `NSCache`, and a negative cache over
  /// arbitrary titles would grow unbounded. The deep fix (move this out of the row
  /// body onto the decorator) is 4.10d; this is the zero-risk stopgap.
  /// (render-chain S14; docs/audit/2026-06-22-render-chain-storms.md)
  private static let cache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 64
    return cache
  }()

  static func from(_ colorHex: String) -> NSImage? {
    let key = colorHex as NSString
    if let cached = cache.object(forKey: key) {
      return cached
    }

    guard let color = NSColor(hexString: colorHex) else {
      return nil
    }

    let image = NSImage(size: NSSize(width: 12, height: 12))
    image.lockFocus()
    color.drawSwatch(in: NSRect(x: 0, y: 0, width: 12, height: 12))
    image.unlockFocus()

    cache.setObject(image, forKey: key)
    return image
  }
}
