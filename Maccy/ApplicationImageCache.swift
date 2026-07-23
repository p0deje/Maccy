class ApplicationImageCache {
  static let shared = ApplicationImageCache()

  private let universalClipboardIdentifier: String =
  "com.apple.finder.Open-iCloudDrive"
  private let fallback = ApplicationImage(bundleIdentifier: nil)
  private var cache: [String: ApplicationImage] = [:]
  
  // Limit cache to 100 entries to prevent unbounded memory growth
  // This is more than enough for typical application bundle identifiers
  private let maxCacheSize = 100
  
  // Track insertion order for LRU eviction
  private var cacheOrder: [String] = []

  func getImage(item: HistoryItem) -> ApplicationImage {
    guard let bundleIdentifier = bundleIdentifier(for: item) else {
      return fallback
    }

    if let image = cache[bundleIdentifier] {
      return image
    }

    let image = ApplicationImage(bundleIdentifier: bundleIdentifier)
    
    // Add to cache with LRU eviction if needed
    if cache.count >= maxCacheSize {
      // Remove least recently used (first inserted)
      if let oldestKey = cacheOrder.first {
        cache.removeValue(forKey: oldestKey)
        cacheOrder.removeFirst()
      }
    }
    
    cache[bundleIdentifier] = image
    cacheOrder.append(bundleIdentifier)

    return image
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
