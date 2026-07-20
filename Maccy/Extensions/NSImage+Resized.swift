import AppKit.NSImage

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

    // HiDPI: bake at the highest active backing scale so the cached bitmap
    // stays sharp on any display the popup is dragged to.
    let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2.0
    let pixelsWide = Int((newWidth * scale).rounded())
    let pixelsHigh = Int((newHeight * scale).rounded())

    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
      bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0
    ) else {
      return self
    }
    rep.size = newSize

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
      return self
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    draw(
      in: NSRect(origin: .zero, size: newSize),
      from: .zero, operation: .copy, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    let baked = NSImage(size: newSize)
    baked.addRepresentation(rep)
    return baked
  }
}
