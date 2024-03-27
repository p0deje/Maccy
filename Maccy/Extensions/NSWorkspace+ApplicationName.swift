import AppKit

extension NSWorkspace {
  func applicationName(url: URL) -> String {
    if let bundle = Bundle(url: url) {
      return bundle.applicationName
    }
    return url.deletingLastPathComponent().lastPathComponent
  }
}
