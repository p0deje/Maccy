import Foundation

extension Bundle {
  var applicationName: String {
    if let displayName: String = object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
      return displayName
    } else if let name: String = object(forInfoDictionaryKey: "CFBundleName") as? String {
      return name
    }
    if let executableURL {
      return executableURL.deletingLastPathComponent().lastPathComponent
    }
    return ""
  }
}

