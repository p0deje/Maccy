import Logging
import SwiftUI

/// Lazily resolves and caches the icon for a clipboard source application,
/// keeping it fresh when the bundle is deleted, renamed, or replaced.
@MainActor
class ApplicationImage {
  private static let logger = Logger(label: "org.p0deje.Maccy")
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
    // DispatchSource.cancel() is thread-safe on any thread, but `eventSource`
    // is main-isolated. Reach it from this nonisolated deinit via
    // MainActor.assumeIsolated — a synchronous runtime assertion, not an async
    // hop, so the macOS-14 restriction on actor hops from deinit does not apply.
    // Instances live in the main-only ApplicationImageCache, so deinit runs on
    // main in practice.
    MainActor.assumeIsolated {
      eventSource?.cancel()
    }
  }

  /// The resolved application icon, or the fallback image if the bundle cannot be found.
  var nsImage: NSImage {
    guard let bundleIdentifier else {
      return Self.fallbackImage
    }

    if let image {
      return image
    }

    // The bundle was not found on a previous lookup (the app may have been
    // uninstalled). Only retry after `retryInterval` so the fallback does not
    // cause repeated `NSWorkspace` lookups on every layout pass.
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
      guard descriptor != -1 else {
        let errorCode = errno
        let reason = String(cString: strerror(errorCode))
        Self.logger.error("open \(appURL.path): error \(errorCode) \(reason)")
        return img
      }
      // Defensive fd guard: ensure `descriptor` is closed if we leave scope
      // before the cancel handler is installed. `makeFileSystemObjectSource`
      // does not throw today, but a future change that fails between `open` and
      // `resume` would otherwise leak the fd. `eventSource` is assigned only
      // after the cancel handler is in place.
      var sourceInstalled = false
      defer { if !sourceInstalled { close(descriptor) } }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor,
        eventMask: [.delete, .rename],
        queue: DispatchQueue.global()
      )
      source.setEventHandler { [weak self] in
        DispatchQueue.main.async { [weak self] in
          guard let self, let eventSource = self.eventSource else {
            return
          }
          let event = eventSource.data
          if event.contains(.delete) {
            // App bundle deleted (uninstalled) — drop the cached icon.
            Self.logger.info("ApplicationImage: deleted \(appURL.path)")
            self.eventSource?.cancel()
            self.eventSource = nil
            self.image = nil
          } else if event.contains(.rename) {
            // App bundle renamed/replaced (e.g. updated) — re-fetch the icon.
            Self.logger.info("ApplicationImage: renamed \(appURL.path)")
            self.image = NSWorkspace.shared.icon(forFile: appURL.path)
          }
        }
      }
      source.setCancelHandler {
        close(descriptor)
      }
      eventSource = source
      sourceInstalled = true
      source.resume()

      return img
    }

    return Self.fallbackImage
  }
}
