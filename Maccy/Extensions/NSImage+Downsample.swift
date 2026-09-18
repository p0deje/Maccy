import AppKit
import ImageIO

extension NSImage {
  nonisolated static func downsampled(
    from data: Data,
    maxPixelSize: CGFloat,
    scale: CGFloat
  ) -> NSImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize))
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }

    let size = NSSize(
      width: CGFloat(image.width) / scale,
      height: CGFloat(image.height) / scale
    )
    let downsampled = NSImage(size: size)
    downsampled.addRepresentation(NSBitmapImageRep(cgImage: image))
    return downsampled
  }

  nonisolated static func pixelSize(from data: Data) -> NSSize? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
      return nil
    }

    return NSSize(width: width.doubleValue, height: height.doubleValue)
  }
}
