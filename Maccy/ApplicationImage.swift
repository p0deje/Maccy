import Defaults
import SwiftUI

class ApplicationImage {
  fileprivate static let fallbackImage = NSImage(
    systemSymbolName: "questionmark.app.dashed",
    accessibilityDescription: nil
  ) ?? NSImage()
  private static let retryInterval: TimeInterval = 60 * 60

  let bundleIdentifier: String?
  private var image: NSImage?
  private var lastChecked: Date?
  private var eventSource: (any DispatchSourceFileSystemObject)?

  init(bundleIdentifier: String?, image: NSImage? = nil) {
    self.bundleIdentifier = bundleIdentifier
    self.image = image
  }

  deinit {
    eventSource?.cancel()
  }

  var nsImage: NSImage {
    guard let bundleIdentifier else {
      return Self.fallbackImage
    }

    if let image {
      return image
    }

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

      eventSource?.cancel()
      let descriptor = open(appURL.path, O_EVTONLY)
      if descriptor == -1 {
        let errorCode = errno
        print("Error code: \(errorCode)")
        print("Error message: \(String(cString: strerror(errorCode)))")
      } else {
        let source = DispatchSource.makeFileSystemObjectSource(
          fileDescriptor: descriptor,
          eventMask: [.write, .delete],
          queue: DispatchQueue.global()
        )
        eventSource = source
        source.setEventHandler { [weak self] in
          DispatchQueue.main.async { [weak self] in
            guard let self else {
              return
            }
            guard let eventSource = self.eventSource else {
              return
            }
            let event = eventSource.data
            if event.contains(.delete) {
              // File was deleted.
              print("Deleted", appURL.path)
              self.eventSource?.cancel()
              self.eventSource = nil
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
