import AppKit

extension NSWorkspace {
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
