import CoreGraphics
import Foundation
import ImageIO

/// Pure, off-main-safe image downsample primitive built on ImageIO.
///
/// CoreGraphics only — no AppKit dependency — so it is safe to call from a
/// background actor. Used by the image pipeline (`ThumbnailCache` / the
/// `ImageProcessor` actor) to keep decode + downsample off the main thread.
enum ImageDownsampler {
  /// Produces a thumbnail `CGImage` whose longest side is ≤ `maxPixelSize`,
  /// honoring EXIF orientation.
  ///
  /// Off-main-safe (CoreGraphics only). Returns nil on corrupt, truncated, or
  /// otherwise invalid data — ImageIO's documented contract for
  /// `CGImageSourceCreateThumbnailAtIndex`.
  ///
  /// - Parameters:
  ///   - data: Raw image bytes (PNG/JPEG/TIFF/… — any `CGImageSource` format).
  ///   - max: The maximum pixel size of the thumbnail's longest side.
  /// - Returns: A downsampled `CGImage`, or nil if the data is not a valid image.
  static func thumbnail(data: Data, max maxPixelSize: CGFloat) -> CGImage? {
    // Guard against NaN/∞/non-positive: Int(maxPixelSize) traps on NaN, and a
    // non-positive thumbnail size is meaningless.
    guard maxPixelSize.isFinite, maxPixelSize > 0 else {
      return nil
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    // Bail before the thumbnail call for empty/garbage sources. Calling
    // `CGImageSourceCreateThumbnailAtIndex` on a 0-image source makes ImageIO
    // emit `*** ERROR ... failed to create thumbnail` to the console; returning
    // nil here keeps that line out of the CI log-scan gate (and is the correct
    // outcome for non-image data anyway).
    guard CGImageSourceGetCount(source) > 0 else {
      return nil
    }
    // `kCGImageSourceShouldCacheImmediately` is documented by Apple for
    // `CGImageSourceCreateImageAtIndex`, not explicitly for
    // `CreateThumbnailAtIndex`. Do NOT rely on this flag as the sole decode
    // guarantee: the off-main-decode property of the pipeline is satisfied by
    // this call running off the main thread, not by this flag.
    let options: [CFString: Any] = [
      kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }
}
