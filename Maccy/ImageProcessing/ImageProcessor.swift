import AppKit
import CoreGraphics
import Foundation

/// Production `ImageProcessing` conformance for the off-main image pipeline.
///
/// A background `actor` (satisfies the protocol's `Sendable` requirement) that
/// keeps all image decode + downsample work off the main thread. It composes
/// two primitives:
///
/// - `thumbnail(for:max:)` is cache-backed (`ThumbnailCache`): the memory +
///   disk-LRU tiers make repeated renders of the same item cheap. The cache is
///   keyed by `(MaccyFingerprint, maxPixelSize)`, so this method computes a
///   fingerprint from the raw image `Data` before delegating.
/// - `preview(for:max:)` is transient: previews are short-lived and sized by
///   the caller, so they bypass the cache and downsample directly via
///   `ImageDownsampler`.
///
/// Both methods begin with a `Task.isCancelled` checkpoint so a render that is
/// superseded (the caller cancels its parent task) returns nil at the actor
/// boundary before any decode or disk work. `preview` adds a second checkpoint
/// between the downsample and the cheap `NSImage` wrap so a cancellation that
/// lands during decode still short-circuits.
actor ImageProcessor: ImageProcessing {
  private let cache: ThumbnailCache

  init(cache: ThumbnailCache) {
    self.cache = cache
  }

  /// Builds (or fetches) a cached thumbnail whose longest side is ≤ the larger
  /// of `size.width` / `size.height`. Returns nil if `data` is not a valid
  /// image or the task has been cancelled.
  func thumbnail(for data: Data, max size: CGSize) async -> NSImage? {
    if Task.isCancelled {
      return nil
    }
    let maxPixel = max(size.width, size.height)
    let fingerprint = MaccyFingerprint(size: data.count, hash: MaccyTextProcessor.fingerprint(for: data))
    return await cache.thumbnail(for: fingerprint, data: data, max: maxPixel)
  }

  /// Builds a transient preview whose longest side is ≤ the larger of
  /// `size.width` / `size.height`. Not cached. Returns nil if `data` is not a
  /// valid image or the task has been cancelled.
  func preview(for data: Data, max size: CGSize) async -> NSImage? {
    if Task.isCancelled {
      return nil
    }
    let maxPixel = max(size.width, size.height)
    guard let downsampled = ImageDownsampler.thumbnail(data: data, max: maxPixel) else {
      return nil
    }
    if Task.isCancelled {
      return nil
    }
    return NSImage(cgImage: downsampled, size: NSSize(width: downsampled.width, height: downsampled.height))
  }
}
