import AppKit.NSWorkspace
import Defaults
import Foundation
import Logging
import Observation
import Sauce

/// Main-actor view model wrapping a `HistoryItem` `@Model`: holds the title,
/// highlights, keyboard shortcuts, and lazily generated thumbnail/preview images
/// for one row in the history list.
@MainActor
@Observable
class HistoryItemDecorator: Identifiable, Hashable, HasVisibility, VisibilityObserving {
  /// Identity-only equality. `nonisolated` so it satisfies `Equatable`/
  /// `Hashable` from a `@MainActor` type; reads only the `let` UUID `id`
  /// (Sendable). `title`/`attributedTitle` are main-mutated vars, so hashing
  /// them would cross isolation; `@Observable` already drives SwiftUI updates on
  /// title change, so `Hashable` need only reflect identity.
  nonisolated static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  /// Preview decode/placeholder target size. The longest side is capped at
  /// `Defaults[.imageMaxPreviewPixels]` (default 800) to bound the off-main
  /// decode + on-main composite cost; 0 = no artificial cap (decodes at screen
  /// resolution — visually identical to "original" in the slideout pane, without
  /// the 256 MB+ bitmap a true native decode of a huge image would cost).
  /// Configurable in Appearance settings.
  static var previewImageSize: NSSize {
    let raw = NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536)
    let cap = Defaults[.imageMaxPreviewPixels]
    return cap > 0 ? capped(raw, max: CGFloat(cap)) : raw
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
  /// Whether this row is part of the current selection.
  var isSelected: Bool {
    return selectionIndex != -1
  }
  var shortcuts: [KeyShortcut] = []

  /// Display name of the source app (or `"iCloud"` for Universal Clipboard).
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

  /// Whether the item carries image data.
  var hasImage: Bool { imageData != nil }

  var previewImageGenerationTask: Task<(), Never>?
  var thumbnailImageGenerationTask: Task<(), Never>?
  var previewImage: NSImage?
  var thumbnailImage: NSImage?
  var applicationImage: ApplicationImage
  private var isInvalidated = false
  /// The item's image blob, loaded lazily on first use — not at decoration time.
  ///
  /// `History.load()` decorates every item; eagerly copying each `imageData`
  /// blob (~1MB) in `init` faulted + copied N blobs onto the main thread during
  /// cold-open — a large share of the measured image-many load block. Deferring
  /// the read to the first thumbnail/preview generation means only items that
  /// actually render an image (the visible window) ever read their blob; the
  /// other ~N−visible fault nothing.
  ///
  /// Mirrors the `textPreviewCache` lazy pattern below. `isInvalidated` is
  /// guarded so a post-deletion access never faults a torn `@Model` (the eager
  /// copy doubled as invalidation insurance; the guard restores that safety).
  @ObservationIgnored private var imageDataCache: Data?
  @ObservationIgnored private var imageDataCacheLoaded = false
  private var imageData: Data? {
    if !imageDataCacheLoaded {
      imageDataCache = isInvalidated ? nil : item.imageData
      imageDataCacheLoaded = true
    }
    return imageDataCache
  }
  /// Process-wide shared `ImageProcessor` (cache-backed) used when a caller
  /// doesn't inject its own. `AppDelegate` feeds the same instance into the
  /// ingestor so the cache is shared across the ingest and view paths.
  private let imageProcessor: ImageProcessing
  @ObservationIgnored private var textPreviewCache: String?
  @ObservationIgnored private var textPreviewCacheLimit: Int = -1

  // Bounded by HistoryItem.textPreviewLimit (configurable; 0 = full text). The
  // cache auto-invalidates when the limit changes so the next read picks up the
  // new value without a relaunch.
  var text: String {
    let limit = HistoryItem.textPreviewLimit
    if let textPreviewCache, textPreviewCacheLimit == limit {
      return textPreviewCache
    }

    let preview = item.previewableTextPrefix(maxLength: limit)
    textPreviewCache = preview
    textPreviewCacheLimit = limit
    return preview
  }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  /// Identity-only hash (mirrors `==`).
  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  private(set) var item: HistoryItem

  private let logger = Logger(label: "org.p0deje.Maccy")

  /// Process-wide shared off-main image processor. `let` (lazy, thread-safe
  /// init) so every decorator that takes the default shares one `ImageProcessor`
  /// and therefore one `ThumbnailCache`; `AppDelegate` passes this same instance
  /// into the ingestor so thumbnails are cached across both paths.
  static let defaultImageProcessor: any ImageProcessing = ImageProcessor(cache: ThumbnailCache())

  /// Creates a decorator for `item`, seeding title/shortcuts and the app icon,
  /// and starting pin/title observation.
  init(
    _ item: HistoryItem,
    shortcuts: [KeyShortcut] = [],
    imageProcessor: ImageProcessing = HistoryItemDecorator.defaultImageProcessor
  ) {
    self.item = item
    self.shortcuts = shortcuts
    self.title = item.title
    self.imageProcessor = imageProcessor
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)

    synchronizeItemPin()
    synchronizeItemTitle()
  }

  /// Kicks off thumbnail generation (off-main) if not already cached or in flight.
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

  /// Kicks off preview generation (off-main) if not already cached or in flight.
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

  /// Awaits the preview image, generating it if needed. `nil` after completion
  /// means the data was invalid or the generation was cancelled; cancellation
  /// is expected when the decorator is invalidated/superseded, so only genuine
  /// decode failures are logged (they would otherwise look like an empty clipboard).
  func asyncGetPreviewImage() async -> NSImage? {
    if let image = previewImage {
      return image
    }
    ensurePreviewImage()
    _ = await previewImageGenerationTask?.result
    if previewImage == nil, !isInvalidated {
      logger.error("preview image generation produced no image (corrupt data)")
    }
    return previewImage
  }

  /// Marks the decorator invalidated and drops all transient images.
  func invalidate() {
    isInvalidated = true
    cleanupImages()
  }

  /// Drops all transient images (preview, thumbnail, decoded cache, text/blob).
  func cleanupImages() {
    releaseTransientImages(.invalidate)
  }

  /// Drops transient images per `reason`. `.scrollOut` keeps the cheap thumbnail
  /// (list scroll reuses it fast) and frees only the preview bitmap; the heavier
  /// reasons also clear thumbnail/text/blob state.
  func releaseTransientImages(_ reason: ReleaseReason) {
    switch reason {
    case .scrollOut:
      previewImageGenerationTask?.cancel()
      previewImageGenerationTask = nil
      previewImage = nil
    case .settingChange, .memoryWarning, .invalidate:
      thumbnailImageGenerationTask?.cancel()
      previewImageGenerationTask?.cancel()
      thumbnailImageGenerationTask = nil
      previewImageGenerationTask = nil
      thumbnailImage = nil
      previewImage = nil
      textPreviewCache = nil
      imageDataCache = nil
      imageDataCacheLoaded = false
    }
  }

  // MARK: - Viewport visibility

  func onAppearInViewport() {
    ensureThumbnailImage()
  }

  func onDisappearFromViewport() {
    releaseTransientImages(.scrollOut)
  }

  /// Cancels an in-flight preview decode and drops the task handle, WITHOUT
  /// clearing a cached `previewImage` (unlike `cleanupImages`). Called when the
  /// lead selection moves off this item (`NavigationManager.leadHistoryItem`
  /// `didSet`) so a stale decode doesn't keep occupying the single serial
  /// `ImageProcessor` actor — previously only `invalidate`/`cleanupImages`
  /// cancelled, so navigating away left the old preview decoding to completion,
  /// piling up behind the actor queue. A re-select of an already-decoded item
  /// stays instant (cache hit in `asyncGetPreviewImage`); a re-select of a
  /// cancelled-uncached item re-kicks via `ensurePreviewImage` (the nil'd handle
  /// lets it through).
  func cancelPreviewGeneration() {
    previewImageGenerationTask?.cancel()
    previewImageGenerationTask = nil
  }

  /// Kicks off (preview, thumbnail) generation. Used by `sizeImages()` for the
  /// benchmark/tests that want both rendered; production paths call the
  /// individual `ensure*` accessors as the view appears.
  func sizeImages() {
    ensurePreviewImage()
    ensureThumbnailImage()
  }

  // MARK: - Off-main generation

  /// Structured (non-detached) task that runs the decode + downsample on the
  /// `imageProcessor` actor, then publishes the result on the main actor.
  /// Cancellation propagates: `cleanupImages`/`invalidate` cancel the stored
  /// handle, and the actor's `Task.isCancelled` checkpoints turn that into an
  /// early `nil` before any decode. Captures only Sendable values
  /// (`imageData`, `imageProcessor`) — never the old `self.image()` (that would
  /// re-introduce main-thread `NSImage(data:)` decode). The closure is
  /// `@MainActor`-isolated so the cheap pre/post work runs on main while the
  /// `await processor.thumbnail(...)` hop runs the decode on the actor.
  private func startThumbnailGeneration() -> Task<(), Never> {
    guard let imageData else {
      return Task {}
    }
    let processor = imageProcessor
    let target = HistoryItemDecorator.thumbnailImageSize
    return Task { @MainActor [weak self] in
      #if DEBUG
      if PerfRecorder.enabled {
        // latency = total (kick → published); mainBlock = on-main portion
        // (total − the off-main decode await).
        let clock = ContinuousClock()
        let totalStart = clock.now
        let decodeStart = clock.now
        let image = await processor.thumbnail(for: imageData, max: target)
        let decode = decodeStart.duration(to: clock.now)
        guard let self, !self.isInvalidated else {
          return
        }
        self.thumbnailImage = image
        let total = totalStart.duration(to: clock.now)
        PerfRecorder.shared.recordThumbnail(
          latency: total,
          mainBlock: max(Duration.zero, total - decode)
        )
        return
      }
      #endif
      let image = await processor.thumbnail(for: imageData, max: target)
      guard let self, !self.isInvalidated else {
        return
      }
      self.thumbnailImage = image
    }
  }

  /// Structured task mirroring `startThumbnailGeneration` for the larger preview
  /// image; decode + downsample run off-main, result published on main, with the
  /// same cancellation propagation. Records latency on decode completion (not on
  /// the `await` in `asyncGetPreviewImage`) so a render is captured even if the
  /// requesting view is torn down mid-decode — the generation task is owned by
  /// the decorator, not the view.
  private func startPreviewGeneration() -> Task<(), Never> {
    guard let imageData else {
      return Task {}
    }
    let processor = imageProcessor
    let target = HistoryItemDecorator.previewImageSize
    return Task { @MainActor [weak self] in
      #if DEBUG
      if PerfRecorder.enabled {
        // latency = total (kick → published); mainBlock = on-main portion
        // (total − the off-main decode await).
        let clock = ContinuousClock()
        let totalStart = clock.now
        let decodeStart = clock.now
        let image = await processor.preview(for: imageData, max: target)
        let decode = decodeStart.duration(to: clock.now)
        guard let self, !self.isInvalidated else {
          return
        }
        self.previewImage = image
        let total = totalStart.duration(to: clock.now)
        PerfRecorder.shared.recordPreview(
          latency: total,
          mainBlock: max(Duration.zero, total - decode)
        )
        return
      }
      #endif
      let image = await processor.preview(for: imageData, max: target)
      guard let self, !self.isInvalidated else {
        return
      }
      self.previewImage = image
    }
  }

  /// Builds `attributedTitle` with `query`'s `ranges` styled per the highlight
  /// preference; clears highlighting when `query` or `title` is empty.
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

  /// Toggles the item's pin between its current value and a free pin slot.
  func togglePin() {
    if item.pin != nil {
      item.pin = nil
    } else if let pin = HistoryItem.randomAvailablePin {
      item.pin = pin
    }
  }

  /// Re-syncs this decorator's pin shortcut whenever the model's `pin` changes,
  /// re-arming itself each change until invalidated.
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

  /// Re-syncs this decorator's `title` whenever the model's title changes,
  /// re-arming itself each change until invalidated.
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
