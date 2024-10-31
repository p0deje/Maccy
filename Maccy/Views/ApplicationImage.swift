import SwiftUI

class ApplicationImage {
  fileprivate static let fallbackImage = NSImage(
    systemSymbolName: "questionmark.app.dashed", accessibilityDescription: nil)!
  private static let retryInterval: TimeInterval = 60 * 60

  let bundleIdentifier: String?
  private var image: NSImage?
  private var lastChecked: Date?
  private var eventSource: (any DispatchSourceFileSystemObject)?

  init(bundleIdentifier: String?, image: NSImage? = nil) {
    self.bundleIdentifier = bundleIdentifier
    self.image = image
  }

  var nsImage: NSImage {
    guard let bundleIdentifier else { return Self.fallbackImage }

    if let image { return image }

    // The image has been queried before but since the application has been deleted.
    // Check from time to time if the application has returned.
    if let lastChecked,
      Date().timeIntervalSince(lastChecked) < Self.retryInterval {
      return Self.fallbackImage
    }
    lastChecked = .now

    if let appURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: bundleIdentifier
    ) {
      let img = NSWorkspace.shared.icon(forFile: appURL.path)
      image = img

      let descriptor = open(appURL.path, O_EVTONLY)
      if descriptor == -1 {
        let errorCode = errno
        print("Error code: \(errorCode)")
        print("Error message: \(String(cString: strerror(errorCode)))")
      }
      if descriptor > 0 {
        let source = DispatchSource.makeFileSystemObjectSource(
          fileDescriptor: descriptor,
          eventMask: [.write, .delete],
          queue: DispatchQueue.global()
        )
        eventSource = source
        source.setEventHandler {
          DispatchQueue.main.async {
            let event = source.data
            if event.contains(.delete) {
              // File was deleted.
              print("Deleted", appURL.path)
              source.cancel()
              self.image = nil
            } else if event.contains(.write) {
              // File was modified. Fetch new icon
              print("Modified", appURL.path)
              self.image = NSWorkspace.shared.icon(forFile: appURL.path)
            }
          }
        }
        source.setCancelHandler {
          close(descriptor)
        }
        source.resume()
      }

      return img
    }
    return Self.fallbackImage
  }
}

class ApplicationImageCache {
  private static let universalClipboardIdentifier: String =
    "com.apple.finder.Open-iCloudDrive"
  private static let fallback = ApplicationImage(bundleIdentifier: nil)
  private var cache: [String: ApplicationImage] = [:]

  private func bundleIdentifier(for item: HistoryItem) -> String? {
    if item.universalClipboard { return Self.universalClipboardIdentifier }
    if let bundleIdentifier = item.application { return bundleIdentifier }
    return nil
  }

  func getImage(item: HistoryItem) -> ApplicationImage {
    guard let bundleIdentifier = bundleIdentifier(for: item) else {
      return Self.fallback
    }
    if let image = cache[bundleIdentifier] {
      return image
    }
    let image = ApplicationImage(bundleIdentifier: bundleIdentifier)
    cache[bundleIdentifier] = image
    return image
  }
}
