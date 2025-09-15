class ApplicationImageCache {
  static let shared = ApplicationImageCache()
  private static let universalClipboardIdentifier: String =
    "com.apple.finder.Open-iCloudDrive"

  public static let fallback = ApplicationImage(bundleIdentifier: nil)
  private var cache: [String: ApplicationImage] = [:]

  private func bundleIdentifier(for item: HistoryItem) -> String? {
    if item.universalClipboard { return Self.universalClipboardIdentifier }
    if let bundleIdentifier = item.application { return bundleIdentifier }
    return nil
  }

  private func getAppImage(bundleIdentifier: String) -> ApplicationImage {
    if let image = cache[bundleIdentifier] {
      return image
    }

    let image = ApplicationImage(bundleIdentifier: bundleIdentifier)
    cache[bundleIdentifier] = image
    return image
  }

  func getImage(item: HistoryItem) -> AppImage {
    guard let bundleIdentifier = bundleIdentifier(for: item) else {
      return Self.fallback
    }

    let appImage = getAppImage(bundleIdentifier: bundleIdentifier)

    if let originUrl = item.contextUrl
    {
      return FaviconApplicationImage(
        appImage: appImage, originUrl: originUrl)
    }

    return appImage
  }
}
