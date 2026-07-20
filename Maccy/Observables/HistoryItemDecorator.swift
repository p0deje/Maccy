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

  var hasImage: Bool { item.imageData != nil }

  var previewImageGenerationTask: Task<Void, Never>?
  var thumbnailImageGenerationTask: Task<Void, Never>?
  var previewImage: NSImage?
  var thumbnailImage: NSImage?
  var applicationImage: ApplicationImage

  // 10k characters seems to be more than enough on large displays
  var text: String { item.previewableText.shortened(to: 10_000) }

  @ObservationIgnored private var cachedPreviewText: String?

  @MainActor
  func asyncGetPreviewText() async -> String {
    if let cached = cachedPreviewText { return cached }

    // Fast paths: fileURLs and plain text don't need background parsing
    let fileURLs = item.fileURLs
    if !fileURLs.isEmpty {
      let result = fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
        .shortened(to: 10_000)
      if !result.isEmpty {
        cachedPreviewText = result
        return result
      }
    }

    if let plainText = item.text, !plainText.isEmpty {
      let result = plainText.shortened(to: 10_000)
      cachedPreviewText = result
      return result
    }

    // Slow path: only read RTF/HTML data if needed, parse in background
    let rtfData = item.rtfData
    let htmlData = item.htmlData
    let itemTitle = item.title

    let result = await Task.detached {
      if let data = rtfData,
         let rtf = NSAttributedString(rtf: data, documentAttributes: nil),
         !rtf.string.isEmpty {
        return rtf.string.shortened(to: 10_000)
      } else if let data = htmlData,
                let html = NSAttributedString(html: data, documentAttributes: nil),
                !html.string.isEmpty {
        return html.string.shortened(to: 10_000)
      } else {
        return itemTitle.shortened(to: 10_000)
      }
    }.value

    cachedPreviewText = result
    return result
  }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  func hash(into hasher: inout Hasher) {
    // We need to hash title and attributedTitle, so SwiftUI knows it needs to update the view if they chage
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

    synchronizeItemPin()
    synchronizeItemTitle()
  }

  @MainActor
  func ensureThumbnailImage() {
    guard let data = item.imageData else {
      return
    }
    guard thumbnailImage == nil else {
      return
    }
    guard thumbnailImageGenerationTask == nil else {
      return
    }
    let targetSize = HistoryItemDecorator.thumbnailImageSize
    thumbnailImageGenerationTask = Task.detached { [weak self] in
      guard let nsImage = NSImage(data: data) else { return }
      let resized = nsImage.resized(to: targetSize)
      await MainActor.run {
        self?.thumbnailImage = resized
      }
    }
  }

  @MainActor
  func ensurePreviewImage() {
    guard let data = item.imageData else {
      return
    }
    guard previewImage == nil else {
      return
    }
    guard previewImageGenerationTask == nil else {
      return
    }
    let targetSize = HistoryItemDecorator.previewImageSize
    previewImageGenerationTask = Task.detached { [weak self] in
      guard let nsImage = NSImage(data: data) else { return }
      let resized = nsImage.resized(to: targetSize)
      await MainActor.run {
        self?.previewImage = resized
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
    thumbnailImage?.recache()
    previewImage?.recache()
    thumbnailImage = nil
    previewImage = nil
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
        self.synchronizeItemTitle()
      }
    }
  }
}
