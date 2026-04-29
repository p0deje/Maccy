class ApplicationImageCache {
  static let shared = ApplicationImageCache()
  private static let maxCachedImages = 30

  private let universalClipboardIdentifier: String =
  "com.apple.finder.Open-iCloudDrive"
  private let fallback = ApplicationImage(bundleIdentifier: nil)
  private var cache: [String: ApplicationImage] = [:]
  private var recentlyUsed: [String] = []

  func getImage(item: HistoryItem) -> ApplicationImage {
    guard let bundleIdentifier = bundleIdentifier(for: item) else {
      return fallback
    }

    if let image = cache[bundleIdentifier] {
      markUsed(bundleIdentifier)
      return image
    }

    let image = ApplicationImage(bundleIdentifier: bundleIdentifier)
    store(image, for: bundleIdentifier)

    return image
  }

  // Fast path used during decorator init: only reads the `application`
  // attribute so we don't hydrate the `contents` relationship for every item.
  func getImage(bundleIdentifier: String?) -> ApplicationImage {
    guard let bundleIdentifier else {
      return fallback
    }

    if let image = cache[bundleIdentifier] {
      markUsed(bundleIdentifier)
      return image
    }

    let image = ApplicationImage(bundleIdentifier: bundleIdentifier)
    store(image, for: bundleIdentifier)

    return image
  }

  // Drop every cached `ApplicationImage`, releasing their NSImage raster
  // caches and DispatchSource file watchers. Called from `History`'s idle
  // flush so a closed-popup process doesn't keep app icons resident forever.
  // Icons get recreated lazily next time a row asks for them.
  func clear() {
    cache.values.forEach { $0.invalidate() }
    cache.removeAll()
    recentlyUsed.removeAll()
  }

  private func store(_ image: ApplicationImage, for bundleIdentifier: String) {
    cache[bundleIdentifier] = image
    markUsed(bundleIdentifier)
    pruneIfNeeded()
  }

  private func markUsed(_ bundleIdentifier: String) {
    recentlyUsed.removeAll { $0 == bundleIdentifier }
    recentlyUsed.append(bundleIdentifier)
  }

  private func pruneIfNeeded() {
    while recentlyUsed.count > Self.maxCachedImages,
          let staleBundleIdentifier = recentlyUsed.first {
      recentlyUsed.removeFirst()
      cache.removeValue(forKey: staleBundleIdentifier)?.invalidate()
    }
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
