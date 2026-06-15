import AppKit.NSWorkspace
import Defaults
import Foundation
import Logging
import Observation
import Sauce

@Observable
class HistoryItemDecorator: Identifiable, Hashable, HasVisibility, @unchecked Sendable {
  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  /// Upper bound on the longest side of a preview image, in pixels (IMG-022).
  ///
  /// Decoding + downsampling a full visibleFrame-sized image (potentially
  /// thousands of pixels per side) on every preview open is the BS-3 bottleneck
  /// this batch moves off-main. Capping the preview target bounds the worst-case
  /// decode cost regardless of screen size; 1600² keeps previews crisp on
  /// retina displays while staying well under the unbounded visibleFrame target
  /// the old `NSImage(data:)` path used.
  private static let previewMaxPixels: CGFloat = 1600

  static var previewImageSize: NSSize {
    let raw = NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536)
    return capped(raw, max: previewMaxPixels)
  }
  static var thumbnailImageSize: NSSize { NSSize(width: 340, height: max(1, Defaults[.imageMaxHeight])) }

  /// Returns `size` with its longer side clamped to `max`, preserving aspect.
  private static func capped(_ size: NSSize, max maxPixels: CGFloat) -> NSSize {
    let longest = max(size.width, size.height)
    guard longest > maxPixels, longest > 0 else {
      return size
    }
    let scale = maxPixels / longest
    return NSSize(width: size.width * scale, height: size.height * scale)
  }

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

  var hasImage: Bool { imageData != nil }

  var previewImageGenerationTask: Task<(), Never>?
  var thumbnailImageGenerationTask: Task<(), Never>?
  var previewImage: NSImage?
  var thumbnailImage: NSImage?
  var applicationImage: ApplicationImage
  private var isInvalidated = false
  private let imageData: Data?
  /// Process-wide shared `ImageProcessor` (cache-backed) used when a caller
  /// doesn't inject its own. AppDelegate (BS-3.8) feeds the SAME instance into
  /// the ingestor so the cache is shared across the ingest + view paths.
  private let imageProcessor: ImageProcessing
  @ObservationIgnored private var textPreviewCache: String?

  // 10k characters seems to be more than enough on large displays.
  var text: String {
    if let textPreviewCache {
      return textPreviewCache
    }

    let preview = item.previewableTextPrefix(maxLength: HistoryItem.textPreviewLimit)
    textPreviewCache = preview
    return preview
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

  private let logger = Logger(label: "org.p0deje.Maccy")

  /// Process-wide shared off-main image processor. `let` (lazy, thread-safe
  /// init) so every decorator that takes the default shares one `ImageProcessor`
  /// and therefore one `ThumbnailCache`; AppDelegate passes this same instance
  /// into the ingestor in BS-3.8 so thumbnails are cached across both paths.
  static let defaultImageProcessor: any ImageProcessing = ImageProcessor(cache: ThumbnailCache())

  @MainActor
  init(
    _ item: HistoryItem,
    shortcuts: [KeyShortcut] = [],
    imageProcessor: ImageProcessing = HistoryItemDecorator.defaultImageProcessor
  ) {
    self.item = item
    self.shortcuts = shortcuts
    self.title = item.title
    self.imageData = item.imageData
    self.imageProcessor = imageProcessor
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)

    synchronizeItemPin()
    synchronizeItemTitle()
  }

  @MainActor
  func ensureThumbnailImage() {
    guard imageData != nil else {
      return
    }
    guard thumbnailImage == nil else {
      return
    }
    guard thumbnailImageGenerationTask == nil else {
      return
    }
    thumbnailImageGenerationTask = startThumbnailGeneration()
  }

  @MainActor
  func ensurePreviewImage() {
    guard imageData != nil else {
      return
    }
    guard previewImage == nil else {
      return
    }
    guard previewImageGenerationTask == nil else {
      return
    }
    previewImageGenerationTask = startPreviewGeneration()
  }

  @MainActor
  func asyncGetPreviewImage() async -> NSImage? {
    if let image = previewImage {
      return image
    }
    ensurePreviewImage()
    _ = await previewImageGenerationTask?.result
    // nil after completion means either the image data was invalid or the
    // generation task was cancelled (IMG-023). Cancellation is expected when
    // the decorator is invalidated/superseded, so only log genuine decode
    // failures — those would otherwise look like an empty clipboard.
    if previewImage == nil, !isInvalidated {
      logger.error("preview image generation produced no image (corrupt data)")
    }
    return previewImage
  }

  @MainActor
  func invalidate() {
    isInvalidated = true
    cleanupImages()
  }

  @MainActor
  func cleanupImages() {
    thumbnailImageGenerationTask?.cancel()
    previewImageGenerationTask?.cancel()
    thumbnailImageGenerationTask = nil
    previewImageGenerationTask = nil
    thumbnailImage?.recache()
    previewImage?.recache()
    thumbnailImage = nil
    previewImage = nil
  }

  /// Kicks off (preview, thumbnail) generation. Used by `sizeImages()` for the
  /// benchmark/tests that want both rendered; production paths call the
  /// individual `ensure*` accessors as the view appears.
  @MainActor
  func sizeImages() {
    ensurePreviewImage()
    ensureThumbnailImage()
  }

  // MARK: - Off-main generation

  /// Structured (non-detached) task that runs the decode + downsample on the
  /// `imageProcessor` actor, then hops back to the main actor to publish the
  /// result. Cancellation propagates: `cleanupImages`/`invalidate` cancel the
  /// stored handle, and the actor's `Task.isCancelled` checkpoints (IMG-023)
  /// turn that into an early nil before any decode. Captures only Sendable
  /// values (`imageData`, `imageProcessor`) — never `self.image()` (that would
  /// re-introduce main-thread `NSImage(data:)` decode).
  private func startThumbnailGeneration() -> Task<(), Never> {
    guard let imageData else {
      return Task {}
    }
    let processor = imageProcessor
    let target = HistoryItemDecorator.thumbnailImageSize
    return Task { [weak self] in
      let image = await processor.thumbnail(for: imageData, max: target)
      await MainActor.run {
        guard let self, !self.isInvalidated else {
          return
        }
        self.thumbnailImage = image
      }
    }
  }

  private func startPreviewGeneration() -> Task<(), Never> {
    guard let imageData else {
      return Task {}
    }
    let processor = imageProcessor
    let target = HistoryItemDecorator.previewImageSize
    return Task { [weak self] in
      let image = await processor.preview(for: imageData, max: target)
      await MainActor.run {
        guard let self, !self.isInvalidated else {
          return
        }
        self.previewImage = image
      }
    }
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
    } else if let pin = HistoryItem.randomAvailablePin {
      item.pin = pin
    }
  }

  private func synchronizeItemPin() {
    guard !isInvalidated else {
      return
    }

    _ = withObservationTracking {
      item.pin
    } onChange: {
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.isInvalidated else {
          return
        }
        if let pin = self.item.pin {
          self.shortcuts = KeyShortcut.create(character: pin)
        }
        self.synchronizeItemPin()
      }
    }
  }

  private func synchronizeItemTitle() {
    guard !isInvalidated else {
      return
    }

    _ = withObservationTracking {
      item.title
    } onChange: {
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.isInvalidated else {
          return
        }
        self.title = self.item.title
        self.synchronizeItemTitle()
      }
    }
  }
}
