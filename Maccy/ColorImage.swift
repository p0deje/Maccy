import AppKit
import SwiftHEXColors

@MainActor
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
    cache.totalCostLimit = 4 * 1024 * 1024
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

    // IMG-029: NSImage(size:flipped:drawingHandler:) replaces lockFocus/unlockFocus
    // (avoids the focus-stack bitmap context; draws lazily).
    let size = NSSize(width: 12, height: 12)
    let image = NSImage(size: size, flipped: false) { rect in
      color.drawSwatch(in: rect)
      return true
    }

    cache.setObject(image, forKey: key, cost: Int(size.width * size.height * 4))
    return image
  }
}
