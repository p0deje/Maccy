import AppKit.NSWorkspace
import Defaults
import Foundation
import Observation
import QuickLookThumbnailing
import Sauce
import UniformTypeIdentifiers

// Simple cache for QuickLook thumbnails
private class ThumbnailCache {
  static let shared = ThumbnailCache()

  private struct CacheEntry {
    let image: NSImage
    let fileModificationDate: Date // Original modification date of the file when cached
  }

  private var lruKeys: [String] = []
  private var cacheData: [String: CacheEntry] = [:]
  private let maxCacheSize = 10 // Keep only 10 thumbnails in memory
  
  private init() {}
  
  func getThumbnail(for url: URL) -> NSImage? {
    let key = url.path
    guard let entry = cacheData[key] else { return nil }
    
    // Check if file was modified since cache
    if let currentFileModDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
       currentFileModDate <= entry.fileModificationDate {
      // Move key to the end of lruKeys (most recently used)
      lruKeys.removeAll { $0 == key }
      lruKeys.append(key)
      return entry.image
    } else {
      // File modified or unable to get modification date, invalidate cache entry
      cacheData.removeValue(forKey: key)
      lruKeys.removeAll { $0 == key }
      return nil
    }
  }
  
  func setThumbnail(_ image: NSImage, for url: URL) {
    let key = url.path
    guard let fileModDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
      // Cannot get modification date, do not cache
      return
    }
    
    // If cache is full, remove the least recently used item
    if cacheData.count >= maxCacheSize, !lruKeys.isEmpty {
      let oldestKey = lruKeys.removeFirst()
      cacheData.removeValue(forKey: oldestKey)
    }
    
    // Add new entry
    let newEntry = CacheEntry(image: image, fileModificationDate: fileModDate)
    cacheData[key] = newEntry
    
    // Remove key if it already exists (to update its position) and append to mark as most recent
    lruKeys.removeAll { $0 == key }
    lruKeys.append(key)
  }
  
  func clearCache() {
    cacheData.removeAll()
    lruKeys.removeAll()
  }
}

@Observable
class HistoryItemDecorator: Identifiable, Hashable {
  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  static var previewThrottler = Throttler(minimumDelay: Double(Defaults[.previewDelay]) / 1000)
  static var previewImageSize: NSSize { NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536) }
  static var thumbnailImageSize: NSSize { NSSize(width: 340, height: Defaults[.imageMaxHeight]) }

  let id = UUID()

  var title: String = ""
  var attributedTitle: AttributedString?

  var isVisible: Bool = true
  var isSelected: Bool = false {
    didSet {
      if isSelected {
        Self.previewThrottler.minimumDelay = Double(Defaults[.previewDelay]) / 1000 // Reset delay here
        Self.previewThrottler.throttle {
          self.showPreview = true // This will trigger showPreview.didSet
        }
      } else {
        Self.previewThrottler.cancel()
        self.showPreview = false // This will trigger showPreview.didSet
      }
    }
  }
  var shortcuts: [KeyShortcut] = []
  var showPreview: Bool = false {
    didSet {
      if showPreview {
        // Add slight delay to avoid rapid generation requests
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          guard let self = self, self.showPreview else { return }
          self.generateQuickLookThumbnail()
        }
      } else {
        // Cancel any ongoing thumbnail generation if preview is hidden
        if let request = currentThumbnailRequest {
          QLThumbnailGenerator.shared.cancel(request)
          currentThumbnailRequest = nil
        }
        self.quickLookThumbnail = nil // Actively clear thumbnail to save memory
      }
    }
  }

  var application: String? {
    if item.universalClipboard {
      return "iCloud"
    }

    guard let bundle = item.application,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
    else {
      return nil
    }

    return url.deletingPathExtension().lastPathComponent
  }

  var previewImage: NSImage?
  var thumbnailImage: NSImage?
  var fileIcon: NSImage?
  var applicationImage: ApplicationImage
  var quickLookThumbnail: NSImage? // New property for advanced previews
  private var currentThumbnailRequest: QLThumbnailGenerator.Request?


  // 10k characters seems to be more than enough on large displays
  var text: String { item.previewableText.shortened(to: 10_000) }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(title)
    hasher.combine(attributedTitle)
  }

  private(set) var item: HistoryItem

  init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
    self.item = item
    self.shortcuts = shortcuts
    self.title = item.title
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)
    
    self.fileIcon = item.fileIcon

    synchronizeItemPin()
    synchronizeItemTitle()
    // Size images immediately for better UI responsiveness
    sizeImages()
  }

  deinit {
    // Cancel any ongoing thumbnail request
    if let request = currentThumbnailRequest {
      QLThumbnailGenerator.shared.cancel(request)
    }
  }

  func sizeImages() {
    guard let image = item.image else {
      return
    }

    previewImage = image.resized(to: HistoryItemDecorator.previewImageSize)
    thumbnailImage = image.resized(to: HistoryItemDecorator.thumbnailImageSize)
  }

  func highlight(_ query: String, _ ranges: [Range<String.Index>]) {
    guard !query.isEmpty, !title.isEmpty else {
      attributedTitle = nil
      return
    }

    var attributedString = AttributedString(title.shortened(to: 500))
    for range in ranges {
      if let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString),
         let upperBound = AttributedString.Index(range.upperBound, within: attributedString) {
        switch Defaults[.highlightMatch] {
        case .bold:
          attributedString[lowerBound..<upperBound].font = .bold(.body)()
        case .italic:
          attributedString[lowerBound..<upperBound].font = .italic(.body)()
        case .underline:
          attributedString[lowerBound..<upperBound].underlineStyle = .single
        default:
          attributedString[lowerBound..<upperBound].backgroundColor = .findHighlightColor
          attributedString[lowerBound..<upperBound].foregroundColor = .black
        }
      }
    }

    attributedTitle = attributedString
  }

  @MainActor
  func togglePin() {
    if item.pin != nil {
      item.pin = nil
    } else {
      let pin = HistoryItem.randomAvailablePin
      item.pin = pin
    }
  }

  private func generateQuickLookThumbnail() {
    // Check if advanced previews are enabled
    guard Defaults[.enableAdvancedPreviews] else {
      self.quickLookThumbnail = nil
      return
    }

    // Cancel any existing request before starting a new one
    if let existingRequest = currentThumbnailRequest {
      QLThumbnailGenerator.shared.cancel(existingRequest)
      currentThumbnailRequest = nil
    }
    self.quickLookThumbnail = nil // Clear previous thumbnail immediately

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }

      guard let fileURL = self.item.fileURLs.first, self.item.image == nil else {
        DispatchQueue.main.async { [weak self] in
          self?.quickLookThumbnail = nil
        }
        return
      }

      // Check cache first
      if let cachedThumbnail = ThumbnailCache.shared.getThumbnail(for: fileURL) {
        DispatchQueue.main.async { [weak self] in
          self?.quickLookThumbnail = cachedThumbnail
        }
        return
      }

      // Use UTType for more accurate file type detection
      guard let utType = UTType(filenameExtension: fileURL.pathExtension.lowercased()),
            self.isPreviewableType(utType) else {
        DispatchQueue.main.async { [weak self] in
          self?.quickLookThumbnail = nil
        }
        return
      }

      // Larger thumbnail size for better preview visibility
      let size = CGSize(width: 600, height: 800) // Increased size for better readability
      let request = QLThumbnailGenerator.Request(
        fileAt: fileURL,
        size: size,
        scale: NSScreen.main?.backingScaleFactor ?? 1.0,
        representationTypes: .thumbnail
      )
      self.currentThumbnailRequest = request

      QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] (thumbnail, error) in
        guard let self = self else { return }
        guard self.currentThumbnailRequest == request else { return }
        self.currentThumbnailRequest = nil

        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          if let thumbnail = thumbnail {
            let image = thumbnail.nsImage
            self.quickLookThumbnail = image
            // Cache the generated thumbnail
            ThumbnailCache.shared.setThumbnail(image, for: fileURL)
          } else {
            self.quickLookThumbnail = nil
          }
        }
      }
    }
  }

  private func isPreviewableType(_ utType: UTType) -> Bool {
    return utType.conforms(to: .pdf) ||
           utType.conforms(to: .presentation) ||
           utType.conforms(to: .spreadsheet) ||
           utType.conforms(to: .text) ||
           utType.conforms(to: .rtf) ||
           utType.conforms(to: .plainText) ||
           // Check for common document formats by identifier
           utType.identifier == "org.openxmlformats.wordprocessingml.document" || // .docx
           utType.identifier == "com.microsoft.word.doc" || // .doc
           utType.identifier == "com.apple.iwork.pages.sffpages" || // .pages
           utType.identifier == "org.oasis-open.opendocument.text" // .odt
  }

  private func synchronizeItemPin() {
    _ = withObservationTracking {
      item.pin
    } onChange: {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        if let pin = self.item.pin {
          self.shortcuts = KeyShortcut.create(character: pin)
        }
        self.synchronizeItemPin()
      }
    }
  }

  private func synchronizeItemTitle() {
    _ = withObservationTracking {
      item.title
    } onChange: {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.title = self.item.title
        self.synchronizeItemTitle()
      }
    }
  }
}
