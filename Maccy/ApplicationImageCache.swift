class ApplicationImageCache {
  static let shared = ApplicationImageCache()

  private let universalClipboardIdentifier: String =
  "com.apple.finder.Open-iCloudDrive"
  private let fallback = ApplicationImage(bundleIdentifier: nil)
  private var cache: [String: ApplicationImage] = [:]

  func getImage(item: HistoryItem) -> ApplicationImage {
    guard let bundleIdentifier = bundleIdentifier(for: item) else {
      return fallback
    }

    if let image = cache[bundleIdentifier] {
      return image
    }

    let image = ApplicationImage(bundleIdentifier: bundleIdentifier)
    cache[bundleIdentifier] = image

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
