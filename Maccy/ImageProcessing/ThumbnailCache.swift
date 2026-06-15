import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Two-tier (memory + disk-LRU) thumbnail cache for the BS-3 image pipeline.
///
/// An `actor` (not `final class @unchecked Sendable`) because `NSCache`'s
/// internal locking only serializes its own dictionary — it does NOT serialize
/// the disk-LRU writes that this type performs. The actor gives both
/// Sendability and mutual exclusion over the disk path, consistent with the
/// BS-2 `@ModelActor` precedent.
///
/// The cache key is the composite `(MaccyFingerprint, maxPixelSize)`. A
/// fingerprint-only key would return a stale, wrong-sized thumbnail after the
/// user changes `Defaults[.imageMaxHeight]` (which triggers
/// `cleanupImages` + rebuild in `History`). `MaccyFingerprint` does not
/// encode pixel dimensions, so the size must live in the key.
actor ThumbnailCache {
  /// Soft upper bound on total on-disk thumbnail bytes before LRU eviction.
  private static let diskByteBudget: Int = 256 * 1024 * 1024

  private let memory: NSCache<ThumbnailCacheKey, NSImage> = {
    let cache = NSCache<ThumbnailCacheKey, NSImage>()
    cache.countLimit = 256
    cache.totalCostLimit = 64 * 1024 * 1024
    return cache
  }()

  private let diskDirectory: URL

  /// - Parameter diskDirectory: Where PNG thumbnails are persisted. `nil`
  ///   means the default `~/Library/Application Support/Maccy/Thumbnails/`.
  ///   Tests inject a temp directory so they never touch the runner's real
  ///   Application Support.
  init(diskDirectory: URL? = nil) {
    let resolved = diskDirectory ?? Self.defaultDirectory
    self.diskDirectory = resolved
    try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
  }

  private static var defaultDirectory: URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return support.appending(path: "Maccy", directoryHint: .isDirectory)
      .appending(path: "Thumbnails", directoryHint: .isDirectory)
  }

  /// Returns a thumbnail for `fingerprint`, building it from `data` (downsampled
  /// to `maxPixelSize`) on miss. Memory hit → disk hit → build → persist.
  func thumbnail(for fingerprint: MaccyFingerprint, data: Data, max maxPixelSize: CGFloat) async -> NSImage? {
    let key = ThumbnailCacheKey(fingerprint: fingerprint, maxPixelSize: Int(maxPixelSize))
    if let cached = memory.object(forKey: key) {
      return cached
    }

    let fileURL = diskURL(forKey: key)
    if FileManager.default.fileExists(atPath: fileURL.path),
       let image = readDisk(at: fileURL) {
      memory.setObject(image, forKey: key, cost: diskCost(image))
      return image
    }

    guard let cgImage = ImageDownsampler.thumbnail(data: data, max: maxPixelSize) else {
      return nil
    }

    writeDisk(cgImage: cgImage, to: fileURL)
    evictDiskIfNeeded()

    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    memory.setObject(image, forKey: key, cost: Int(cgImage.width) * Int(cgImage.height) * 4)
    return image
  }

  /// Removes both the memory and disk entry for `(fingerprint, maxPixelSize)`.
  func evict(fingerprint: MaccyFingerprint, max maxPixelSize: CGFloat) async {
    let key = ThumbnailCacheKey(fingerprint: fingerprint, maxPixelSize: Int(maxPixelSize))
    memory.removeObject(forKey: key)
    let url = diskURL(forKey: key)
    try? FileManager.default.removeItem(at: url)
  }

  /// Wipes the entire disk cache (for BS-6 `cleanupImages` + tests).
  func clearDisk() async {
    let urls = (try? FileManager.default.contentsOfDirectory(at: diskDirectory, includingPropertiesForKeys: nil))
      ?? []
    for url in urls {
      try? FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Disk

  private func diskURL(forKey key: ThumbnailCacheKey) -> URL {
    let name = "\(key.fingerprint.hash)-\(key.fingerprint.size)-\(key.maxPixelSize).png"
    return diskDirectory.appending(path: name)
  }

  private func readDisk(at url: URL) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return nil
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
  }

  private func writeDisk(cgImage: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    ) else { return }
    CGImageDestinationAddImage(destination, cgImage, nil)
    CGImageDestinationFinalize(destination)
  }

  /// Best-effort LRU: if the directory's total file size exceeds the budget,
  /// delete oldest-modified files until under budget. Kept simple — a directory
  /// scan per write is cheap relative to the downsample work that precedes it.
  private func evictDiskIfNeeded() {
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
    guard let entries = try? FileManager.default.contentsOfDirectory(
      at: diskDirectory,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else {
      return
    }

    var sized: [(url: URL, size: Int, mtime: Date)] = []
    var total = 0
    for url in entries {
      let values = try? url.resourceValues(forKeys: Set(keys))
      let size = values?.fileSize ?? 0
      let mtime = values?.contentModificationDate ?? Date.distantPast
      total += size
      sized.append((url, size, mtime))
    }

    guard total > Self.diskByteBudget else { return }
    sized.sort { $0.mtime < $1.mtime }
    for entry in sized {
      try? FileManager.default.removeItem(at: entry.url)
      total -= entry.size
      if total <= Self.diskByteBudget {
        return
      }
    }
  }

  private func diskCost(_ image: NSImage) -> Int {
    let pixels = image.size.width.rounded() * image.size.height.rounded()
    return Int(max(pixels, 0)) * 4
  }
}

/// `NSCache` requires `Key: NSObject & NSCopying`. A Swift struct won't work.
/// `MaccyFingerprint` is a value type, so the class holds it by value.
final class ThumbnailCacheKey: NSObject, NSCopying {
  let fingerprint: MaccyFingerprint
  let maxPixelSize: Int

  init(fingerprint: MaccyFingerprint, maxPixelSize: Int) {
    self.fingerprint = fingerprint
    self.maxPixelSize = maxPixelSize
  }

  func copy(with zone: NSZone? = nil) -> Any {
    ThumbnailCacheKey(fingerprint: fingerprint, maxPixelSize: maxPixelSize)
  }

  override var hash: Int {
    var hasher = Hasher()
    hasher.combine(fingerprint)
    hasher.combine(maxPixelSize)
    return hasher.finalize()
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? ThumbnailCacheKey else {
      return false
    }
    return fingerprint == other.fingerprint && maxPixelSize == other.maxPixelSize
  }
}
