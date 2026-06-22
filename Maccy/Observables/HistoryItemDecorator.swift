import AppKit.NSWorkspace
import Defaults
import Foundation
import Logging
import Observation
import Sauce

@Observable
// swiftlint:disable:next type_body_length
class HistoryItemDecorator: Identifiable, Hashable, HasVisibility, @unchecked Sendable {
  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  /// Upper bound on the longest side of a preview image, in pixels (IMG-022).
  ///
  /// Decoding + downsampling a full visibleFrame-sized image (potentially
  /// thousands of pixels per side) on every preview open is the BS-3 bottleneck
  /// this batch moves off-main. Capping the preview target bounds the worst-case
  /// decode cost regardless of screen size.
  ///
  /// 800² (was 1600², 2026-06-22): the preview pane renders in a slideout that
  /// is far smaller than the screen, so 1600² was over-sampled — the extra
  /// resolution cost both the off-main decode AND the on-main render composite
  /// (a ~10 MB bitmap at 1600² vs ~2.5 MB at 800²). 800² is display-appropriate
  /// for the slideout and ~4× the decode/render throughput. A preview only needs
  /// to be recognizable (the full image is pasted on select), not pixel-perfect.
  /// Tunable up if a large slideout looks soft.
  private static let previewMaxPixels: CGFloat = 800

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
  /// The item's image blob, loaded lazily on first use — not at decoration time.
  ///
  /// BS-6 (`img-fullres-dup-storage`): `History.load()` decorates every item,
  /// and eagerly copying each `imageData` blob (~1MB) in `init` faulted + copied
  /// N blobs onto the main thread during cold-open — a large share of the
  /// measured ~0.999s image-many load block. Deferring the read to the first
  /// thumbnail/preview generation means only items that actually render an image
  /// (the visible window) ever read their blob; the other ~N−visible fault nothing.
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

  /// Cancels an in-flight preview decode and drops the task handle, WITHOUT
  /// clearing a cached `previewImage` (unlike `cleanupImages`). Called when the
  /// lead selection moves off this item (`NavigationManager.leadHistoryItem`
  /// didSet) so a stale decode doesn't keep occupying the single serial
  /// `ImageProcessor` actor — the BS-3 收尾 of the IMG-023 cancellation gap
  /// (previously only `invalidate`/`cleanupImages` cancelled, so navigating
  /// away left the old preview decoding to completion, piling up behind the
  /// actor queue → the 1.5s spike; mouse-hover worst case). A re-select of an
  /// already-decoded item stays instant (cache hit in `asyncGetPreviewImage`);
  /// a re-select of a cancelled-uncached item re-kicks via `ensurePreviewImage`
  /// (the nil'd handle lets it through).
  @MainActor
  func cancelPreviewGeneration() {
    previewImageGenerationTask?.cancel()
    previewImageGenerationTask = nil
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
  /// `imageProcessor` actor, then publishes the result on the main actor.
  /// Cancellation propagates: `cleanupImages`/`invalidate` cancel the stored
  /// handle, and the actor's `Task.isCancelled` checkpoints (IMG-023) turn that
  /// into an early nil before any decode. Captures only Sendable values
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
        // method=B instrumentation: latency = total (kick → published);
        // mainBlock = on-main portion (total − the off-main decode await).
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

  private func startPreviewGeneration() -> Task<(), Never> {
    guard let imageData else {
      return Task {}
    }
    let processor = imageProcessor
    let target = HistoryItemDecorator.previewImageSize
    return Task { @MainActor [weak self] in
      #if DEBUG
      if PerfRecorder.enabled {
        // method=B instrumentation: record on decode COMPLETION (not on the
        // await in asyncGetPreviewImage) so a render is captured even if the
        // AsyncView that requested it is torn down mid-decode (e.g. rapid
        // selection navigation with .id(item.id) refreshing the preview). The
        // generation task is owned by the decorator, not the view, so it
        // completes regardless. latency = total (kick → published);
        // mainBlock = on-main portion (total − the off-main decode await).
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
