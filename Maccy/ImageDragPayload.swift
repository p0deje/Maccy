import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Owns a snapshot of the original image, never a SwiftData model or a displayed thumbnail.
final class ImageDragPayload: @unchecked Sendable {
  static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MaccyImageDrags")
  static let retentionInterval: TimeInterval = 24 * 60 * 60

  private let source: Data
  private let directory: URL
  private let filename: String
  // Shared by all drag payloads, including cleanup, to serialize cache creation and reuse.
  private static let cacheLock = NSLock()

  init(data: Data, directory: URL = ImageDragPayload.directory) {
    filename = "Image-\(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()).png"
    source = data
    self.directory = directory
  }

  func itemProvider() -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = filename
    provider.registerFileRepresentation(
      forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all
    ) { completion in
      do {
        completion(try self.fileURL(), false, nil)
      } catch {
        completion(nil, false, error)
      }
      return nil
    }
    // Native image destinations can request bytes, while browsers/editors can request a file URL.
    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
      do {
        completion(try Data(contentsOf: self.fileURL()), nil)
      } catch {
        completion(nil, error)
      }
      return nil
    }
    provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
      do {
        completion(try self.fileURL().dataRepresentation, nil)
      } catch {
        completion(nil, error)
      }
      return nil
    }
    return provider
  }

  func pasteboardItem() -> NSPasteboardItem {
    let item = NSPasteboardItem()
    // The pasteboard item retains its provider independently of the source view.
    item.setDataProvider(ImageDragDataProvider(payload: self), forTypes: [.fileURL, .png])
    return item
  }

  fileprivate func fileURL() throws -> URL {
    Self.cacheLock.lock()
    defer { Self.cacheLock.unlock() }
    let url = directory.appendingPathComponent(filename)
    if FileManager.default.fileExists(atPath: url.path) {
      // Refresh before cleanup so an older image being dragged again remains cached.
      try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
      Self.cleanupUnlocked(in: directory, now: Date())
      return url
    }

    let png = try Self.pngData(from: source)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    Self.cleanupUnlocked(in: directory, now: Date())
    try png.write(to: url, options: .atomic)
    return url
  }

  static func pngData(from data: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
      throw CocoaError(.fileReadCorruptFile)
    }
    // Preserve original PNG bytes (and resolution/transparency) without re-encoding.
    if CGImageSourceGetType(source) as String? == UTType.png.identifier {
      guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
        throw CocoaError(.fileReadCorruptFile)
      }
      return data
    }
    // Apply EXIF orientation when normalizing photos, without reducing their pixel dimensions.
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(width, height)
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return output as Data
  }

  /// Keep exports beyond the drag session: destinations may read their URLs after the popup closes.
  /// Reap day-old exports on launch and on subsequent exports, including leftovers after a crash.
  static func cleanup(in directory: URL = directory, now: Date = Date()) {
    cacheLock.lock()
    defer { cacheLock.unlock() }
    cleanupUnlocked(in: directory, now: now)
  }

  private static func cleanupUnlocked(in directory: URL, now: Date) {
    let manager = FileManager.default
    guard let files = try? manager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
    ) else { return }
    for file in files where file.lastPathComponent.hasPrefix("Image-") && file.pathExtension == "png" {
      guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
            values.isRegularFile == true,
            let modified = values.contentModificationDate,
            now.timeIntervalSince(modified) > retentionInterval else { continue }
      try? manager.removeItem(at: file)
    }
  }
}

private final class ImageDragDataProvider: NSObject, NSPasteboardItemDataProvider {
  let payload: ImageDragPayload

  init(payload: ImageDragPayload) {
    self.payload = payload
  }

  func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                  provideDataForType type: NSPasteboard.PasteboardType) {
    do {
      let url = try payload.fileURL()
      if type == .fileURL {
        item.setString(url.absoluteString, forType: type)
      } else if type == .png {
        item.setData(try Data(contentsOf: url), forType: type)
      }
    } catch {
      NSLog("Cannot export dragged image: %@", error.localizedDescription)
    }
  }
}
