import AppKit

// Based on https://stackoverflow.com/questions/73062803/resizing-nsimage-keeping-aspect-ratio-reducing-the-image-size-while-trying-to-sc.
extension NSImage {
  /// Returns the pixel dimensions of the image.
  /// On Retina displays, this differs from `size` which returns logical points.
  var pixelSize: NSSize {
    if let bitmapRep = representations.first(where: { $0 is NSBitmapImageRep }) as? NSBitmapImageRep {
      return NSSize(width: CGFloat(bitmapRep.pixelsWide), height: CGFloat(bitmapRep.pixelsHigh))
    }
    // Fallback to logical size if no bitmap representation is available
    return size
  }

  // Render at the backing scale factor of the screen so that resized
  // images stay sharp on Retina displays.
  private static var renderScale: CGFloat {
    NSScreen.forPopup?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
  }

  // Must be called on the main thread.
  //
  // Rasterizes the result into a standalone bitmap. Unlike
  // `NSImage(size:flipped:drawingHandler:)`, the returned image does NOT
  // retain the original (potentially huge) image, so evicting the resized
  // image from a cache actually frees its memory.
  func resized(to newSize: NSSize) -> NSImage {
    let ratioX = newSize.width / size.width
    let ratioY = newSize.height / size.height
    let ratio = ratioX < ratioY ? ratioX : ratioY
    let newHeight = size.height * ratio
    let newWidth = size.width * ratio
    let newSize = NSSize(width: newWidth, height: newHeight)

    // Don't attempt to size up.
    if newSize.height >= size.height {
      return self
    }

    let scale = NSImage.renderScale
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(newWidth * scale),
      pixelsHigh: Int(newHeight * scale),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      return self
    }
    // Set the size in points so the rep is treated as high-resolution
    // instead of a larger image.
    rep.size = newSize

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)
    context?.imageInterpolation = .high
    NSGraphicsContext.current = context
    draw(in: NSRect(origin: .zero, size: newSize), from: NSRect.zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    let resized = NSImage(size: newSize)
    resized.addRepresentation(rep)
    return resized
  }
}
