import AppKit.NSWorkspace

extension NSWorkspace {
  /// Returns the human-facing name of the app at `url`.
  ///
  /// Prefers the bundle's `CFBundleDisplayName`, then `CFBundleName`, and finally
  /// falls back to the parent directory name when the bundle can't be read.
  func applicationName(url: URL) -> String {
    if let bundle = Bundle(url: url) {
      if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
        return displayName
      } else if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
        return name
      }
    }

    return url.deletingLastPathComponent().lastPathComponent
  }
}
