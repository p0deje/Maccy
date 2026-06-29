/// Main-actor cache of `ApplicationImage` instances keyed by bundle identifier,
/// bounded by `NSCache` so the OS can evict entries under memory pressure.
@MainActor
class ApplicationImageCache {
  static let shared = ApplicationImageCache()

  private let universalClipboardIdentifier: String =
  "com.apple.finder.Open-iCloudDrive"
  private let fallback = ApplicationImage(bundleIdentifier: nil)
  // NSCache (countLimit=128) bounds the cache so the OS evicts entries under
  // memory pressure; the evicted ApplicationImage's deinit cancels its
  // DispatchSource, closing the watched file descriptor.
  private let cache: NSCache<NSString, ApplicationImage> = {
    let cache = NSCache<NSString, ApplicationImage>()
    cache.countLimit = 128
    return cache
  }()

  /// Returns the cached `ApplicationImage` for `item`'s source application,
  /// creating and caching one on first access.
  func getImage(item: HistoryItem) -> ApplicationImage {
    guard let bundleIdentifier = bundleIdentifier(for: item) else {
      return fallback
    }

    let key = bundleIdentifier as NSString
    if let image = cache.object(forKey: key) {
      return image
    }

    let image = ApplicationImage(bundleIdentifier: bundleIdentifier)
    cache.setObject(image, forKey: key, cost: 1)

    return image
  }

  /// MemoryGovernor hook: evicts every cached entry. Each evicted
  /// `ApplicationImage`'s deinit cancels its `DispatchSource`, closing the
  /// watched file descriptor.
  func purge() {
    cache.removeAllObjects()
  }

  /// Resolves the bundle identifier used as the cache key for `item`,
  /// substituting the universal-clipboard identifier where appropriate.
  private func bundleIdentifier(for item: HistoryItem) -> String? {
    if item.universalClipboard {
      return universalClipboardIdentifier
    }

    if let bundleIdentifier = item.application {
      return bundleIdentifier
    }

    return nil
  }
}
