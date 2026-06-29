import AppKit.NSImage

// Based on https://stackoverflow.com/questions/73062803/resizing-nsimage-keeping-aspect-ratio-reducing-the-image-size-while-trying-to-sc.
extension NSImage {
  /// Legacy on-main resize via `NSGraphicsContext` draw, preserving aspect ratio.
  ///
  /// Retained only as the synchronous fallback for `PassthroughImageProcessor`
  /// (tests) and any path that cannot await the off-main pipeline. New image
  /// decode/downsample work should go through the off-main image downsampler,
  /// which keeps decode off the main thread and caches results; images produced
  /// there bypass this method entirely.
  func resized(to newSize: NSSize) -> NSImage {
    let ratioX = newSize.width / size.width
    let ratioY = newSize.height / size.height
    let ratio = ratioX < ratioY ? ratioX : ratioY
    let newHeight = size.height * ratio
    let newWidth = size.width * ratio
    let newSize = NSSize(width: newWidth, height: newHeight)

    // Don't attempt to size up. The previous check compared only height, which
    // skipped legitimate width-only shrinks for wide images (the width-blind
    // upscale bug); require BOTH dimensions to be already satisfied.
    if newSize.width >= size.width && newSize.height >= size.height {
      return self
    }

    return NSImage(size: newSize, flipped: false) { destRect in
      if let context = NSGraphicsContext.current {
        context.imageInterpolation = .high
        self.draw(in: destRect, from: NSRect.zero, operation: .copy, fraction: 1)
      }

      return true
    }
  }
}
