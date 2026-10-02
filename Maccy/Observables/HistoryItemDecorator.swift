import AppKit.NSWorkspace
import Defaults
import Foundation
import Observation
import Sauce

@Observable
class HistoryItemDecorator: Identifiable, Hashable, HasVisibility {
  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  static var previewImageSize: NSSize { NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536) }
  static var thumbnailImageSize: NSSize { NSSize(width: 340, height: Defaults[.imageMaxHeight]) }

  let id = UUID()

  var title: String = ""
  var attributedTitle: AttributedString?

  var isVisible: Bool = true
  var selectionIndex: Int = -1
  var isSelected: Bool {
    return selectionIndex != -1
  }
  var shortcuts: [KeyShortcut] = []

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

  var hasImage: Bool { item.hasImageContent }

  var previewImageGenerationTask: Task<(), Error>?
  var thumbnailImageGenerationTask: Task<(), Error>?
  var previewImage: NSImage?
  var imagePixelSize: NSSize?
  var previewText: String {
    item.previewableText
  }
  var thumbnailImage: NSImage?
  var applicationImage: ApplicationImage

  // 10k characters seems to be more than enough on large displays
  var text: String { previewText.shortened(to: 10_000) }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  func hash(into hasher: inout Hasher) {
    // We need to hash title and attributedTitle, so SwiftUI knows it needs to update the view if they chage
    hasher.combine(id)
    hasher.combine(title)
    hasher.combine(attributedTitle)
  }

  private(set) var item: HistoryItem
  
  var multiSelectionIndex: Int? {
    guard AppState.shared.navigator.isMultiSelectInProgress else {
      return nil
    }
    return selectionIndex
  }
  
  // Describe the complete item independently of its potentially truncated visual content.
  var accessibilityLabel: String {
    var parts: [String] = []
    let imageSize = imagePixelSize ?? (
      Defaults[.lowMemoryImageMode] ? nil : item.imageData.flatMap { NSImage.pixelSize(from: $0) }
    )
    if hasImage, let size = imageSize {
      parts.append(String(format: NSLocalizedString("history_item_image_accessibility_label_no_app", comment: ""), Int(size.width), Int(size.height)))
    } else {
      parts.append(title)
    }
    if let application = application {
      parts.append(application)
    }
    if isPinned {
      parts.append(NSLocalizedString("history_item_pinned_accessibility_value", comment: ""))
    }
    if let index = multiSelectionIndex {
      parts.append(String(format: NSLocalizedString("history_item_selected_accessibility_value", comment: ""), index + 1, AppState.shared.navigator.selection.count))
    }
    return parts.joined(separator: ", ")
  }

  init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
    self.item = item
    self.shortcuts = shortcuts
    self.title = item.title
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)

    synchronizeItemPin()
    synchronizeItemTitle()
  }

  @MainActor
  func ensureThumbnailImage() {
    guard hasImage else {
      return
    }
    guard thumbnailImage == nil else {
      return
    }
    guard thumbnailImageGenerationTask == nil else {
      return
    }
    if Defaults[.lowMemoryImageMode] {
      let itemID = item.persistentModelID
      let container = Storage.shared.container
      let scale = NSScreen.forPopup?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
      let targetSize = Self.thumbnailImageSize
      thumbnailImageGenerationTask = Task { @MainActor [weak self] in
        defer { self?.thumbnailImageGenerationTask = nil }
        let result: (NSImage?, NSSize?) = await Task.detached(priority: .userInitiated) {
          guard let imageData = HistoryItem.imageData(for: itemID, in: container) else {
            return (nil, nil)
          }
          let maxPixelSize = Self.maxPixelSize(for: targetSize, data: imageData, scale: scale)
          return (
            NSImage.downsampled(from: imageData, maxPixelSize: maxPixelSize, scale: scale),
            NSImage.pixelSize(from: imageData)
          )
        }.value
        guard !Task.isCancelled, let self else { return }
        if let image = result.0 {
          self.thumbnailImage = image
        } else {
          self.generateThumbnailImage()
        }
        self.imagePixelSize = result.1
      }
      return
    }

    thumbnailImageGenerationTask = Task { @MainActor [weak self] in
      defer { self?.thumbnailImageGenerationTask = nil }
      self?.generateThumbnailImage()
    }
  }

  @MainActor
  func ensurePreviewImage() {
    guard hasImage else {
      return
    }
    guard previewImage == nil else {
      return
    }
    guard previewImageGenerationTask == nil else {
      return
    }
    if Defaults[.lowMemoryImageMode] {
      let itemID = item.persistentModelID
      let container = Storage.shared.container
      let scale = NSScreen.forPopup?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
      let targetSize = Self.previewImageSize
      previewImageGenerationTask = Task { @MainActor [weak self] in
        defer { self?.previewImageGenerationTask = nil }
        let result: (NSImage?, NSSize?) = await Task.detached(priority: .userInitiated) {
          guard let imageData = HistoryItem.imageData(for: itemID, in: container) else {
            return (nil, nil)
          }
          let maxPixelSize = Self.maxPixelSize(for: targetSize, data: imageData, scale: scale)
          return (
            NSImage.downsampled(from: imageData, maxPixelSize: maxPixelSize, scale: scale),
            NSImage.pixelSize(from: imageData)
          )
        }.value
        guard !Task.isCancelled, let self else { return }
        if let image = result.0 {
          self.previewImage = image
        } else {
          self.generatePreviewImage()
        }
        self.imagePixelSize = result.1
      }
      return
    }

    previewImageGenerationTask = Task { @MainActor [weak self] in
      defer { self?.previewImageGenerationTask = nil }
      self?.generatePreviewImage()
    }
  }

  @MainActor
  func asyncGetPreviewImage() async -> NSImage? {
    if let image = previewImage {
      return image
    }
    ensurePreviewImage()
    _ = await previewImageGenerationTask?.result
    return previewImage
  }

  @MainActor
  func cleanupImages() {
    thumbnailImageGenerationTask?.cancel()
    previewImageGenerationTask?.cancel()
    thumbnailImage?.recache()
    previewImage?.recache()
    thumbnailImage = nil
    previewImage = nil
    item.clearDecodedImageCache()
  }

  @MainActor
  private func generateThumbnailImage() {
    if imagePixelSize == nil, let data = item.imageData {
      imagePixelSize = NSImage.pixelSize(from: data)
    }
    guard let image = item.image else {
      return
    }
    thumbnailImage = image.resized(to: HistoryItemDecorator.thumbnailImageSize)
  }

  @MainActor
  private func generatePreviewImage() {
    if imagePixelSize == nil, let data = item.imageData {
      imagePixelSize = NSImage.pixelSize(from: data)
    }
    guard let image = item.image else {
      return
    }
    previewImage = image.resized(to: HistoryItemDecorator.previewImageSize)
  }

  @MainActor
  func sizeImages() {
    generatePreviewImage()
    generateThumbnailImage()
  }

  nonisolated private static func maxPixelSize(for targetSize: NSSize, data: Data, scale: CGFloat) -> CGFloat {
    guard let sourceSize = NSImage.pixelSize(from: data),
          sourceSize.width > 0,
          sourceSize.height > 0 else {
      return max(targetSize.width, targetSize.height) * scale
    }

    let widthRatio = targetSize.width * scale / sourceSize.width
    let heightRatio = targetSize.height * scale / sourceSize.height
    let ratio = min(widthRatio, heightRatio)
    let sourceMax = max(sourceSize.width, sourceSize.height)
    return max(1, min(sourceMax, sourceMax * ratio))
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

  private func synchronizeItemPin() {
    _ = withObservationTracking {
      item.pin
    } onChange: { [weak self] in
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
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
    } onChange: { [weak self] in
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.title = self.item.title
        self.synchronizeItemTitle()
      }
    }
  }
}
