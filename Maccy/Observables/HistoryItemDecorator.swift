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

  var hasImage: Bool { item.image != nil }

  var previewImageGenerationTask: Task<(), Error>?
  var thumbnailImageGenerationTask: Task<(), Error>?
  var previewImage: NSImage?
  // 10k characters seems to be more than enough on large displays
  var previewText: String { item.previewableText.shortened(to: 10_000) }
  var thumbnailImage: NSImage?
  var applicationImage: ApplicationImage

  var text: String { previewText }

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
    if hasImage, let image = item.image {
      let size = image.pixelSize
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
    guard item.image != nil else {
      return
    }
    guard thumbnailImage == nil else {
      return
    }
    guard thumbnailImageGenerationTask == nil else {
      return
    }
    thumbnailImageGenerationTask = Task { [weak self] in
      self?.generateThumbnailImage()
    }
  }

  @MainActor
  func ensurePreviewImage() {
    guard item.image != nil else {
      return
    }
    guard previewImage == nil else {
      return
    }
    guard previewImageGenerationTask == nil else {
      return
    }
    previewImageGenerationTask = Task { [weak self] in
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
    guard let image = item.image else {
      return
    }
    thumbnailImage = image.resized(to: HistoryItemDecorator.thumbnailImageSize)
  }

  @MainActor
  private func generatePreviewImage() {
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
        self.synchronizeItemTitle()
      }
    }
  }
}
