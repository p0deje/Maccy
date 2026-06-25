@MainActor
class ApplicationImageCache {
  static let shared = ApplicationImageCache()

  private let universalClipboardIdentifier: String =
  "com.apple.finder.Open-iCloudDrive"
  private let fallback = ApplicationImage(bundleIdentifier: nil)
  // M4 (master plan): NSCache (countLimit=128) replaces the unbounded Dict so the
  // OS evicts under pressure; ApplicationImage.deinit cancels its DispatchSource
  // (closing the watched fd). Closes appicon-cache-unbounded (05/13).
  private let cache: NSCache<NSString, ApplicationImage> = {
    let cache = NSCache<NSString, ApplicationImage>()
    cache.countLimit = 128
    return cache
  }()

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

  /// MemoryGovernor hook: evict everything. Each `ApplicationImage.deinit`
  /// cancels its `DispatchSource` (closing the watched fd).
  func purge() {
    cache.removeAllObjects()
  }

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
