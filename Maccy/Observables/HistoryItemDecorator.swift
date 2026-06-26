import AppKit.NSWorkspace
import Defaults
import Foundation
import Observation
import Sauce

private actor ImageGenerationQueue {
  static let previews = ImageGenerationQueue()
  static let thumbnails = ImageGenerationQueue()

  func resizedImage(data: Data, targetSize: NSSize) -> NSImage? {
    guard !Task.isCancelled else { return nil }
    guard let nsImage = NSImage(data: data) else { return nil }
    guard !Task.isCancelled else { return nil }

    let resized = nsImage.resized(to: targetSize)
    guard !Task.isCancelled else { return nil }

    return resized
  }
}

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

  var hasImage: Bool { item.hasStoredImageData }

  @ObservationIgnored var previewImageGenerationTask: Task<Void, Never>?
  @ObservationIgnored var thumbnailImageGenerationTask: Task<Void, Never>?
  @ObservationIgnored private var previewImageGenerationID: UUID?
  @ObservationIgnored private var thumbnailImageGenerationID: UUID?
  var previewImage: NSImage?
  var thumbnailImage: NSImage?
  var accessoryImage: NSImage?
  var applicationImage: ApplicationImage

  // 10k characters seems to be more than enough on large displays
  var text: String { item.previewableText.shortened(to: 10_000) }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  func hash(into hasher: inout Hasher) {
    // Keep mutated titles visible in SwiftUI after pasteboard content is normalized.
    hasher.combine(id)
    hasher.combine(title)
    hasher.combine(attributedTitle)
  }

  private(set) var item: HistoryItem

  init(_ item: HistoryItem, shortcuts: [KeyShortcut] = []) {
    self.item = item
    self.shortcuts = shortcuts
    self.title = item.title
    self.accessoryImage = ColorImage.from(item.title)
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)

    synchronizeItemPin()
    synchronizeItemTitle()
  }

  @MainActor
  func ensureThumbnailImage() {
    guard let data = item.storedImageData else {
      return
    }
    guard thumbnailImage == nil else {
      return
    }
    guard thumbnailImageGenerationTask == nil else {
      return
    }
    let targetSize = HistoryItemDecorator.thumbnailImageSize
    let generationID = UUID()
    thumbnailImageGenerationID = generationID
    thumbnailImageGenerationTask = Task.detached(priority: .utility) { [weak self] in
      let resized = await ImageGenerationQueue.thumbnails.resizedImage(data: data, targetSize: targetSize)
      let shouldApply = !Task.isCancelled
      await MainActor.run {
        guard let self, self.thumbnailImageGenerationID == generationID else { return }

        self.thumbnailImageGenerationTask = nil
        self.thumbnailImageGenerationID = nil

        guard shouldApply, let resized else { return }
        self.thumbnailImage = resized
      }
    }
  }

  @MainActor
  func ensurePreviewImage() {
    guard let data = item.storedImageData else {
      return
    }
    guard previewImage == nil else {
      return
    }
    guard previewImageGenerationTask == nil else {
      return
    }
    let targetSize = HistoryItemDecorator.previewImageSize
    let generationID = UUID()
    previewImageGenerationID = generationID
    previewImageGenerationTask = Task.detached(priority: .userInitiated) { [weak self] in
      let resized = await ImageGenerationQueue.previews.resizedImage(data: data, targetSize: targetSize)
      let shouldApply = !Task.isCancelled
      await MainActor.run {
        guard let self, self.previewImageGenerationID == generationID else { return }

        self.previewImageGenerationTask = nil
        self.previewImageGenerationID = nil

        guard shouldApply, let resized else { return }
        self.previewImage = resized
      }
    }
  }

  @MainActor
  func asyncGetPreviewImage() async -> NSImage? {
    if let image = previewImage {
      return image
    }
    ensurePreviewImage()
    await previewImageGenerationTask?.value
    return previewImage
  }

  @MainActor
  func cleanupImages() {
    thumbnailImageGenerationTask?.cancel()
    previewImageGenerationTask?.cancel()
    thumbnailImageGenerationTask = nil
    previewImageGenerationTask = nil
    thumbnailImageGenerationID = nil
    previewImageGenerationID = nil
    thumbnailImage?.recache()
    previewImage?.recache()
    thumbnailImage = nil
    previewImage = nil
  }

  @MainActor
  func cancelThumbnailImageGeneration() {
    guard thumbnailImage == nil else { return }
    thumbnailImageGenerationTask?.cancel()
    thumbnailImageGenerationTask = nil
    thumbnailImageGenerationID = nil
  }

  @MainActor
  func cancelPreviewImageGeneration() {
    guard previewImage == nil else { return }
    previewImageGenerationTask?.cancel()
    previewImageGenerationTask = nil
    previewImageGenerationID = nil
  }

  @MainActor
  func sizeImages() {
    ensurePreviewImage()
    ensureThumbnailImage()
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
    } onChange: {
      DispatchQueue.main.async {
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
      DispatchQueue.main.async {
        self.title = self.item.title
        self.accessoryImage = ColorImage.from(self.item.title)
        self.synchronizeItemTitle()
      }
    }
  }
}
